//
//  SystemStatusWidgetTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct SystemStatusWidgetTileView: View {
    let tile: WidgetTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool
    var isExpanded: Bool = false
    var isExpandedPreviewOpen: Bool = false

    @ObservedObject private var systemStatus = SystemStatusService.shared

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        GeometryReader { proxy in
            let metrics = visibleMetrics
            let layout = layout(in: proxy.size, visibleMetricCount: max(1, metrics.count))

            ZStack {
                // Clear: the tile sits on glass, applied below.
                Color.clear

                if !isWithinStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }

                content(metrics: metrics, layout: layout, size: proxy.size)
            }
            .dockyWidgetGlass(cornerRadius: cornerRadius)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task {
            systemStatus.ensureFreshStatus()
        }
    }

    @ViewBuilder
    private func content(metrics: [SystemStatusMetricSnapshot], layout: LayoutMetrics, size: CGSize) -> some View {
        if isExpanded, let snapshot = systemStatus.snapshot {
            expandedPanel(snapshot: snapshot, size: size)
        } else if layout.isCompact, let snapshot = systemStatus.snapshot {
            compactStrip(snapshot: snapshot, layout: layout)
        } else if !metrics.isEmpty {
            indicatorStrip(metrics: metrics, layout: layout)
        } else {
            emptyState(layout: layout)
        }
    }

    private func indicatorStrip(metrics: [SystemStatusMetricSnapshot], layout: LayoutMetrics) -> some View {
        HStack(alignment: .center, spacing: layout.contentGap) {
            ForEach(metrics) { metric in
                metricIndicator(metric: metric, layout: layout)
            }
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// Short-dock layout. A ring with a caption under it leaves the number
    /// only a few points tall when the tile is ~40pt high, so each usage
    /// metric becomes three stacked lines instead (name, value, thin bar),
    /// followed by a two-line column for download and upload.
    private func compactStrip(snapshot: SystemStatusSnapshot, layout: LayoutMetrics) -> some View {
        HStack(alignment: .center, spacing: layout.compactColumnGap) {
            ForEach(compactUsageMetrics(in: snapshot)) { metric in
                compactMetric(metric: metric, layout: layout)
            }

            if renderedSpan != .one {
                compactNetwork(snapshot: snapshot, layout: layout)
            }
        }
        .padding(.horizontal, layout.compactHorizontalPadding)
        .padding(.vertical, layout.compactVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// Which usage columns fit: the disk alone up to two tiles (next to
    /// the network column at two), then disk, CPU and memory.
    private func compactUsageMetrics(in snapshot: SystemStatusSnapshot) -> [SystemStatusMetricSnapshot] {
        let usage = snapshot.metrics.filter { $0.kind != .network }
        switch renderedSpan {
        case .one, .two:
            return Array(usage.prefix(1))
        case .three, .four:
            return usage
        }
    }

    private func compactNetwork(snapshot: SystemStatusSnapshot, layout: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            compactRateLine(symbol: "arrow.down", text: snapshot.compactReceivedRateText, tint: .systemBlue, layout: layout)
            compactRateLine(symbol: "arrow.up", text: snapshot.compactSentRateText, tint: .systemOrange, layout: layout)
        }
        // Fixed width, sized for "999K": rates change every two seconds and
        // a flexible column would make its neighbours shuffle sideways.
        .frame(width: layout.compactRateFontSize * 3.6, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Download \(rateText(snapshot.receivedBytesPerSecond)), upload \(rateText(snapshot.sentBytesPerSecond))")
    }

    private func compactRateLine(symbol: String, text: String, tint: NSColor, layout: LayoutMetrics) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: layout.compactRateFontSize * 0.78, weight: .heavy))
                .foregroundStyle(Color(nsColor: tint))

            Text(text)
                .font(.system(size: layout.compactRateFontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// Hover panel: every figure spelled out, one row per resource.
    private func expandedPanel(snapshot: SystemStatusSnapshot, size: CGSize) -> some View {
        let base = min(max(min(size.width, size.height) * 0.058, 11), 15)
        let usage = snapshot.metrics.filter { $0.kind != .network } + (snapshot.gpuMetric.map { [$0] } ?? [])

        return VStack(alignment: .leading, spacing: base * 0.85) {
            ForEach(usage) { metric in
                expandedRow(metric: metric, detail: expandedDetail(for: metric, in: snapshot), base: base)
            }

            HStack(spacing: base * 0.5) {
                Text("Network")
                    .font(.system(size: base, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                // Full rates where they fit, the short form ("13M") in a
                // narrow panel such as the sidebar's.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: base * 0.5) {
                        expandedRate(symbol: "arrow.down", text: rateText(snapshot.receivedBytesPerSecond), tint: .systemBlue, base: base)
                        expandedRate(symbol: "arrow.up", text: rateText(snapshot.sentBytesPerSecond), tint: .systemOrange, base: base)
                    }

                    HStack(spacing: base * 0.5) {
                        expandedRate(symbol: "arrow.down", text: snapshot.compactReceivedRateText, tint: .systemBlue, base: base)
                        expandedRate(symbol: "arrow.up", text: snapshot.compactSentRateText, tint: .systemOrange, base: base)
                    }
                }
            }
        }
        .padding(base * 1.3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func expandedRow(metric: SystemStatusMetricSnapshot, detail: String?, base: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: base * 0.3) {
            HStack(spacing: base * 0.45) {
                Image(systemName: metric.kind.symbolName)
                    .font(.system(size: base * 0.95, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(expandedTitle(for: metric.kind))
                    .font(.system(size: base, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Text(metric.primaryText)
                    .font(.system(size: base * 1.15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.quaternary)

                    Capsule(style: .continuous)
                        .fill(Color(nsColor: accentColor(for: metric)))
                        .frame(width: max(base * 0.4, proxy.size.width * CGFloat(metric.progress)))
                }
            }
            .frame(height: base * 0.4)

            if let detail {
                Text(detail)
                    .font(.system(size: base * 0.82, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func expandedRate(symbol: String, text: String, tint: NSColor, base: CGFloat) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: base * 0.8, weight: .heavy))
                .foregroundStyle(Color(nsColor: tint))

            Text(text)
                .font(.system(size: base * 0.95, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private func expandedTitle(for kind: SystemStatusMetricKind) -> String {
        switch kind {
        case .disk: "SSD"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        case .network: "Network"
        }
    }

    private func expandedDetail(for metric: SystemStatusMetricSnapshot, in snapshot: SystemStatusSnapshot) -> String? {
        switch metric.kind {
        case .disk:
            return "\(byteText(snapshot.diskFreeBytes, style: .file)) free of \(byteText(snapshot.diskTotalBytes, style: .file))"
        case .memory:
            return "\(byteText(snapshot.usedMemoryBytes, style: .memory)) of \(byteText(snapshot.totalMemoryBytes, style: .memory))"
        case .cpu, .gpu, .network:
            return nil
        }
    }

    private func byteText(_ bytes: UInt64, style: ByteCountFormatter.CountStyle) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: style)
    }

    private func rateText(_ bytesPerSecond: Double) -> String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(max(0, bytesPerSecond)), countStyle: .file))/s"
    }

    private func compactMetric(metric: SystemStatusMetricSnapshot, layout: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(metric.secondaryText)
                .font(.system(size: layout.compactLabelFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(metric.primaryText)
                .font(.system(size: layout.compactValueFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.quaternary)

                    Capsule(style: .continuous)
                        .fill(Color(nsColor: accentColor(for: metric)))
                        .frame(width: max(layout.compactBarHeight, proxy.size.width * CGFloat(metric.progress)))
                }
            }
            .frame(height: layout.compactBarHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.secondaryText) \(metric.primaryText)")
    }

    private func metricIndicator(metric: SystemStatusMetricSnapshot, layout: LayoutMetrics) -> some View {
        VStack(spacing: layout.stackSpacing) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: layout.ringWidth)

                Circle()
                    .trim(from: 0, to: metric.progress)
                    .stroke(
                        Color(nsColor: accentColor(for: metric)),
                        style: StrokeStyle(lineWidth: layout.ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .padding(layout.ringWidth + 1)

                Image(systemName: metric.kind.symbolName)
                    .font(.system(size: layout.iconSize, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: layout.circleDiameter, height: layout.circleDiameter)

            VStack(spacing: 0) { 
                Text(metric.primaryText)
                    .font(.system(size: layout.valueFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(y: 2)
    }

    private func emptyState(layout: LayoutMetrics) -> some View {
        VStack(spacing: layout.stackSpacing) {
            if systemStatus.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.primary.opacity(0.92))
            } else {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: layout.iconSize, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Text(systemStatus.isLoading ? "Loading Status" : "No Status Data")
                .font(.system(size: layout.titleFontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if !systemStatus.isLoading, renderedSpan != .one {
                Text("System metrics are temporarily unavailable.")
                    .font(.system(size: layout.detailFontSize))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var visibleMetrics: [SystemStatusMetricSnapshot] {
        guard let snapshot = systemStatus.snapshot else {
            return []
        }

        let limit = switch renderedSpan {
        case .one:
            1
        case .two:
            2
        case .three, .four:
            3
        }

        return Array(snapshot.metrics.prefix(limit))
    }

    private func layout(in size: CGSize, visibleMetricCount: Int) -> LayoutMetrics {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let minSide = min(width, height)
        let contentPadding = min(minSide * 0.12, minSide * 0.18)
        let stackSpacing = min(minSide * 0.05, minSide * 0.1)
        let contentGap = min(minSide * 0.08, minSide * 0.14)
        let availableWidth = max(0, width - contentPadding * 2)
        let availableHeight = max(0, height - contentPadding * 2)
        let widthBasedCircle = (availableWidth - CGFloat(max(0, visibleMetricCount - 1)) * contentGap) / CGFloat(max(1, visibleMetricCount))
        let maxCircleByHeight = availableHeight * (renderedSpan == .one ? 0.6 : 0.52)
        let circleDiameter = max(0, min(widthBasedCircle, maxCircleByHeight))

        // Compact (short dock) metrics: three text lines sized off the
        // height left after a small padding.
        let compactVerticalPadding = max(3, height * 0.09)
        let compactUsableHeight = max(0, height - compactVerticalPadding * 2)

        return LayoutMetrics(
            isCompact: height < 60,
            compactVerticalPadding: compactVerticalPadding,
            compactHorizontalPadding: max(7, minSide * 0.2),
            compactColumnGap: max(4, minSide * 0.12),
            compactLabelFontSize: min(compactUsableHeight * 0.26, 11),
            compactValueFontSize: min(compactUsableHeight * 0.39, 17),
            compactRateFontSize: min(compactUsableHeight * 0.34, 14),
            compactBarHeight: min(max(2.5, compactUsableHeight * 0.09), 5),
            contentPadding: contentPadding,
            contentGap: contentGap,
            stackSpacing: stackSpacing,
            captionFontSize: min(circleDiameter * 0.18, 11),
            titleFontSize: min(minSide * 0.17, renderedSpan == .one ? 14 : 16),
            detailFontSize: min(minSide * 0.12, 13),
            valueFontSize: min(circleDiameter * 0.24, renderedSpan == .three ? 12 : 14),
            circleDiameter: circleDiameter,
            ringWidth: min(circleDiameter * 0.1, 7),
            iconSize: min(circleDiameter * 0.28, renderedSpan == .three ? 16 : 20)
        )
    }

    private var backgroundTintColor: NSColor {
        .windowBackgroundColor
    }

    private func accentColor(for metric: SystemStatusMetricSnapshot) -> NSColor {
        switch metric.kind {
        case .disk:
            if metric.progress >= 0.9 {
                return .systemRed
            }

            if metric.progress >= 0.75 {
                return .systemOrange
            }

            return .systemBlue
        case .cpu:
            if metric.progress >= 0.85 {
                return .systemRed
            }

            if metric.progress >= 0.65 {
                return .systemOrange
            }

            return .systemYellow
        case .memory:
            if metric.progress >= 0.85 {
                return .systemRed
            }

            if metric.progress >= 0.7 {
                return .systemOrange
            }

            return .systemPurple
        case .gpu:
            if metric.progress >= 0.85 {
                return .systemRed
            }

            if metric.progress >= 0.65 {
                return .systemOrange
            }

            return .systemGreen
        case .network:
            if metric.progress >= 0.75 {
                return .systemBlue
            }

            if metric.progress > 0.15 {
                return .systemTeal
            }

            return .systemGreen
        }
    }
}

private struct LayoutMetrics {
    let isCompact: Bool
    let compactVerticalPadding: CGFloat
    let compactHorizontalPadding: CGFloat
    let compactColumnGap: CGFloat
    let compactLabelFontSize: CGFloat
    let compactValueFontSize: CGFloat
    let compactRateFontSize: CGFloat
    let compactBarHeight: CGFloat
    let contentPadding: CGFloat
    let contentGap: CGFloat
    let stackSpacing: CGFloat
    let captionFontSize: CGFloat
    let titleFontSize: CGFloat
    let detailFontSize: CGFloat
    let valueFontSize: CGFloat
    let circleDiameter: CGFloat
    let ringWidth: CGFloat
    let iconSize: CGFloat
}
