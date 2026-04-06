// CHANGE-ID: 20260325_074500_AboutEtudes_HeartIconRestore
// SCOPE: AboutEtudesView — restore heart icon inline in Filter sentence using original formatting. No other UI or copy changes.
// SEARCH-TOKEN: 20260325_074500_AboutEtudes_HeartIconRestore

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

                    Text("Set up default task lists in the Tasks Manager — they’ll appear automatically when you start a session. Import tasks by pasting text or scanning.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

                aboutSection("Session Timer") {
                    Text("The Session Timer is the home of the app. Start a session from here, or access your Journal and Feed.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Log practice, rehearsal, performance, writing, or recording. Attach photos, record audio or video, and trim before saving. Use the + button to add a session manually if you didn’t log it at the time. You control visibility per session. Notes and attachments can remain personal even when a session is shared. Attachments are private by default — tap the eye icon to include them.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Use Threads to group related work — for example, recital prep or a recording project. Threads are personal and visible only to you.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

                aboutSection("Journal & Feed") {
                    Text("Your Journal is a private, time-based archive of all your sessions, organised by week, month, or year.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Your Feed shows shared sessions in chronological order. If you follow other musicians, you’ll see what they’ve chosen to share.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    
                    Text("Tapping a user’s name in a post filters the Feed to their sessions. Tap again to return to the full Feed.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    (
                        Text("Use the Filter to narrow what you see by instrument, activity, saved sessions (")
                        + Text(Image(systemName: "heart"))
                        + Text("), search, and your thread and ensemble filters.")
                    )
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    
                    Text("Ensembles group people you follow — for example, students or band members. Selecting one filters the Feed.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Search helps you quickly find what you’re looking for in your sessions and Feed.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("Comments are private conversations between you and the author.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

                aboutSection("Insights") {
                    Text("Tap the stacked rectangles in the This Week header to view long-term insights and activity trends.")
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

