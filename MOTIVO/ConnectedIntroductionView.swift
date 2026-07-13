// CHANGE-ID: 20260713_ConnectedIntroduction_M8A1_GlyphAnimation
// SCOPE: Add a one-shot, Reduce Motion-aware reveal to the two existing Practice Window separators in ConnectedIntroductionView only. No copy, layout, navigation, authentication, StoreKit, or unrelated UI changes.
// SEARCH-TOKEN: 20260713_ConnectedIntroduction_M8A1_GlyphAnimation

import SwiftUI

struct ConnectedIntroductionView: View {
    let onSignIn: () -> Void
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroImage

                returningUserSection
                    .padding(.top, Theme.Spacing.xxl)

                introductionSection
                    .padding(.top, Theme.Spacing.xxl)

                PracticeWindowSeparator(animationDelay: 0.3)
                    .padding(.vertical, Theme.Spacing.xxl)

                sharingSection

                PracticeWindowSeparator(animationDelay: 0.5)
                    .padding(.vertical, Theme.Spacing.xxl)

                principlesSection

                closingSection
                    .padding(.top, Theme.Spacing.xxl)

                continueSection
                    .padding(.top, Theme.Spacing.xxl)
                    .padding(.bottom, Theme.Spacing.xxl)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Études Connected")
                    .font(Theme.Text.pageTitle)
                    .foregroundStyle(.primary)
            }
        }
    }

    private var heroImage: some View {
        GeometryReader { proxy in
            Image("ConnectedHero")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: 300)
                .clipped()
                .accessibilityHidden(true)
        }
        .frame(height: 300)
    }

    private var returningUserSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Sign in to Connected")
                .font(Theme.Text.pageTitle)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Already have a Connected account?")
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.Colors.secondaryText)

                Button("Sign In", action: onSignIn)
                    .font(Theme.Text.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .stroke(Theme.Colors.stroke(colorScheme).opacity(0.72), lineWidth: 1)
                    }
                    .buttonStyle(.plain)
            }
        }
        .editorialMargins()
    }

    private var introductionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("Études Connected opens up your Études journal to the people you already make music with.")
                .connectedBody()

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Teachers.")
                Text("Students.")
                Text("Bandmates.")
                Text("Ensemble members.")
                Text("Collaborators.")
            }
            .font(Theme.Text.body)
            .foregroundStyle(.primary)

            Text("Connected gives you a place to share ideas, find inspiration, and stay connected with the people you make music with.")
                .connectedBody()

            Text("You decide what to share, and what remains private.")
                .connectedBody()
        }
        .editorialMargins()
    }

    private var sharingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("Share when you've worked something out on your instrument that might help someone else, you'd like to send charts for tomorrow's rehearsal to your bandmates, or you've found inspiration in something another musician has posted.")
                .connectedBody()

            Text("Find other musicians by name or instrument, organise them into Ensembles, and save useful posts for future reference.")
                .connectedBody()
        }
        .editorialMargins()
    }

    private var principlesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("No likes.")
                Text("No public follower counts.")
                Text("No engagement algorithms.")
                Text("No pressure to post.")
            }
            .font(Theme.Text.body)
            .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                Text("Start with the people already part of your musical life.")
                    .connectedBody()

                Text("If someone isn't using Études Connected yet, you can invite them.")
                    .connectedBody()
            }
        }
        .editorialMargins()
    }

    private var closingSection: some View {
        Text("Continue to get started with Études Connected.")
            .connectedBody()
            .editorialMargins()
    }

    private var continueSection: some View {
        Button("Continue", action: onContinue)
            .font(Theme.Text.body.weight(.semibold))
            .foregroundStyle(
                Theme.Colors.primaryAction.opacity(0.92)
            )
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(
                    cornerRadius: Theme.Radius.control,
                    style: .continuous
                )
                .fill(
                    Theme.Colors.primaryAction.opacity(0.18)
                )
            )
            .buttonStyle(.plain)
            .editorialMargins()
    }
}

private struct PracticeWindowSeparator: View {
    let animationDelay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lineRevealProgress: CGFloat = 0
    @State private var dotRevealProgress: CGFloat = 0
    @State private var hasAnimated = false

    private let glyphColor = Color(red: 0.28, green: 0.56, blue: 0.56)

    var body: some View {
        PracticeWindowSeparatorCanvas(
            lineProgress: lineRevealProgress,
            dotProgress: dotRevealProgress,
            glyphColor: glyphColor
        )
        .frame(width: 92, height: 30)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .onAppear {
            revealIfNeeded()
        }
    }

    private func revealIfNeeded() {
        guard !hasAnimated else { return }
        hasAnimated = true

        guard !reduceMotion else {
            lineRevealProgress = 1
            dotRevealProgress = 1
            return
        }

        let lineDuration: Double = 5.0

        withAnimation(.easeOut(duration: lineDuration).delay(animationDelay)) {
            lineRevealProgress = 1
        }

        withAnimation(.easeIn(duration: 1.6).delay(animationDelay + lineDuration)) {
            dotRevealProgress = 1
        }
    }
}

private struct PracticeWindowSeparatorCanvas: View, Animatable {
    var lineProgress: CGFloat
    var dotProgress: CGFloat
    let glyphColor: Color

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(lineProgress, dotProgress) }
        set {
            lineProgress = newValue.first
            dotProgress = newValue.second
        }
    }

    var body: some View {
        Canvas { context, size in
            let insetX: CGFloat = 8
            let availableWidth = max(size.width - (insetX * 2), 1)
            let centerY = (size.height / 2) - 1.5
            let opticalExtension: CGFloat = 2.5
            let startX = insetX - opticalExtension
            let endX = insetX + availableWidth + opticalExtension
            let fullLineWidth = max(endX - startX, 1)
            let lineCenterX = startX + (fullLineWidth / 2)
            let clampedLineProgress = min(max(lineProgress, 0), 1)
            let clampedDotProgress = min(max(dotProgress, 0), 1)
            let halfLineWidth = (fullLineWidth / 2) * clampedLineProgress

            var line = Path()
            line.move(to: CGPoint(x: lineCenterX - halfLineWidth, y: centerY))
            line.addLine(to: CGPoint(x: lineCenterX + halfLineWidth, y: centerY))
            context.stroke(
                line,
                with: .color(glyphColor.opacity(0.31)),
                style: StrokeStyle(lineWidth: 1.35, lineCap: .round)
            )

            for position in [CGFloat(0.20), CGFloat(0.50), CGFloat(0.80)] {
                let dotX = insetX + (availableWidth * position)
                let radius: CGFloat = 7.6
                let rect = CGRect(
                    x: dotX - radius,
                    y: centerY - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                let dotPath = Path(ellipseIn: rect)

                context.fill(
                    dotPath,
                    with: .color(glyphColor.opacity(0.32 * Double(clampedDotProgress)))
                )
                context.stroke(
                    dotPath,
                    with: .color(glyphColor.opacity(0.46 * Double(clampedDotProgress))),
                    lineWidth: 1.25
                )
            }
        }
    }
}

private extension View {
    func editorialMargins() -> some View {
        padding(.horizontal, Theme.Spacing.l)
    }

    func connectedBody() -> some View {
        font(Theme.Text.body)
            .foregroundStyle(Theme.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
