//
// PracticeTimerStore.swift
//
// Provides file-backed persistence for PracticeTimer staged video payloads.
// Stores JSON data under Application Support/MOTIVO/PracticeTimer/stagedVideo.json
// Includes one-time migration from UserDefaults key "PracticeTimer.stagedVideo".
// Ensures storage directory exists and is excluded from backups.
//

import Foundation

enum PracticeTimerStore {
    
    private static let userDefaultsKey = "PracticeTimer.stagedVideo"
    
    private static let baseDir: URL = {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("MOTIVO", isDirectory: true)
            .appendingPathComponent("PracticeTimer", isDirectory: true)
    }()
    
    private static let fileURL = baseDir.appendingPathComponent("stagedVideo.json", isDirectory: false)
    
    private static func bootstrap() {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true, attributes: nil)
            
            // Exclude MOTIVO folder from backups
            var motivoDir = baseDir.deletingLastPathComponent()
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            
            try motivoDir.setResourceValues(resourceValues)
        } catch {
            #if DEBUG
            print("PracticeTimerStore.bootstrap error: \(error)")
            #endif
        }
    }
    
    /// Loads staged video JSON data.
    /// If file exists, returns its contents.
    /// Otherwise attempts one-time migration from UserDefaults key "PracticeTimer.stagedVideo".
    /// Returns nil if no data found.
    static func loadStagedVideo() -> Data? {
        bootstrap()
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                return try Data(contentsOf: fileURL)
            } catch {
                #if DEBUG
                print("PracticeTimerStore.loadStagedVideo read error: \(error)")
                #endif
                return nil
            }
        }
        
        // Try migration from UserDefaults
        let defaults = UserDefaults.standard
        
        // Check if key exists to avoid unnecessary calls
        guard defaults.object(forKey: userDefaultsKey) != nil else {
            return nil
        }
        
        var migratedData: Data?
        
        if let data = defaults.data(forKey: userDefaultsKey) {
            migratedData = data
        } else if let str = defaults.string(forKey: userDefaultsKey) {
            migratedData = str.data(using: .utf8)
        }
        
        guard let dataToMigrate = migratedData else {
            // Remove the key if present but can't read data
            defaults.removeObject(forKey: userDefaultsKey)
            #if DEBUG
            print("PracticeTimerStore.loadStagedVideo migration found key but failed to decode data.")
            #endif
            return nil
        }
        
        do {
            try dataToMigrate.write(to: fileURL, options: .atomic)
            defaults.removeObject(forKey: userDefaultsKey)
            #if DEBUG
            print("PracticeTimerStore.loadStagedVideo migrated data from UserDefaults to file.")
            #endif
            return dataToMigrate
        } catch {
            #if DEBUG
            print("PracticeTimerStore.loadStagedVideo migration write error: \(error)")
            #endif
            return nil
        }
    }
    
    /// Saves staged video JSON data.
    /// If `data` is nil, removes the staged video file.
    /// Does NOT write to UserDefaults.
    static func saveStagedVideo(_ data: Data?) {
        bootstrap()
        let fileManager = FileManager.default
        
        if let data = data {
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                #if DEBUG
                print("PracticeTimerStore.saveStagedVideo write error: \(error)")
                #endif
            }
        } else {
            do {
                if fileManager.fileExists(atPath: fileURL.path) {
                    try fileManager.removeItem(at: fileURL)
                }
            } catch {
                #if DEBUG
                print("PracticeTimerStore.saveStagedVideo remove error: \(error)")
                #endif
            }
        }
    }
    
    /// Clears the staged video file if it exists.
    static func clear() {
        saveStagedVideo(nil)
    }
}

