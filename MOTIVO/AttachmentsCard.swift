// CHANGE-ID: 20260105_235800_attachmentscard_star_toggle_no_fallback
// SCOPE: Toggle star bidirectionally and clear selection on delete; remove auto-fallback to first image. No layout changes.
// AttachmentsCard.swift
// Extracted from PracticeTimerView as part of refactor step 3 (fixed).
// Renders staged images, audio, and videos for the session.
// All state/behaviour stays in PracticeTimerView and is passed via bindings/closures.

import SwiftUI
import AVFoundation
import AVKit

struct AttachmentsCard: View {
    @Binding var stagedImages: [StagedAttachment]
    @Binding var stagedAudio: [StagedAttachment]
    @Binding var stagedVideos: [StagedAttachment]
    
    @Binding var selectedThumbnailID: UUID?
    @Binding var trimItem: StagedAttachment?
    @Binding var audioTitleEditingBuffer: [UUID: String]
    @Binding var audioTitleDidImmediatePersist: Set<UUID>
    @Binding var audioTitles: [UUID: String]
    
    let audioAutoTitles: [UUID: String]
    let audioDurations: [UUID: Int]
    @Binding var videoThumbnails: [UUID: UIImage]
    
    let stagedSizeWarning: String?
    let currentlyPlayingID: UUID?
    let isAudioPlaying: Bool
    let recorderIcon: Color
    
    let focusedAudioTitleID: FocusState<UUID?>.Binding
    
    let formattedClipDuration: (Int) -> String
    let surrogateURL: (StagedAttachment) -> URL?
    
    let onPersistStagedAttachments: () -> Void
    let onTogglePlay: (UUID) -> Void
    let onDeleteAudio: (UUID) -> Void
    let onPersistAudioTitleImmediately: (UUID, String) -> Void
    let onScheduleDebouncedAudioTitlePersist: (UUID, String) -> Void
    let onPersistCommittedAudioTitle: (UUID) -> Void
    let onPlayVideo: (UUID) -> Void
    let onViewImage: (UUID) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attachments").sectionHeader()
            
