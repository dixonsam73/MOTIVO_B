//
//  QuickLookPreview.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 10/09/2025.
//

import SwiftUI
import QuickLook

/// Reusable QuickLook preview for file URLs.
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        private let item: PreviewItem
        init(url: URL) { self.item = PreviewItem(url: url) }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { item }
    }

    final class PreviewItem: NSObject, QLPreviewItem {
        let url: URL
        init(url: URL) { self.url = url }
        var previewItemURL: URL? { url }
    }
}
