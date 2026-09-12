import SwiftUI

struct AboutEtudesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                introduction

                PracticeWindowSeparator(animationDelay: 0.3)
                    .padding(.vertical, Theme.Spacing.xxl)

                captureSection
                tasksSection.padding(.top, Theme.Spacing.xxl)
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

    private var tasksSection: some View {
        aboutSection("Shape your practice") {
            Text("Create reusable task lists for the things you want to work on. Bring them into a session, tick off tasks as you go, and return to them next time. You can also import a list by pasting text or scanning handwritten notes.")
                .aboutBody()

            AboutScreenshot(
                "AboutTasks",
                crop: CGRect(x: 32, y: 1310, width: 878, height: 552),
                description: "Example task list, with warm-up and scale patterns completed and work on Bach’s Cello Suite II still to do."
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
                crop: CGRect(x: 55, y: 460, width: 832, height: 520),
                description: "The opening of Bach’s Cello Suite II, Prélude, in the score viewer."
            )
        }
    }

    private var journalSection: some View {
        aboutSection("Return to what matters") {
            Text("Your Journal brings Sessions and Thoughts together over time. Use Threads to connect work on a piece, project or longer-term goal.")
                .aboutBody()

            AboutScreenshot(
                "AboutSession",
                crop: CGRect(x: 0, y: 246, width: 942, height: 1750),
                description: "A saved Afternoon Practice session: Bass Guitar, two hours and five minutes, with notes, focus, a photo and page 8 of the Bach score attached."
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
                crop: CGRect(x: 36, y: 1010, width: 870, height: 625),
                description: "Example Insights showing varied session lengths and a current streak of one day."
            )
        }
    }

    private var connectedSection: some View {
        aboutSection("Explore Connected") {
            Text("Your Journal, Tasks and score library work offline without a Connected account.")
                .aboutBody()

            Text("Études Connected adds sharing with other musicians. In Connected, sessions share with your followers by default; you can change this in Profile.")
                .aboutBody()

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
/// Crop coordinates use the same 942 × 2048 reference canvas for every asset.
private struct AboutScreenshot: View {
    let asset: String
    let crop: CGRect
    let description: String

    @Environment(\.colorScheme) private var colorScheme

    init(_ asset: String, crop: CGRect, description: String) {
        self.asset = asset
        self.crop = crop
        self.description = description
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / crop.width
            Image(asset)
                .resizable()
                .interpolation(.high)
                .frame(width: 942 * scale, height: 2048 * scale)
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
