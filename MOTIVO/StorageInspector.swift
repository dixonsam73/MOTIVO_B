import Foundation

#if DEBUG
struct StorageInspector {
    static func logSandboxUsage(tag: String) {
        let fileManager = FileManager.default
        
        func folderSize(at url: URL) -> Int64 {
            guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [], errorHandler: nil) else {
                return 0
            }
            var totalSize: Int64 = 0
            for case let fileURL as URL in enumerator {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    if resourceValues.isRegularFile == true, let fileSize = resourceValues.fileSize {
                        totalSize += Int64(fileSize)
                    }
                } catch {
                    // Ignore errors for individual files
                }
            }
            return totalSize
        }
        
        func sizeString(bytes: Int64) -> String {
            let mb = Double(bytes) / 1_048_576
            return "\(bytes) bytes (\(String(format: "%.2f", mb)) MB)"
        }
        
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsURL = urls.first
        
        let appSupportURL = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("MOTIVO")
        
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        
        let documentsSize: Int64
        if let documentsURL = documentsURL, fileManager.fileExists(atPath: documentsURL.path) {
            documentsSize = folderSize(at: documentsURL)
        } else {
            documentsSize = 0
        }
        
        let appSupportSize: Int64
        if let appSupportURL = appSupportURL, fileManager.fileExists(atPath: appSupportURL.path) {
            appSupportSize = folderSize(at: appSupportURL)
        } else {
            appSupportSize = 0
        }
        
        let tempSize: Int64
        if fileManager.fileExists(atPath: tempURL.path) {
            tempSize = folderSize(at: tempURL)
        } else {
            tempSize = 0
        }
        
        print("[StorageInspector - \(tag)] Documents: \(sizeString(bytes: documentsSize)), MOTIVO Application Support: \(sizeString(bytes: appSupportSize)), Temp: \(sizeString(bytes: tempSize))")
    }
}
#endif
