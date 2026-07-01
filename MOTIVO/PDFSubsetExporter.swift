import Foundation
import PDFKit

enum PDFSubsetExporter {
    enum ExportError: Error {
        case unreadableSource
        case noValidPages
        case writeFailed
    }

    static func export(from sourceURL: URL, selectedPages: [Int]) throws -> URL {
        guard let sourceDocument = PDFDocument(url: sourceURL) else {
            throw ExportError.unreadableSource
        }

        let validPages = Array(Set(selectedPages.filter { pageNumber in
            pageNumber > 0 && pageNumber <= sourceDocument.pageCount
        })).sorted()

        guard !validPages.isEmpty else {
            throw ExportError.noValidPages
        }

        let outputDocument = PDFDocument()
        for pageNumber in validPages {
            let zeroBasedIndex = pageNumber - 1
            guard let page = sourceDocument.page(at: zeroBasedIndex) else { continue }
            outputDocument.insert(page, at: outputDocument.pageCount)
        }

        guard outputDocument.pageCount > 0 else {
            throw ExportError.noValidPages
        }

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let safeBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Selected Pages" : baseName
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeBaseName)-SelectedPages-\(UUID().uuidString)")
            .appendingPathExtension("pdf")

        guard outputDocument.write(to: outputURL) else {
            throw ExportError.writeFailed
        }

        return outputURL
    }
}
