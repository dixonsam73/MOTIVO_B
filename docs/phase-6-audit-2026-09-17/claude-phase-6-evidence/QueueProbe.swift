import Foundation
import Combine
enum BackendLogger { static func notice(_ text: String) {} }
enum BackendMode { case backendPreview, backendConnected, localSimulation }
@MainActor final class BackendEnvironment {
 static let shared = BackendEnvironment()
 var mode = BackendMode.backendConnected
 let publish = ProbeService()
}
@MainActor final class ProbeService {
 var owner = "A"
 var observedOwners: [String] = []
 func uploadPost(_ payload: SessionSyncQueue.PostPublishPayload) async -> Result<Void,Error> {
 observedOwners.append(owner); return .success(())
 }
 func unsharePost(_ id: UUID) async -> Result<Void,Error> { .success(()) }
}
@main struct Probe {
 @MainActor static func main() async throws {
 let q = SessionSyncQueue.shared
 let file = SessionSyncQueue.makeFileURL()
 let id = UUID()
 func payload(_ visible: Bool) -> SessionSyncQueue.PostPublishPayload {
 .init(id:id,sessionID:id,sessionTimestamp:Date(),title:"synthetic",durationSeconds:10,activityType:nil,activityDetail:nil,instrumentLabel:nil,mood:nil,effort:nil,isPublic:visible)
 }
 q.enqueue(payload(true))
 let diskBefore = try Data(contentsOf:file)
 let parent = file.deletingLastPathComponent()
 try FileManager.default.setAttributes([.posixPermissions:0o555],ofItemAtPath:parent.path)
 defer { try? FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:parent.path) }
 q.enqueue(payload(false))
 print("QUEUE failed write returns normally, memory op:",q.items[0].op.rawValue)
 print("QUEUE previous durable bytes unchanged:",try Data(contentsOf:file)==diskBefore)
 try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:parent.path)
 let persisted = try JSONDecoder().decode([SessionSyncQueue.PostPublishPayload].self,from:Data(contentsOf:file))
 print("QUEUE actual durable state for relaunch:",persisted[0].op.rawValue)
 q.clear(); q.enqueue(payload(true))
 BackendEnvironment.shared.publish.owner = "B"
 await q.flushNow()
 print("QUEUE old A payload sent with current service owner:",BackendEnvironment.shared.publish.observedOwners,"remaining:",q.items.count)
 q.clear()
 }
}