            if !stagedImages.isEmpty || !stagedVideos.isEmpty {
                let visuals = stagedImages + stagedVideos
                let columns = [GridItem(.adaptive(minimum: 128), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(visuals, id: \.id) { att in
                        if stagedImages.contains(where: { $0.id == att.id }) {
                            // Image tile
                            ZStack(alignment: .topTrailing) {
                                if let ui = UIImage(data: att.data) {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 128, height: 128)
                                        .background(Color.secondary.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture { onViewImage(att.id) }
                                } else {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.secondary.opacity(0.08))
                                        Image(systemName: "photo")
                                            .imageScale(.large)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 128, height: 128)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onViewImage(att.id) }
                                }
                                
                                // Controls: star to set thumbnail, delete
                                VStack(spacing: 6) {
                                    Text(selectedThumbnailID == att.id ? "★" : "☆")
                                        .font(.system(size: 16))
                                        .padding(8)
                                        .background(.ultraThinMaterial, in: Circle())
                                        .onTapGesture {
                                            if selectedThumbnailID == att.id {
                                                selectedThumbnailID = nil
                                            } else {
                                                selectedThumbnailID = att.id
                                            }
                                        }
                                    
                                    Button {
                                        stagedImages.removeAll { $0.id == att.id }
                                        if selectedThumbnailID == att.id {
                                            selectedThumbnailID = nil
                                        }
                                        onPersistStagedAttachments()
                                        // Mirror delete to staging store
                                        if let ref = StagingStore.list().first(where: { $0.id == att.id }) {
                                            StagingStore.remove(ref)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 16, weight: .semibold))
                                            .padding(8)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(6)
                            }
                        } else if stagedVideos.contains(where: { $0.id == att.id }) {
                            // Video tile
                            ZStack(alignment: .topTrailing) {
                                // Ensure video tiles sit behind audio rows in hit testing
                                // so audio play buttons remain responsive when regions overlap.
                                // (Audio rows use .zIndex(1).)
                                
                                ZStack {
                                    if let thumb = videoThumbnails[att.id] {
                                        Image(uiImage: thumb)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 128, height: 128)
                                            .clipped()
                                    } else {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.secondary.opacity(0.08))
                                            .frame(width: 128, height: 128)
                                        Image(systemName: "film")
                                            .imageScale(.large)
                                            .foregroundStyle(.secondary)
                                    }
                                    // Center play overlay button
                                    Button(action: { onPlayVideo(att.id) }) {
                                        ZStack {
                                            Circle()
                                                .fill(.ultraThinMaterial)
                                                .frame(width: 44, height: 44)
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                }
                                .frame(width: 128, height: 128)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onPlayVideo(att.id)
                                }
                                
                                // Delete button
                                VStack(spacing: 6) {
                                    Button {
                                        // Remove surrogate temp file best-effort
                                        let tmp = FileManager.default.temporaryDirectory
                                            .appendingPathComponent(att.id.uuidString)
                                            .appendingPathExtension("mov")
                                        try? FileManager.default.removeItem(at: tmp)
                                        
                                        // Also remove any stray copies created in Documents by older replace paths
                                        if let docs = FileManager.default.urls(for: .documentDirectory,
                                                                               in: .userDomainMask).first {
                                            let docMov = docs
                                                .appendingPathComponent(att.id.uuidString)
                                                .appendingPathExtension("mov")
                                            let docMp4 = docs
                                                .appendingPathComponent(att.id.uuidString)
                                                .appendingPathExtension("mp4")
                                            try? FileManager.default.removeItem(at: docMov)
                                            try? FileManager.default.removeItem(at: docMp4)
                                        }
                                        
                                        stagedVideos.removeAll { $0.id == att.id }
                                        videoThumbnails.removeValue(forKey: att.id)
                                        onPersistStagedAttachments()
                                        // Mirror delete to staging store
                                        if let ref = StagingStore.list().first(where: { $0.id == att.id }) {
                                            StagingStore.remove(ref)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 16, weight: .semibold))
                                            .padding(8)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(6)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Audio list
            ForEach(stagedAudio, id: \.id) { att in
                HStack(spacing: 12) {
                    Button(action: { onTogglePlay(att.id) }) {
                        Image(systemName: (currentlyPlayingID == att.id && isAudioPlaying) ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(recorderIcon)
                    
                    // Binding for the audio title text field
                    let titleBinding = Binding<String>(
                        get: {
                            if focusedAudioTitleID.wrappedValue == att.id {
                                #if DEBUG
                                print("[PracticeTimer] Title.get focused id=\(att.id) buffer=\(audioTitleEditingBuffer[att.id] ?? "")")
                                #endif
                                return audioTitleEditingBuffer[att.id] ?? ""
                            } else {
                                let t = (audioTitles[att.id] ?? "")
                                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                #if DEBUG
                                print("[PracticeTimer] Title.get unfocused id=\(att.id) title=\(t) auto=\(audioAutoTitles[att.id] ?? "")")
                                #endif
                                if t.isEmpty {
                                    return audioAutoTitles[att.id] ?? ""
                                }
                                return audioTitles[att.id] ?? ""
                            }
                        },
                        set: { newValue in
                            #if DEBUG
                            let isFocused = (focusedAudioTitleID.wrappedValue == att.id)
                            print("[PracticeTimer] Title.set id=\(att.id) isFocused=\(isFocused) new=\(newValue)")
                            #endif
                            // Only mutate the editing buffer while focused; do not write to audioTitles yet
                            if focusedAudioTitleID.wrappedValue == att.id {
                                audioTitleEditingBuffer[att.id] = newValue
                                let nonEmpty = !newValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                                if nonEmpty && !audioTitleDidImmediatePersist.contains(att.id) {
                                    // First meaningful keystroke — persist immediately
                                    audioTitleDidImmediatePersist.insert(att.id)
                                    onPersistAudioTitleImmediately(att.id, newValue)
                                } else {
                                    // Subsequent edits — debounce to reduce churn
                                    onScheduleDebouncedAudioTitlePersist(att.id, newValue)
                                }
                            }
                        }
                    )
                    
                    TextField("Title", text: titleBinding)
                        .textFieldStyle(.plain)
                        .disableAutocorrection(true)
                        .focused(focusedAudioTitleID, equals: att.id)
                        .onTapGesture {
                            // Enter focus and initialize an empty buffer so the field clears for fresh input
                            focusedAudioTitleID.wrappedValue = att.id
                        }
                        .onChange(of: focusedAudioTitleID.wrappedValue) { _, newFocus in
                            if newFocus == att.id {
                                #if DEBUG
                                print("[PracticeTimer] focus gained id=\(att.id)")
                                #endif
                                // Gained focus: clear the editing buffer so user starts from empty
                                audioTitleEditingBuffer[att.id] = ""
                            } else if newFocus == nil || newFocus != att.id {
                                #if DEBUG
                                print("[PracticeTimer] focus lost id=\(att.id) buffer=\(audioTitleEditingBuffer[att.id] ?? "")")
                                #endif
                                
                                // Lost focus from this field: commit buffer to stored titles
                                if let buffer = audioTitleEditingBuffer[att.id] {
                                    let trimmed = buffer.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                    
                                    if trimmed.isEmpty {
                                        // Restore auto-title if user left it empty
                                        audioTitles[att.id] = audioAutoTitles[att.id] ?? ""
                                    } else {
                                        audioTitles[att.id] = buffer
                                    }
                                    
                                    // Clean up buffer
                                    audioTitleEditingBuffer.removeValue(forKey: att.id)
                                    
                                    // Persist immediately to StagingStore
                                    onPersistCommittedAudioTitle(att.id)
                                    
                                    // Persist after any change (debounced)
                                    DispatchQueue.main.async {
                                        onPersistStagedAttachments()
                                    }
                                }
                            }
                        }
                        .onSubmit {
                            #if DEBUG
                            print("[PracticeTimer] Title.submit id=\(att.id) buffer=\(audioTitleEditingBuffer[att.id] ?? "")")
                            #endif
                            // Commit on submit as well (Enter/Return key)
                            let buffer = audioTitleEditingBuffer[att.id] ?? ""
                            let trimmed = buffer.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                            if trimmed.isEmpty {
                                audioTitles[att.id] = audioAutoTitles[att.id] ?? ""
                            } else {
                                audioTitles[att.id] = buffer
                            }
                            audioTitleEditingBuffer.removeValue(forKey: att.id)
                            onPersistCommittedAudioTitle(att.id)
                            DispatchQueue.main.async {
                                onPersistStagedAttachments()
                            }
                        }
                    
                    if let secs = audioDurations[att.id] {
                        Text(formattedClipDuration(secs))
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .font(.subheadline)
                    }
                    
                    Spacer(minLength: 8)
                    
                    Button(role: .destructive, action: { onDeleteAudio(att.id) }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
                .zIndex(1)
            }
            
            if let warn = stagedSizeWarning {
                Text(warn)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(.top, 4)
            }
        }
    }
}

