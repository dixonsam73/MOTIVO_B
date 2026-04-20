// CHANGE-ID: 20260420_181500_ContentView_JournalArchiveRowContainerExtractionSafetyPass3_c4d9
// SCOPE: Extract JournalArchiveRowContainerModifier plus MonthBarLeadingAccentShape and MonthBarTrailingBodyShape from ContentView with no rendering, spacing, tint, routing, anchor, or behavior changes.
// SEARCH-TOKEN: 20260420_181500_ContentView_JournalArchiveRowContainerExtractionSafetyPass3_c4d9

import SwiftUI

struct JournalArchiveRowContainerModifier: ViewModifier {
    let lens: JournalTimeLens
    let yearWidthFraction: CGFloat
    let barFillColor: Color?
    let barStrokeColor: Color?
    let barAccentColor: Color?
    let barAccentWidth: CGFloat

    init(
        lens: JournalTimeLens,
        yearWidthFraction: CGFloat,
        barFillColor: Color? = nil,
        barStrokeColor: Color? = nil,
        barAccentColor: Color? = nil,
        barAccentWidth: CGFloat = 0
    ) {
        self.lens = lens
        self.yearWidthFraction = yearWidthFraction
        self.barFillColor = barFillColor
        self.barStrokeColor = barStrokeColor
        self.barAccentColor = barAccentColor
        self.barAccentWidth = barAccentWidth
    }

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        switch lens {
        case .week:
            content.cardSurface()
        case .month:
            content.cardSurface()
        case .year:
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 58, alignment: .leading)
                .background(alignment: .leading) {
                    GeometryReader { proxy in
                        let clampedFraction = min(max(yearWidthFraction, 0.05), 0.94)
                        let width = max(0, proxy.size.width * clampedFraction)

                        let cornerRadius: CGFloat = 10
                        let resolvedFill = barFillColor ?? Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.055)
                        let resolvedStroke = barStrokeColor ?? Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.05)
                        let hasAccent = barAccentColor != nil && barAccentWidth > 0
                        let accentWidth = hasAccent ? min(barAccentWidth, width) : 0
                        let bodyWidth = max(0, width - accentWidth)

                        let fullShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        let accentShape = MonthBarLeadingAccentShape(cornerRadius: cornerRadius)
                        let bodyShape = MonthBarTrailingBodyShape(cornerRadius: cornerRadius)

                        ZStack(alignment: .leading) {
                            if hasAccent, let accentColor = barAccentColor {
                                if bodyWidth > 0 {
                                    bodyShape
                                        .fill(resolvedFill)
                                        .frame(width: bodyWidth, height: 58, alignment: .leading)
                                        .offset(x: accentWidth)

                                    bodyShape
                                        .stroke(resolvedStroke, lineWidth: 0.5)
                                        .frame(width: bodyWidth, height: 58, alignment: .leading)
                                        .offset(x: accentWidth)
                                }

                                accentShape
                                    .fill(accentColor)
                                    .frame(width: accentWidth, height: 58, alignment: .leading)

                                accentShape
                                    .stroke(resolvedStroke, lineWidth: 0.5)
                                    .frame(width: accentWidth, height: 58, alignment: .leading)
                            } else {
                                fullShape
                                    .fill(resolvedFill)
                                    .frame(width: width, height: 58, alignment: .leading)

                                fullShape
                                    .stroke(resolvedStroke, lineWidth: 0.5)
                                    .frame(width: width, height: 58, alignment: .leading)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
        }
    }
}

struct MonthBarLeadingAccentShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)

        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
struct MonthBarTrailingBodyShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

