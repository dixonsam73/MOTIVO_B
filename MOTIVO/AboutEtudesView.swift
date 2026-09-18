import SwiftUI

struct AboutEtudesView<ConnectedDestination: View>: View {
    @ViewBuilder let connectedDestination: () -> ConnectedDestination

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                introduction

                PracticeWindowSeparator(animationDelay: 0.3)
                    .padding(.vertical, Theme.Spacing.xxl)

                captureSection
                listsSection.padding(.top, Theme.Spacing.xxl)
                scoresSection.padding(.top, Theme.Spacing.xxl)

                PracticeWindowSeparator(animationDelay: 0.5)
                    .padding(.vertical, Theme.Spacing.xxl)

                journalSection
                insightsSection.padding(.top, Theme.Spacing.xxl)

                PracticeWindowSeparator(animationDelay: 0.3)
                    .padding(.vertical, Theme.Spacing.xxl)

                connectedSection
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.xxl)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
        .tint(Theme.Colors.accent)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("About Études")
                    .font(Theme.Text.pageTitle)
                    .foregroundStyle(.primary)
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("A journal for musicians.")
                .font(.title2.weight(.medium))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Text("Keep a record of your practice, rehearsals, performances and ideas, and build an archive of your musical life.")
                .aboutBody()
        }
    }

    private var captureSection: some View {
        aboutSection("Capture sessions and ideas") {
            Text("Start the Timer when you begin, or add a session manually afterwards. Keep notes, record audio and video, and take photos alongside your work.")
                .aboutBody()

            Text("For something that doesn’t need a timed session, add a Thought: an idea, reflection, sketch or fragment, with text and any existing files you’d like to attach.")
                .aboutBody()

            Text("Choose your instruments and activities in Profile to make session setup your own.")
                .aboutBody()
        }
    }

    private var listsSection: some View {
        aboutSection("Shape your practice with Lists") {
            Text("Create reusable Lists for practice, lesson assignments or setlists. Bring a List into a session, tick off items as you go, and return to it next time. Import a List by pasting text or scanning handwritten notes.")
                .aboutBody()

            AboutScreenshot(
                "AboutLists",
                sourceSize: CGSize(width: 1206, height: 1777),
                crop: CGRect(x: 40, y: 760, width: 1130, height: 780),
                description: "A practice List grouped under Warm Up and Bach cello suites. Hanon major scale patterns are checked off, with two items still to do. Add line, Save list and Import list controls appear below."
            )

            Text("The built-in tuner, metronome and drone are there when you need them.")
                .aboutBody()
        }
    }

    private var scoresSection: some View {
        aboutSection("Keep scores close") {
            Text("Build your personal score library, open a score while practising, and pick up where you left off. Keep the scores you use alongside the sessions they belong to.")
                .aboutBody()

            AboutScreenshot(
                "AboutScore",
                sourceSize: CGSize(width: 1206, height: 2622),
                crop: CGRect(x: 24, y: 190, width: 1158, height: 1050),
                description: "The opening of Bach’s Cello Suite II, Prélude, with recording, sharing and score library controls above the music."
            )
        }
    }

    private var journalSection: some View {
        aboutSection("Return to what matters") {
            Text("Your Journal brings Sessions and Thoughts together over time. Use Threads to connect work on a piece, project or longer-term goal.")
                .aboutBody()

            AboutScreenshot(
                "AboutSession",
                sourceSize: CGSize(width: 1206, height: 2622),
                crop: CGRect(x: 38, y: 1148, width: 1130, height: 990),
                description: "A Journal card for Afternoon Practice on bass guitar, grouped under 7–13 September 2026, with a Bach Thread, a short note, a photo, a Favourite control and two attachments."
            )

            Text("Filter by instrument, activity or Thread, search your entries and recording titles, and bookmark useful Sessions and Thoughts with Favourites. Threads and Favourites are personal.")
                .aboutBody()
        }
    }

    private var insightsSection: some View {
        aboutSection("Notice your patterns") {
            Text("Insights help you notice patterns in your time, activities and focus, without rankings or performance pressure.")
                .aboutBody()

            AboutScreenshot(
                "AboutInsights",
                sourceSize: CGSize(width: 1206, height: 2622),
                crop: CGRect(x: 38, y: 1160, width: 1130, height: 1240),
                description: "Three Insights cards: Practice rhythm varies week to week, Practice window is spread throughout the day, and Session shape shows a wide range of session lengths."
            )
        }
    }

    private var connectedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Your Journal, Lists and score library work offline, without an account.")
                .aboutBody()

            Text("Études Connected lets you share your musical work, ideas and progress with fellow musicians, teachers and students. Exchange recordings, discuss what you’re working on, and prepare for your next lesson or rehearsal.")
                .aboutBody()

            Text("In Connected, sessions are shared with your followers by default. You can change this in Profile or choose what to share for each session.")
                .aboutBody()

            NavigationLink(destination: connectedDestination) {
                HStack(spacing: Theme.Spacing.s) {
                    Text("Explore Connected")
                    Image(systemName: "arrow.right")
                        .accessibilityHidden(true)
                }
                .font(Theme.Text.body.weight(.semibold))
                .foregroundStyle(Theme.Colors.primaryAction.opacity(0.92))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.Colors.primaryAction.opacity(0.18))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func aboutSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text(title)
                .font(Theme.Text.pageTitle)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

/// Presents a detail from a screenshot without altering its source pixels.
/// Crop coordinates and source size are expressed in the original image’s pixels.
private struct AboutScreenshot: View {
    let asset: String
    let sourceSize: CGSize
    let crop: CGRect
    let description: String

    @Environment(\.colorScheme) private var colorScheme

    init(_ asset: String, sourceSize: CGSize, crop: CGRect, description: String) {
        self.asset = asset
        self.sourceSize = sourceSize
        self.crop = crop
        self.description = description
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / crop.width
            Image(asset)
                .resizable()
                .interpolation(.high)
                .frame(width: sourceSize.width * scale, height: sourceSize.height * scale)
                .offset(x: -crop.minX * scale, y: -crop.minY * scale)
        }
        .aspectRatio(crop.width / crop.height, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(Theme.Colors.stroke(colorScheme), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
        .accessibilityAddTraits(.isImage)
    }
}

private extension View {
    func aboutBody() -> some View {
        font(Theme.Text.body)
            .foregroundStyle(Theme.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
