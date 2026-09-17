import Foundation
import Combine
@MainActor class AuthManager { var hasConnectedIdentity = true }
enum BackendConfig { static let isConfigured = true }
@MainActor enum LocalFactoryReset { static let isInProgress = false }
@MainActor enum MembershipAttestationService {
 enum Outcome: Equatable { case result(String) }
 static var waits: [String: CheckedContinuation<Outcome,Never>] = [:]
 static var calls = [String]()
 static func attest(auth: AuthManager,isLocallyEntitled:Bool,reason:String) async -> Outcome {
 calls.append(reason)
 return await withCheckedContinuation { waits[reason]=$0 }
 }
 static func finish(_ reason:String) { waits.removeValue(forKey:reason)!.resume(returning:.result(reason)) }
}
@main struct Probe {
 @MainActor static func main() async {
 let c=MembershipAttestationCoordinator(); let auth=AuthManager()
 let a=Task { await c.attestIfNeeded(auth:auth,isLocallyEntitled:true,reason:"old-A",force:true) }
 while MembershipAttestationService.waits["old-A"] == nil { await Task.yield() }
 c.reset()
 let b=Task { await c.attestIfNeeded(auth:auth,isLocallyEntitled:true,reason:"new-B",force:true) }
 while MembershipAttestationService.waits["new-B"] == nil { await Task.yield() }
 MembershipAttestationService.finish("old-A"); _=await a.value
 print("COORDINATOR while B pending: isAttesting",c.isAttesting,"outcome",String(describing:c.lastOutcome))
 let third=Task { await c.attestIfNeeded(auth:auth,isLocallyEntitled:true,reason:"third",force:true) }
 for _ in 0..<100 { await Task.yield() }
 print("COORDINATOR service calls before B completes:",MembershipAttestationService.calls)
 if MembershipAttestationService.waits["third"] != nil { MembershipAttestationService.finish("third") }
 MembershipAttestationService.finish("new-B"); _=await b.value; _=await third.value
 }
}
