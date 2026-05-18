// CHANGE-ID: 20260518_132400_AboutEtudes_CopyRefresh
// SCOPE: AboutEtudesView — refresh helper/about copy to reflect current Études philosophy and feature set (Thoughts, Threads, tint system, private-first model, Insights wording, Timer naming). Preserve existing layout/UI structure and inline heart icon formatting.
// SEARCH-TOKEN: 20260518_132400_AboutEtudes_CopyRefresh

import SwiftUI

struct AboutEtudesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                aboutSection("Overview") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Études is a modern practice journal. Capture sessions, ideas, recordings, and reflections — and build a lasting archive of your musical process.")
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.secondaryText)

                        Text("Designed for musicians, composers, teachers, and students, Études focuses on continuity rather than performance metrics.")
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.secondaryText)

                        Text("Études is designed to remain valuable even if nothing is ever shared.")
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.secondaryText)

                        Text("Accounts are private by default. Sharing is intentional. There are no public counts, rankings, or popularity systems.")
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.secondaryText)

                        Text("Most sessions will remain private. That’s expected.")
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }

                aboutSection("Profile") {
                    Text("Add your instruments and activities, and choose a primary instrument for faster session setup.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Set up reusable task lists in the Tasks Manager — they can appear automatically when you begin a session. Import tasks by pasting text or scanning handwritten notes.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Your Journal remains personal and available even when used entirely offline.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

                aboutSection("Timer") {
                    Text("The Timer is where most sessions begin.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Log practice, rehearsal, performance, writing, recording, listening, score study, or rehearsal preparation. Record or attach photos, audio, and video — and trim recordings before saving.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Use the + button to add sessions manually, or create Thoughts — lightweight journal entries for ideas, sketches, reflections, fragments, or unfinished work that doesn’t fit a timed session.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("You control visibility per session. Notes and attachments can remain personal even when a session is shared. Attachments are private by default — tap the eye icon to include them.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Use Threads to preserve continuity across long-term work — for example recital preparation, a recording project, technical studies, a composition, or an ensemble programme. Threads are personal and visible only to you.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

                aboutSection("Journal & Feed") {
                    Text("Your Journal is a private, time-based archive of your work, organised by week, month, or year.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("As patterns emerge in your practice, the Journal can subtly reflect them through colour. Depending on your settings, tint can respond to instruments, activities, or Threads — while remaining calm and neutral when no strong pattern exists.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Thoughts appear alongside sessions, allowing ideas, sketches, reflections, and recordings to live within the same long-term archive.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Your Feed shows shared sessions in chronological order. If you follow other musicians, you’ll only see what they’ve intentionally chosen to share.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Tapping a user’s name in a post filters the Feed to their sessions. Tap again to return to the full Feed.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    (
                        Text("Use Filters to narrow what you see by instrument, activity, Threads, ensembles, saved sessions (")
                        + Text(Image(systemName: "heart"))
                        + Text("), content type, or search.")
                    )
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Saved sessions are personal bookmarks, not public reactions.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Ensembles help organise the people you follow into meaningful musical contexts — for example students, collaborators, chamber groups, or bands.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Comments are private conversations between you and the author — never public threads.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

                aboutSection("Insights") {
                    Text("Insights help reveal patterns in your work over time — including focus, consistency, session rhythm, activities, and Threads — without scores, rankings, or performance pressure.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.top, Theme.Spacing.s)
        }
        .appBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .font(Theme.Text.pageTitle)
                    .foregroundStyle(.primary)
            }
        }
    }

    private func aboutSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
                .sectionHeader()

            aboutCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    content()
                }
            }
        }
    }

    private func aboutCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: Theme.Spacing.m)
    }
}
