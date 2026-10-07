//
//  ClaudeActivityService.swift
//  Docky
//
//  Feeds the Claude widget with what Claude is doing right now, from two
//  sources that work very differently:
//
//  1. Claude Code sessions running on this Mac (terminal, or the desktop
//     app's Code tab in Local mode). Claude Code can run a command at each
//     step of a session ("hooks"). Once connected, a one-line hook drops
//     every event as a small JSON file into
//     ~/Library/Application Support/Docky/ClaudeActivity/, and this
//     service drains that folder once a second. That gives the prompt,
//     the tool in use, and whether the session is waiting for an answer.
//
//  2. Tasks in the Claude desktop app, which run in the cloud. Nothing on
//     this Mac reports their progress, so the only thing available is the
//     title of the app's windows, read through the Accessibility-backed
//     window registry Docky already keeps. That says which task is open,
//     not which step it is on.
//
//  Connecting Claude Code edits ~/.claude/settings.json, so it only ever
//  happens from an explicit button press, keeps a one-time backup of the
//  file, and can be undone with `disconnectClaudeCode()`.
//

import AppKit
import ApplicationServices
import Combine
import Foundation

struct ClaudeCodeSessionActivity: Identifiable, Equatable {
    enum State: Equatable {
        /// Claude is in the middle of a turn.
        case working
        /// Claude stopped to ask for a permission or an answer.
        case waiting
        /// The last turn finished.
        case idle
    }

    let id: String
    var projectName: String
    var prompt: String
    var step: String
    var state: State
    var updatedAt: Date
}

/// The single line the dock tile shows.
struct ClaudeActivityHeadline: Equatable {
    let title: String
    let detail: String
    let state: ClaudeCodeSessionActivity.State
}

final class ClaudeActivityService: ObservableObject {
    static let shared = ClaudeActivityService()
    static let claudeDesktopBundleIdentifier = "com.anthropic.claudefordesktop"

    /// Local Claude Code sessions, most recently active first.
    @Published private(set) var sessions: [ClaudeCodeSessionActivity] = []
    /// Titles of the Claude desktop app's open windows.
    @Published private(set) var desktopTaskTitles: [String] = []
    @Published private(set) var isClaudeDesktopRunning = false
    @Published private(set) var isClaudeCodeConnected = false
    @Published private(set) var connectionError: String?

    private let fileManager = FileManager.default
    private var sessionsByID: [String: ClaudeCodeSessionActivity] = [:]
    private var timer: Timer?

    private init() {}

    // MARK: - Lifecycle

    /// Starts polling. Called by the widget when it appears; safe to call
    /// repeatedly.
    func start() {
        guard timer == nil else { return }

        try? fileManager.createDirectory(at: Self.spoolDirectoryURL, withIntermediateDirectories: true)
        refreshConnectionState()
        poll()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    var hasAccessibilityAccess: Bool {
        AXIsProcessTrusted()
    }

    /// What the tile leads with: a session that needs the user first, then
    /// one that is working, then the task open in the desktop app, then the
    /// most recently finished session.
    var headline: ClaudeActivityHeadline? {
        if let waiting = sessions.first(where: { $0.state == .waiting }) {
            return ClaudeActivityHeadline(
                title: waiting.projectName,
                detail: waiting.step.isEmpty ? "Needs your answer" : waiting.step,
                state: .waiting
            )
        }

        if let working = sessions.first(where: { $0.state == .working }) {
            return ClaudeActivityHeadline(
                title: working.projectName,
                detail: working.step.isEmpty ? working.prompt : working.step,
                state: .working
            )
        }

        if let title = desktopTaskTitles.first {
            return ClaudeActivityHeadline(title: title, detail: "Open in Claude", state: .idle)
        }

        if let finished = sessions.first {
            return ClaudeActivityHeadline(
                title: finished.projectName,
                detail: finished.prompt.isEmpty ? "Finished" : "Finished: \(finished.prompt)",
                state: .idle
            )
        }

        return nil
    }

    func openClaudeDesktop() {
        WorkspaceService.shared.activateOrOpen(bundleIdentifier: Self.claudeDesktopBundleIdentifier)
    }

    // MARK: - Polling

    private func poll() {
        let changedSessions = drainSpool()
        let expired = expireStaleSessions()
        if changedSessions || expired {
            publishSessions()
        }
        refreshDesktopTasks()
    }

    /// Reads and removes every event file the hook has written since the
    /// last pass, oldest first. Returns whether any session changed.
    private func drainSpool() -> Bool {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: Self.spoolDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        var events: [SpooledEvent] = []
        for url in urls where url.pathExtension == "json" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            events.append(SpooledEvent(url: url, date: values?.contentModificationDate ?? Date()))
        }

        guard !events.isEmpty else {
            return false
        }

        events.sort { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.url.lastPathComponent < rhs.url.lastPathComponent
            }
            return lhs.date < rhs.date
        }

