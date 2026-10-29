//
//  CalendarService.swift
//  Docky
//

import AppKit
import Combine
import EventKit
import Foundation

final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    @Published private(set) var nextEvent: CalendarEventSnapshot?
    @Published private(set) var upcomingEvents: [CalendarEventSnapshot] = []
    /// Invitations the user has not answered yet, one row per event (a
    /// recurring invitation is listed once, at its next occurrence).
    @Published private(set) var pendingInvitations: [CalendarEventSnapshot] = []
    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorDescription: String?

    private let eventStore = EKEventStore()
    private var lastRefreshDate: Date?
    private var cancellables = Set<AnyCancellable>()
    private var rolloverTimer: Timer?

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)

        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: eventStore)
            .sink { [weak self] _ in
                self?.refresh(force: true)
            }
            .store(in: &cancellables)
    }

    func ensureFreshEvent() {
        refresh(force: false)
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    /// Event calendars for the per-widget picker; empty without read access.
    func availableCalendars() -> [CalendarChoice] {
        guard permissionStatus == .granted else { return [] }

        return eventStore.calendars(for: .event)
            .map { calendar in
                CalendarChoice(
                    identifier: calendar.calendarIdentifier,
                    title: calendar.title,
                    color: NSColor(cgColor: calendar.cgColor) ?? .white
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Docky's tri-state view of calendar access. `.writeOnly` counts as
    /// not-granted because the widget needs read access to show events.
    var permissionStatus: PermissionStatus {
        switch authorizationStatus {
        case .fullAccess, .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted, .writeOnly:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func refresh(force: Bool) {
        if !force,
           let lastRefreshDate,
           Date().timeIntervalSince(lastRefreshDate) < 300 {
            return
        }

        refreshAuthorizationStatus()
        lastErrorDescription = nil

        switch authorizationStatus {
        case .fullAccess, .authorized:
            loadNextEvent()
        case .writeOnly:
            nextEvent = nil
            upcomingEvents = []
            pendingInvitations = []
            isLoading = false
            lastErrorDescription = "Calendar read access is needed to show upcoming events."
        case .notDetermined:
            // Permission is requested lazily from the widget's Enable button,
            // never automatically on render. Leave the widget in its
            // call-to-action state until the user opts in.
            nextEvent = nil
            upcomingEvents = []
            pendingInvitations = []
            isLoading = false
        case .denied, .restricted:
            nextEvent = nil
            upcomingEvents = []
            pendingInvitations = []
            isLoading = false
            lastErrorDescription = "Enable Calendar access in Settings to show upcoming events."
        @unknown default:
            nextEvent = nil
            upcomingEvents = []
            pendingInvitations = []
            isLoading = false
            lastErrorDescription = "Calendar is unavailable right now."
        }
    }

    /// Requests calendar access in response to an explicit user action
    /// (the widget's Enable button). Loads events immediately on grant.
    func requestAccess() async -> Bool {
        let granted = await requestCalendarPermission()
        if granted {
            loadNextEvent()
        }
        return granted
    }

    private func requestCalendarPermission() async -> Bool {
        refreshAuthorizationStatus()

        switch authorizationStatus {
        case .fullAccess, .authorized:
            return true
        case .writeOnly, .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                eventStore.requestFullAccessToEvents { [weak self] granted, _ in
                    guard let self else {
                        continuation.resume(returning: granted)
                        return
                    }

                    Task { @MainActor in
                        self.refreshAuthorizationStatus()
                        continuation.resume(returning: granted)
                    }
                }
            }
        @unknown default:
            return false
        }
    }

    private func loadNextEvent() {
        isLoading = true

        let now = Date()
        let calendarRef = Calendar.autoupdatingCurrent
        let searchEnd = calendarRef.date(byAdding: .day, value: 30, to: now) ?? now.addingTimeInterval(2_592_000)
        let predicate = eventStore.predicateForEvents(withStart: now, end: searchEnd, calendars: nil)
        let staleStartCutoff = now.addingTimeInterval(-15 * 60)
        let startOfToday = calendarRef.startOfDay(for: now)
        let upcomingEvents = eventStore.events(matching: predicate)
            .filter {
                guard $0.endDate > now, $0.startDate >= startOfToday else { return false }
                return $0.isAllDay || $0.startDate >= staleStartCutoff
            }
            .sorted {
                if $0.startDate == $1.startDate {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.startDate < $1.startDate
            }

        // Declined invitations stay out of the "up next" surfaces; they are
        // still in Calendar, but the user already said they are not going.
        let attendingEvents = upcomingEvents.filter {
            CalendarEventSnapshot.responseStatus(for: $0) != .declined
        }
        let nextEvent = attendingEvents.first(where: { !$0.isAllDay }) ?? attendingEvents.first

        var seenInvitationIdentifiers = Set<String>()
        let invitationEvents = upcomingEvents.filter { event in
            guard CalendarEventSnapshot.responseStatus(for: event) == .pending else { return false }
            let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
            return seenInvitationIdentifiers.insert(identifier).inserted
        }

        self.nextEvent = nextEvent.map(CalendarEventSnapshot.init(event:))
        // Deeper window so per-widget calendar filtering still has events after exclusions.
        self.upcomingEvents = attendingEvents.prefix(20).map(CalendarEventSnapshot.init(event:))
        self.pendingInvitations = invitationEvents.prefix(10).map(CalendarEventSnapshot.init(event:))
        self.lastRefreshDate = now
        self.isLoading = false
        self.lastErrorDescription = nil
        scheduleRollover(after: nextEvent?.endDate)
    }

    /// Answers an invitation on the user's behalf. Returns `false` when the
    /// reply could not be written (no access, event gone, or this macOS
    /// version no longer exposes the setter) so the caller can fall back to
    /// opening the event in Calendar.
    @discardableResult
    func respond(to snapshot: CalendarEventSnapshot, with reply: CalendarInvitationReply) -> Bool {
        guard permissionStatus == .granted,
              let event = resolveEvent(for: snapshot),
              CalendarInvitationResponder.apply(reply.participantStatus, to: event) else {
            return false
        }

        do {
            // A recurring invitation is answered for the whole series from
            // the listed occurrence on, which is what Calendar does too.
            let span: EKSpan = event.hasRecurrenceRules ? .futureEvents : .thisEvent
            try eventStore.save(event, span: span, commit: true)
        } catch {
            eventStore.reset()
            lastErrorDescription = error.localizedDescription
            refresh(force: true)
            return false
        }

        refresh(force: true)
        return true
    }

    /// Finds the live `EKEvent` behind a snapshot. Matches on the occurrence
    /// start date first because `event(withIdentifier:)` only ever returns
    /// the first occurrence of a recurring event.
    private func resolveEvent(for snapshot: CalendarEventSnapshot) -> EKEvent? {
        let predicate = eventStore.predicateForEvents(
            withStart: snapshot.startDate.addingTimeInterval(-60),
            end: max(snapshot.endDate, snapshot.startDate).addingTimeInterval(60),
            calendars: nil
        )
        let occurrence = eventStore.events(matching: predicate).first { event in
            (event.eventIdentifier ?? event.calendarItemIdentifier) == snapshot.eventIdentifier
                && abs(event.startDate.timeIntervalSince(snapshot.startDate)) < 1
        }
        return occurrence ?? eventStore.event(withIdentifier: snapshot.eventIdentifier)
    }

    private func scheduleRollover(after endDate: Date?) {
        rolloverTimer?.invalidate()
        rolloverTimer = nil

        guard let endDate else { return }

        let fireDate = endDate.addingTimeInterval(1)
        if fireDate <= Date() {
            DispatchQueue.main.async { [weak self] in
                self?.refresh(force: true)
            }
            return
        }

        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            self?.refresh(force: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        rolloverTimer = timer
    }

    #if DEBUG
    func seedDummyDebugSnapshot() {
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let startDate = calendar.date(byAdding: .minute, value: 18, to: now) ?? now.addingTimeInterval(1_080)
        let endDate = calendar.date(byAdding: .minute, value: 63, to: now) ?? now.addingTimeInterval(3_780)

        let next = CalendarEventSnapshot(
            title: "Oriel demo review",
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            location: "Studio A",
            calendarTitle: "Work",
            color: NSColor.systemBlue,
            quickJoinURL: URL(string: "https://zoom.us/j/5551234567")
        )

        let dummyTwo = CalendarEventSnapshot(
            title: "Lunch with Priya",
            startDate: calendar.date(byAdding: .hour, value: 3, to: now) ?? now.addingTimeInterval(10_800),
            endDate: calendar.date(byAdding: .hour, value: 4, to: now) ?? now.addingTimeInterval(14_400),
            isAllDay: false,
            location: "Mission",
            calendarTitle: "Personal",
            color: NSColor.systemPink,
            quickJoinURL: nil
        )

        let dummyThree = CalendarEventSnapshot(
            title: "Sprint planning",
            startDate: calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400),
            endDate: calendar.date(byAdding: .day, value: 1, to: now)?.addingTimeInterval(3_600) ?? now.addingTimeInterval(90_000),
            isAllDay: false,
            location: "",
            calendarTitle: "Work",
            color: NSColor.systemBlue,
            quickJoinURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )

        let dummyFour = CalendarEventSnapshot(
            title: "Team offsite",
            startDate: calendar.date(byAdding: .day, value: 2, to: now) ?? now.addingTimeInterval(172_800),
            endDate: calendar.date(byAdding: .day, value: 2, to: now)?.addingTimeInterval(86_400) ?? now.addingTimeInterval(259_200),
            isAllDay: true,
            location: "Sausalito",
            calendarTitle: "Work",
            color: NSColor.systemOrange,
            quickJoinURL: nil
        )

        let dummyInvitation = CalendarEventSnapshot(
            title: "Design critique",
            startDate: calendar.date(byAdding: .day, value: 1, to: now)?.addingTimeInterval(7_200) ?? now.addingTimeInterval(93_600),
            endDate: calendar.date(byAdding: .day, value: 1, to: now)?.addingTimeInterval(10_800) ?? now.addingTimeInterval(97_200),
            isAllDay: false,
            location: "",
            calendarTitle: "Work",
            color: NSColor.systemPurple,
            quickJoinURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            responseStatus: .pending,
            organizerName: "Priya"
        )

        nextEvent = next
        upcomingEvents = [next, dummyTwo, dummyThree, dummyInvitation, dummyFour]
        pendingInvitations = [dummyInvitation]
        lastRefreshDate = now
        isLoading = false
        lastErrorDescription = nil
        scheduleRollover(after: endDate)
    }
    #endif
}

struct CalendarChoice: Identifiable, Equatable {
    let identifier: String
    let title: String
    let color: NSColor

    var id: String { identifier }
}

/// The current user's answer to an event they were invited to.
enum CalendarResponseStatus: String, Equatable {
    /// Not an invitation: the user owns the event or it has no attendees.
    case notInvited
    case pending
    case accepted
    case tentative
    case declined
}

/// The three answers the calendar widget offers for an invitation.
enum CalendarInvitationReply: String, CaseIterable, Identifiable {
    case accept
    case maybe
    case decline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accept: String(localized: "Yes")
        case .maybe: String(localized: "Maybe")
        case .decline: String(localized: "No")
        }
    }

    var symbolName: String {
        switch self {
        case .accept: "checkmark"
        case .maybe: "questionmark"
        case .decline: "xmark"
        }
    }

    var participantStatus: EKParticipantStatus {
        switch self {
        case .accept: .accepted
        case .maybe: .tentative
        case .decline: .declined
        }
    }
}

/// EventKit can read the user's answer to an invitation but has no public
/// way to change it. Calendar itself goes through a setter on `EKEvent`
/// that is not in the SDK headers; this looks that setter up at runtime
/// and reports `false` when it is missing, so a future macOS that removes
/// it degrades to "open the event in Calendar" instead of crashing.
enum CalendarInvitationResponder {
    private typealias StatusSetter = @convention(c) (AnyObject, Selector, Int) -> Void

    nonisolated static func apply(_ status: EKParticipantStatus, to event: EKEvent) -> Bool {
        for selectorName in ["setParticipationStatus:", "setSelfParticipantStatus:"] {
            let selector = NSSelectorFromString(selectorName)
            guard event.responds(to: selector),
                  let implementation = event.method(for: selector) else {
                continue
            }
            let setter = unsafeBitCast(implementation, to: StatusSetter.self)
            setter(event, selector, status.rawValue)
            return true
        }
        return false
    }
}

struct CalendarEventSnapshot: Equatable {
    let eventIdentifier: String
    let calendarIdentifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String
    let calendarTitle: String
    let color: NSColor
    let quickJoinURL: URL?
    let responseStatus: CalendarResponseStatus
    /// Display name of whoever sent the invitation; empty when unknown.
    let organizerName: String
    /// From a calendar that only informs (public holidays, the clock
    /// change, birthdays), not one of the person's own appointments.
    var isInformational: Bool = false

    nonisolated init(event: EKEvent) {
        eventIdentifier = event.eventIdentifier ?? event.calendarItemIdentifier
        calendarIdentifier = event.calendar.calendarIdentifier
        let trimmedTitle = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        title = trimmedTitle.isEmpty ? "Untitled Event" : trimmedTitle
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        calendarTitle = event.calendar.title
        isInformational = event.calendar.type == .birthday
            || Self.informationalTitles.contains { event.calendar.title.localizedCaseInsensitiveContains($0) }
        color = NSColor(cgColor: event.calendar.cgColor) ?? .white
        quickJoinURL = Self.resolveQuickJoinURL(for: event, location: location)
        responseStatus = Self.responseStatus(for: event)
        organizerName = event.organizer?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// The user's own answer on `event`, read from the attendee EventKit
    /// flags as the current user. Events the user organizes, and events
    /// with no attendee list, are not invitations.
    nonisolated static func responseStatus(for event: EKEvent) -> CalendarResponseStatus {
        guard event.organizer?.isCurrentUser != true,
              let selfAttendee = event.attendees?.first(where: { $0.isCurrentUser }) else {
            return .notInvited
        }

        switch selfAttendee.participantStatus {
        case .pending:
            return .pending
        case .accepted:
            return .accepted
        case .tentative:
            return .tentative
        case .declined:
            return .declined
        default:
            return .notInvited
        }
    }

    #if DEBUG
    init(
        eventIdentifier: String = UUID().uuidString,
        calendarIdentifier: String = UUID().uuidString,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        location: String,
        calendarTitle: String,
        color: NSColor,
        quickJoinURL: URL?,
        responseStatus: CalendarResponseStatus = .notInvited,
        organizerName: String = ""
    ) {
        self.eventIdentifier = eventIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.calendarTitle = calendarTitle
        self.color = color
        self.quickJoinURL = quickJoinURL
        self.responseStatus = responseStatus
        self.organizerName = organizerName
    }
    #endif

    /// Names of the holiday calendars macOS and Google offer, in French and
    /// English; the clock change comes with them.
    private nonisolated static let informationalTitles = [
        "férié", "ferie", "fête", "fete", "holiday", "vacances scolaires", "anniversaire", "birthday",
    ]

    private nonisolated static func resolveQuickJoinURL(for event: EKEvent, location: String) -> URL? {
        if let directURL = normalizedJoinURL(event.url) {
            return directURL
        }

        if let notes = event.notes,
           let notesURL = firstJoinURL(in: notes) {
            return notesURL
        }

        if let locationURL = firstJoinURL(in: location) {
            return locationURL
        }

        return nil
    }

    private nonisolated static func firstJoinURL(in text: String) -> URL? {
        guard !text.isEmpty else {
            return nil
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []

        for match in matches {
            guard let range = Range(match.range, in: text) else {
                continue
            }

            let candidate = String(text[range])
            if let url = normalizedJoinURL(URL(string: candidate)) {
                return url
            }
        }

        return nil
    }

    private nonisolated static func normalizedJoinURL(_ url: URL?) -> URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "zoommtg", "msteams", "webex", "facetime"].contains(scheme) else {
            return nil
        }

        return url
    }
}
