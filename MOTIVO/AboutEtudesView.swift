// CHANGE-ID: 20260318_161600_AboutEtudes_OverviewHeaderTrim
// SCOPE: AboutEtudesView — replace large in-content title with smaller Overview section header and remove final closing sentence card. No other UI, copy, or logic changes.
// SEARCH-TOKEN: 20260318_161600_AboutEtudes_OverviewHeaderTrim

import SwiftUI

struct AboutEtudesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                aboutSection("Overview") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Études is a modern practice journal. Capture sessions, ideas, and recordings — and build a lasting archive of your musical process.")
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.secondaryText)

                        Text("Accounts are private by default. Sharing is intentional. There are no public counts, rankings, or popularity metrics.")
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }

                aboutSection("Profile") {
                    Text("Add your instruments and activities. Choose a primary instrument for faster session setup.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Set up default task lists in the Tasks Manager — they’ll appear automatically when you start a session.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

                aboutSection("Feed") {
                    Text("Your Feed shows your sessions in chronological order. If you follow other musicians, you’ll also see what they’ve chosen to share.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    (
                        Text("Use the Feed Filter to switch between All (you + people you follow), Mine (just you), Saved (sessions you’ve bookmarked using ")
                        + Text(Image(systemName: "heart"))
                        + Text(" — visible only to you), and your thread filters (your own organisational labels).")
                    )
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Search finds sessions by activity, instrument, or notes.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Comments are private conversations between you and the author.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

                aboutSection("Session Timer") {
                    Text("Start a session using the record button in the Feed. Use the + button to add a session manually if you didn’t log it at the time.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Log practice, rehearsal, performance, writing, or recording. Attach photos, record audio or video, and trim before saving. You control visibility per session. Notes and attachments can remain personal even when a session is shared. Attachments are private by default — tap the eye icon to include them.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Use Threads to group related work — for example, recital prep or a recording project. Threads are personal and visible only to you.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

                aboutSection("Insights") {
                    Text("Tap the three bars in the Your Sessions header to view long-term insights and activity trends.")
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
