//
//  SessionDetailView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData
import PhotosUI
import UniformTypeIdentifiers

struct SessionDetailView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let session: Session

    // Pickers & preview
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var photoSelection: PhotosPickerItem?

    // Wrap URL so it conforms to Identifiable for .sheet(item:)
    struct QuickLookItem: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }
    @State private var quickLookItem: QuickLookItem?

    var body: some View {
        List {
            // Summary
            Section(header: Text("Summary")) {
                HStack { Text("When");      Spacer(); Text(dateTime(session.timestamp)).foregroundStyle(.secondary) }
                HStack { Text("Duration");  Spacer(); Text(formatDuration(Int(session.durationSeconds))).foregroundStyle(.secondary) }
                HStack { Text("Instrument");Spacer(); Text(session.instrument?.isEmpty == false ? session.instrument! : "—").foregroundStyle(.secondary) }
                HStack { Text("Privacy");   Spacer(); Text(session.isPublic ? "Public" : "Private").foregroundStyle(.secondary) }
            }

            // Feel
            Section(header: Text("Feel")) {
                MeterRow(label: "Mood", value: Int(session.mood))
                MeterRow(label: "Effort", value: Int(session.effort))
            }

            // Tags
            if let tags = (session.tags as? Set<Tag>)?.compactMap({ $0.name }).sorted(), !tags.isEmpty {
                Section(header: Text("Tags")) {
                    Text(tags.joined(separator: ", ")).foregroundStyle(.secondary)
                }
            }

            // Notes
            if let notes = session.notes, !notes.isEmpty {
                Section(header: Text("Notes")) { Text(notes) }
            }

            // Attachments (tap to preview)
            AttachmentsSectionView(attachments: attachmentsArray) { attachment in
                if let path = attachment.fileURL {
                    let url = AttachmentStore.url(for: path)
                    quickLookItem = QuickLookItem(url: url)
                }
            }
        }
        .navigationTitle(session.title?.isEmpty == false ? session.title! : "Practice Session")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Add Attachment menu
                Menu {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Files", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "paperclip.circle")
                }

                // Edit / Delete
                NavigationLink("Edit") { AddEditSessionView(session: session) }
                Button(role: .destructive) { deleteSession() } label: { Image(systemName: "trash") }
            }
        }
        // Photo library picker (images only for now)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoSelection, matching: .images)
        .onChange(of: photoSelection) { _, newItem in
            Task { await handlePhotoSelection(newItem) }
        }
        // Files importer
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image, .audio, .movie, .pdf, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { handleFileImport(url: url) }
            case .failure:
                break
            }
        }
        // Quick Look preview via Identifiable wrapper + explicit Done button
        .sheet(item: $quickLookItem) { item in
            NavigationView {
                QuickLookPreview(url: item.url)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { quickLookItem = nil }
                        }
                    }
            }
        }
    }

    // MARK: - Derived
    private var attachmentsArray: [Attachment] {
        ((session.attachments as? Set<Attachment>) ?? []).sorted {
            ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
    }

    // MARK: - Pickers handling
    private func handleFileImport(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
            let savedPath = try AttachmentStore.saveData(data, suggestedName: url.deletingPathExtension().lastPathComponent, ext: ext)
            try AttachmentStore.addAttachment(kind: kindForExtension(ext), filePath: savedPath, to: session, ctx: ctx)
        } catch {
            // Minimal handling per your guardrails
        }
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let savedPath = try AttachmentStore.saveData(data, suggestedName: "image_\(Int(Date().timeIntervalSince1970))", ext: "png")
                try AttachmentStore.addAttachment(kind: .image, filePath: savedPath, to: session, ctx: ctx)
            }
        } catch {
            // Minimal handling
        }
    }

    private func kindForExtension(_ ext: String) -> AttachmentKind {
        let e = ext.lowercased()
        if ["png","jpg","jpeg","heic","gif","tiff","bmp","webp"].contains(e) { return .image }
        if ["m4a","aac","mp3","wav","aiff","caf","flac","ogg"].contains(e) { return .audio }
        if ["mov","mp4","m4v","avi","mkv","hevc"].contains(e) { return .video }
        return .file
    }

    // MARK: - Actions
    private func deleteSession() {
        ctx.delete(session)
        try? ctx.save()
        dismiss()
    }
}

// MARK: - Subviews
private struct MeterRow: View {
    let label: String
    let value: Int
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Text(label); Spacer(); Text("\(value)").foregroundStyle(.secondary) }
            ProgressView(value: Double(value), total: 10)
        }
    }
}

// MARK: - Helpers
private func formatDuration(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    if s == 0 { return "\(m)m" }
    return String(format: "%dm %02ds", m, s)
}

private func dateTime(_ date: Date?) -> String {
    guard let date else { return "—" }
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    return df.string(from: date)
}