        for event in events {
            if let data = try? Data(contentsOf: event.url),
               let object = try? JSONSerialization.jsonObject(with: data),
               let payload = object as? [String: Any] {
                apply(payload, at: event.date)
            }
            try? fileManager.removeItem(at: event.url)
        }

        return true
    }

    private struct SpooledEvent {
        let url: URL
        let date: Date
    }

    private func apply(_ payload: [String: Any], at date: Date) {
        guard let sessionID = payload["session_id"] as? String, !sessionID.isEmpty,
              let eventName = payload["hook_event_name"] as? String else {
            return
        }

        if eventName == "SessionEnd" {
            sessionsByID[sessionID] = nil
            return
        }

        var session = sessionsByID[sessionID] ?? ClaudeCodeSessionActivity(
            id: sessionID,
            projectName: "Claude Code",
            prompt: "",
            step: "",
            state: .idle,
            updatedAt: date
        )

        if let workingDirectory = payload["cwd"] as? String, !workingDirectory.isEmpty {
            session.projectName = URL(fileURLWithPath: workingDirectory).lastPathComponent
        }

        switch eventName {
        case "UserPromptSubmit":
            let prompt: String = payload["prompt"] as? String ?? ""
            session.prompt = Self.singleLine(prompt, limit: 140)
            session.step = "Thinking"
            session.state = .working
        case "PreToolUse":
            let toolName: String = payload["tool_name"] as? String ?? ""
            let toolInput: [String: Any] = payload["tool_input"] as? [String: Any] ?? [:]
            session.step = Self.stepDescription(toolName: toolName, input: toolInput)
            session.state = .working
        case "PostToolUse":
            // Also how a session leaves `.waiting`: the tool it asked
            // permission for has now run.
            session.state = .working
        case "Notification":
            let namedKind = payload["notification_type"] as? String
            let legacyKind = payload["type"] as? String
            let kind: String = namedKind ?? legacyKind ?? ""
            guard kind.contains("permission") || kind.contains("elicitation") else {
                return
            }
            let message: String = payload["message"] as? String ?? "Needs your answer"
            session.step = Self.singleLine(message, limit: 140)
            session.state = .waiting
        case "Stop":
            session.step = ""
            session.state = .idle
        default:
            return
        }

        session.updatedAt = date
        sessionsByID[sessionID] = session
    }

    /// A session that stops sending events was most likely closed without
    /// a final hook (terminal killed, Mac slept). Returns whether anything
    /// changed.
    private func expireStaleSessions() -> Bool {
        let now = Date()
        var changed = false

        for (identifier, session) in sessionsByID {
            let age = now.timeIntervalSince(session.updatedAt)
            if session.state != .idle, age > Self.activeSessionTimeout {
                var idle = session
                idle.state = .idle
                idle.step = ""
                sessionsByID[identifier] = idle
                changed = true
            } else if session.state == .idle, age > Self.finishedSessionLifetime {
                sessionsByID[identifier] = nil
                changed = true
            }
        }

        return changed
    }

    private func publishSessions() {
        let sorted = sessionsByID.values.sorted { $0.updatedAt > $1.updatedAt }
        if sorted != sessions {
            sessions = sorted
        }
    }

    private func refreshDesktopTasks() {
        let running = !NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.claudeDesktopBundleIdentifier)
            .isEmpty
        if running != isClaudeDesktopRunning {
            isClaudeDesktopRunning = running
        }

        var titles: [String] = []
        if running {
            for window in WindowRegistry.shared.windows(forBundleIdentifier: Self.claudeDesktopBundleIdentifier) {
                let title = Self.cleanedWindowTitle(window.windowTitle)
                if !title.isEmpty, !titles.contains(title) {
                    titles.append(title)
                }
            }
        }

        if titles != desktopTaskTitles {
            desktopTaskTitles = titles
        }
    }

    // MARK: - Claude Code connection

    /// Adds Docky's hook to ~/.claude/settings.json. Existing settings and
    /// hooks are kept; the file is backed up once, before the first edit.
    func connectClaudeCode() {
        updateClaudeSettings { hooks in
            for event in Self.hookEvents {
                var groups = try Self.hookGroups(in: hooks, for: event)
                let alreadyConnected = groups.contains { group in
                    Self.isDockyHookGroup(group)
                }
                if alreadyConnected {
                    continue
                }

                let entry: [String: Any] = ["type": "command", "command": Self.hookCommand]
                let entries: [[String: Any]] = [entry]
                var group: [String: Any] = ["hooks": entries]
                if Self.eventsTakingMatcher.contains(event) {
                    group["matcher"] = ""
                }
                groups.append(group)
                hooks[event] = groups
            }
        }
    }

    /// Removes Docky's hook and nothing else.
    func disconnectClaudeCode() {
        guard fileManager.fileExists(atPath: Self.claudeSettingsURL.path) else {
            refreshConnectionState()
            return
        }

        updateClaudeSettings { hooks in
            for event in Self.hookEvents {
                let groups = try Self.hookGroups(in: hooks, for: event)
                let remaining: [[String: Any]] = groups.filter { group in
                    !Self.isDockyHookGroup(group)
                }
                if remaining.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = remaining
                }
            }
        }
    }

    private func updateClaudeSettings(_ edit: (inout [String: Any]) throws -> Void) {
        do {
            let url = Self.claudeSettingsURL
            var root: [String: Any] = [:]

            if let data = try? Data(contentsOf: url), !data.isEmpty {
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw ClaudeSettingsError.unexpectedShape
                }
                root = object

                let backupURL = url.appendingPathExtension("docky-backup")
                if !fileManager.fileExists(atPath: backupURL.path) {
                    try data.write(to: backupURL)
                }
            }

            var hooks: [String: Any] = [:]
            if let existing = root["hooks"] {
                guard let dictionary = existing as? [String: Any] else {
                    throw ClaudeSettingsError.unexpectedShape
                }
                hooks = dictionary
            }

            try edit(&hooks)
            if hooks.isEmpty {
                root.removeValue(forKey: "hooks")
            } else {
                root["hooks"] = hooks
            }

            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            try data.write(to: url, options: .atomic)
            connectionError = nil
        } catch ClaudeSettingsError.unexpectedShape {
            connectionError = "~/.claude/settings.json has a shape Docky does not recognize, so it was left untouched."
        } catch {
            connectionError = error.localizedDescription
        }

        refreshConnectionState()
    }

    private func refreshConnectionState() {
        let contents = (try? String(contentsOf: Self.claudeSettingsURL, encoding: .utf8)) ?? ""
        let connected = contents.contains(Self.hookMarker)
        if connected != isClaudeCodeConnected {
            isClaudeCodeConnected = connected
        }
    }

    private enum ClaudeSettingsError: Error {
        case unexpectedShape
    }

    nonisolated private static func hookGroups(in hooks: [String: Any], for event: String) throws -> [[String: Any]] {
        guard let existing = hooks[event] else {
            return []
        }
        guard let groups = existing as? [[String: Any]] else {
            throw ClaudeSettingsError.unexpectedShape
        }
        return groups
    }

    nonisolated private static func isDockyHookGroup(_ group: [String: Any]) -> Bool {
        guard let entries = group["hooks"] as? [[String: Any]] else {
            return false
        }
        for entry in entries {
            if let command = entry["command"] as? String, command.contains(hookMarker) {
                return true
            }
        }
        return false
    }

    // MARK: - Constants

    nonisolated private static let hookMarker = "Docky/ClaudeActivity"
    nonisolated private static let hookEvents: [String] = [
        "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd",
    ]
    /// Events whose hook groups accept a `matcher`; an empty one matches
    /// every tool or notification type.
    nonisolated private static let eventsTakingMatcher: Set<String> = [
        "PreToolUse", "PostToolUse", "Notification", "SessionEnd",
    ]
    private static let activeSessionTimeout: TimeInterval = 15 * 60
    private static let finishedSessionLifetime: TimeInterval = 12 * 60 * 60

    /// Writes the event Claude Code passes on stdin to a new file in the
    /// spool folder. The write goes through a `.tmp` name and a rename so
    /// Docky never reads half a file, and the command does nothing (beyond
    /// consuming stdin) when the folder is gone, e.g. after Docky is
    /// removed. It prints nothing, so it never adds to Claude's context.
    nonisolated private static let hookCommand: String =
        #"d="$HOME/Library/Application Support/Docky/ClaudeActivity"; if [ -d "$d" ]; then f="$d/$(date +%s)-$$"; cat > "$f.tmp" && mv "$f.tmp" "$f.json"; else cat > /dev/null; fi"#

    private static var spoolDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return base
            .appending(path: "Docky", directoryHint: .isDirectory)
            .appending(path: "ClaudeActivity", directoryHint: .isDirectory)
    }

    private static var claudeSettingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appending(path: ".claude", directoryHint: .isDirectory)
            .appending(path: "settings.json", directoryHint: .notDirectory)
    }

    // MARK: - Text helpers

    /// Turns a tool call into a short present-tense phrase for the tile.
    private static func stepDescription(toolName: String, input: [String: Any]) -> String {
        func text(_ key: String) -> String {
            let value: String = input[key] as? String ?? ""
            return singleLine(value, limit: 80)
        }

        func fileName(_ key: String) -> String {
            let path: String = input[key] as? String ?? ""
            if path.isEmpty {
                return "a file"
            }
            return URL(fileURLWithPath: path).lastPathComponent
        }

        switch toolName {
        case "Bash":
            let command = text("command")
            return command.isEmpty ? "Running a command" : "Running \(command)"
        case "Read":
            return "Reading \(fileName("file_path"))"
        case "Edit", "MultiEdit":
            return "Editing \(fileName("file_path"))"
        case "Write":
            return "Writing \(fileName("file_path"))"
        case "NotebookEdit":
            return "Editing \(fileName("notebook_path"))"
        case "Grep":
            return "Searching for \(text("pattern"))"
        case "Glob":
            return "Finding \(text("pattern"))"
        case "WebSearch":
            return "Searching the web: \(text("query"))"
        case "WebFetch":
            let address: String = input["url"] as? String ?? ""
            let host: String = URL(string: address)?.host ?? "a page"
            return "Reading \(host)"
        case "Task", "Agent":
            let description = text("description")
            return description.isEmpty ? "Delegating to a subagent" : "Delegating: \(description)"
        case "TodoWrite", "TaskCreate", "TaskUpdate":
            return "Updating its task list"
        default:
            // MCP tools are named mcp__<server>__<tool>.
            let parts = toolName.components(separatedBy: "__")
            if parts.count >= 3, parts[0] == "mcp" {
                let server = parts[1]
                let tool = parts.dropFirst(2).joined(separator: " ")
                return "Using \(server): \(tool)"
            }
            return toolName.isEmpty ? "Working" : "Using \(toolName)"
        }
    }

    private static func singleLine(_ text: String, limit: Int) -> String {
        var pieces: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                pieces.append(trimmed)
            }
        }
        let collapsed = pieces.joined(separator: " ")
        guard collapsed.count > limit else {
            return collapsed
        }
        return String(collapsed.prefix(limit - 1)) + "…"
    }

    /// Drops the app name some window titles carry ("Task - Claude") and
    /// titles that are only the app name, which say nothing about the task.
    private static func cleanedWindowTitle(_ title: String) -> String {
        var cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" - ", " — ", " – ", " | "] {
            let suffix = "\(separator)Claude"
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count))
            }
            let prefix = "Claude\(separator)"
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
            }
        }
        return cleaned == "Claude" ? "" : cleaned
    }
}
