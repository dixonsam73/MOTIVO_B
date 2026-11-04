//
//  SyncTestAppDelegate.swift
//  MOTIVO — private iCloud sync. Compiled in every configuration; nothing
//  here runs until the person turns sync on (see JournalSyncCoordinator).
//
//  The app's own silent-push path (stage J). The engine never fetches
//  (C-149), so the app fetches records itself and a change on the other
//  device must reach the app another way: a
//  CKDatabaseSubscription of the app's own, whose content-available push
//  lands here. When the engine is automatic this does nothing.
//

import UIKit
import CloudKit

final class SyncTestAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { completionHandler(.noData); return }
        Task { @MainActor in
            guard let engine = JournalSyncCoordinator.shared.engine else { completionHandler(.noData); return }
            let acted = await engine.pushReceived()
            completionHandler(acted ? .newData : .noData)
        }
    }
}
