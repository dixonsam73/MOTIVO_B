// CHANGE-ID: 20260610_1430_PDFPhase2A
// SCOPE: PDF Scores Phase 2A — metadata-only PDF page selection; staged-to-persisted UUID migration; selected-page viewer routing and display labels.
// SEARCH-TOKEN: 20260610_1430-PDF-PAGE-SELECTION
//
//  StagedAttachment.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 12/09/2025.
//

import Foundation
import SwiftUI
import PDFKit

struct StagedAttachment: Identifiable {
    let id: UUID
    let data: Data
    let kind: AttachmentKind
    var selectedPages: [Int]? = nil
}

enum PDFSelectedPagesStore {
    static let key = "pdfSelectedPages_v1"

    static func load() -> [String: [Int]] {
        let raw = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        var output: [String: [Int]] = [:]

        for (key, value) in raw {
            if let ints = value as? [Int] {
                output[key] = sanitized(ints)
            } else if let numbers = value as? [NSNumber] {
                output[key] = sanitized(numbers.map { $0.intValue })
            }
        }

        return output
    }

    static func pages(for id: UUID) -> [Int]? {
        load()[id.uuidString]
    }

    static func setPages(_ pages: [Int]?, for id: UUID) {
        var map = load()
        if let sanitized = sanitized(pages), !sanitized.isEmpty {
            map[id.uuidString] = sanitized
        } else {
            map.removeValue(forKey: id.uuidString)
        }
        UserDefaults.standard.set(map, forKey: key)
    }

    static func migratePages(from stagedID: UUID, stagedPages: [Int]?, to persistedID: UUID?) {
        guard let persistedID else { return }
        let pages = sanitized(stagedPages ?? pages(for: stagedID))
        setPages(pages, for: persistedID)
        setPages(nil, for: stagedID)
    }

    static func sanitized(_ pages: [Int]?) -> [Int]? {
        guard let pages else { return nil }
        let clean = Array(Set(pages.filter { $0 > 0 })).sorted()
        return clean.isEmpty ? nil : clean
    }

    static func pageCount(for data: Data) -> Int {
        PDFDocument(data: data)?.pageCount ?? 0
    }

    static func pageCount(for url: URL) -> Int {
        PDFDocument(url: url)?.pageCount ?? 0
    }
}

enum PDFSelectedPagesFormatter {
    static func summary(for pages: [Int]?) -> String {
        guard let clean = PDFSelectedPagesStore.sanitized(pages), !clean.isEmpty else {
            return "Entire document"
        }

        if clean.count == 1, let page = clean.first {
            return "Page \(page)"
        }

        return "Pages " + clean.map(String.init).joined(separator: ",")
    }
}

struct PDFPageSelectionRequest: Identifiable {
    let id: UUID
    let pageCount: Int
}

struct PDFPageSelectionSheet: View {
    let pageCount: Int
    @Binding var selectedPages: [Int]?

    @Environment(\.dismiss) private var dismiss
    @State private var draftSelection: Set<Int> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        draftSelection.removeAll()
                    } label: {
                        HStack {
                            Image(systemName: draftSelection.isEmpty ? "checkmark.square.fill" : "square")
                            Text("Entire document")
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("Page numbers refer to pages within the PDF document. Leave all pages unselected to attach the entire PDF.")
                }

                Section("Pages") {
                    ForEach(1...max(pageCount, 1), id: \.self) { page in
                        Button {
                            if draftSelection.contains(page) {
                                draftSelection.remove(page)
                            } else {
                                draftSelection.insert(page)
                            }
                        } label: {
                            HStack {
                                Image(systemName: draftSelection.contains(page) ? "checkmark.square.fill" : "square")
                                Text("\(page)")
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Select PDF Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let sorted = draftSelection.sorted()
                        selectedPages = sorted.isEmpty ? nil : sorted
                        dismiss()
                    }
                }
            }
            .onAppear {
                draftSelection = Set(PDFSelectedPagesStore.sanitized(selectedPages) ?? [])
            }
        }
    }
}
