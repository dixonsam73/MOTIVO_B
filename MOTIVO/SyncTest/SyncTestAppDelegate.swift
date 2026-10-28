//
//  SyncTestAppDelegate.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
//
//  The app's own silent-push path (stage J). CKSyncEngine acts on pushes by
//  itself only while it syncs automatically; while media waits for Wi-Fi the
//  engine is built without automatic sync and the app fetches records itself,
//  so a change on the other device must reach the app another way: a
//  CKDatabaseSubscription of the app's own, whose content-available push
//  lands here. When the engine is automatic this does nothing.
//

#if SYNCTEST
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
#endif
