// CHANGE-ID: 20260420_182400_ContentView_JournalYearMonthRowExtractionSafetyPass2_b61f
// SCOPE: Extract JournalYearMonthRow into a separate file with no rendering, layout, spacing, navigation, data-flow, or behavior changes. Keep parent list composition, anchors, tap routing, and derived-data builders in ContentView.
// SEARCH-TOKEN: 20260420_182400_ContentView_JournalYearMonthRowExtractionSafetyPass2_b61f

import SwiftUI

// MARK: - Row (shows derived title and subtitle)

struct JournalYearMonthRow: View {
    let row: JournalYearMonthRowModel
    let isFirstInYear: Bool

    @Environment(\.colorScheme) private var colorScheme

    private let barCornerRadius: CGFloat = 8
    private let activeBarHeight: CGFloat = 4
    private let quietBarHeight: CGFloat = 1.5
    private let leaderLaneWidth: CGFloat = 5
    private let leaderGapToContent: CGFloat = 4
    private let leaderCornerRadius: CGFloat = 1.5

    private var activeBarFill: Color {
        let baseOpacity: Double = colorScheme == .dark ? 0.105 : 0.03
        let densityLift: Double = colorScheme == .dark ? 0.075 : 0.095
        let adjustedDensity = pow(Double(row.densityFraction), 0.6)
        return Color.primary.opacity(baseOpacity + densityLift * adjustedDensity)
    }

    private var activeBarStroke: Color {
        let baseOpacity: Double = colorScheme == .dark ? 0.065 : 0.012
        let densityLift: Double = colorScheme == .dark ? 0.02 : 0.026
        return Color.primary.opacity(baseOpacity + densityLift * Double(row.densityFraction))
    }

    private var quietTextOpacity: Double {
        row.isFutureMonth ? 0.28 : 0.42
    }

    private var metadataOpacity: Double {
        row.isFutureMonth ? 0.2 : 0.4
    }

    private var quietBarOpacity: Double {
        row.isFutureMonth ? 0.016 : 0.028
    }

    private var showsMetadata: Bool {
        row.hasSessions && row.metadataText != nil
    }

    private var rowTopPadding: CGFloat {
        isFirstInYear ? 2 : 8
    }

    private var rowBottomPadding: CGFloat {
        row.hasSessions ? 12 : 11
    }

    private var leaderColor: Color? {
        Theme.InstrumentTint.visibleAccentColor(
            for: row.dominantInstrumentLabel,
            ownerID: row.ownerUserID,
            scheme: colorScheme,
            shouldAssignIfNeeded: false
        )
    }

    private var barHeight: CGFloat {
        row.hasSessions ? activeBarHeight : quietBarHeight
    }

    var body: some View {
        HStack(alignment: .top, spacing: leaderGapToContent) {
            leaderLane

            VStack(alignment: .leading, spacing: 0) {
                Text(row.monthLabel)
                    .font(.caption.weight(row.hasSessions ? .semibold : .medium))
                    .foregroundStyle(Color.primary.opacity(row.hasSessions ? 0.96 : quietTextOpacity))
                    .lineLimit(1)
                    .padding(.bottom, showsMetadata ? 2 : 7)

                if let metadata = row.metadataText, row.hasSessions {
                    let metadataParts = metadata.components(separatedBy: " • ")
                    let primaryTime = metadataParts.first ?? metadata
                    let secondaryMetadata = metadataParts.dropFirst().joined(separator: " • ")

                    Group {
                        if secondaryMetadata.isEmpty {
                            Text(primaryTime)
                                .font(.caption2.weight(.semibold))
                        } else {
                            Text(primaryTime)
                                .font(.caption2.weight(.semibold))
                            + Text(" • \(secondaryMetadata)")
                                .font(.caption2)
                        }
                    }
                        .foregroundStyle(Color.primary.opacity(metadataOpacity))
                        .lineLimit(1)
                        .padding(.bottom, 9)
                }

                GeometryReader { proxy in
                    let totalWidth = max(0, proxy.size.width)
                    let clampedFraction = min(max(row.widthFraction, 0.08), 1.0)
                    let fillWidth = row.hasSessions ? max(0, totalWidth * clampedFraction) : 0

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(quietBarOpacity))
                            .frame(width: totalWidth, height: quietBarHeight)

                        if row.hasSessions {
                            RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                                .fill(activeBarFill)
                                .frame(width: fillWidth, height: activeBarHeight)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                                        .stroke(activeBarStroke, lineWidth: 0.45)
                                        .frame(width: fillWidth, height: activeBarHeight)
                                }
                        }
                    }
                }
                .frame(height: barHeight)
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) {
                if let leaderColor {
                    RoundedRectangle(cornerRadius: leaderCornerRadius, style: .continuous)
                        .fill(leaderColor)
                        .frame(width: leaderLaneWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .offset(x: -(leaderLaneWidth + leaderGapToContent))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, rowTopPadding)
        .padding(.bottom, rowBottomPadding)
    }

    @ViewBuilder
    private var leaderLane: some View {
        Color.clear
            .frame(width: leaderLaneWidth)
    }
}


