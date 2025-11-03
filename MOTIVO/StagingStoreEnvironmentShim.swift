import Foundation
import SwiftUI

// Shim to satisfy views that use `@EnvironmentObject private var stagingStore: StagingStore`.
// We alias `StagingStore` to the existing ObservableObject wrapper `StagingStoreObject`.
// This avoids subclassing a final class and avoids changing any logic or UI.

// Notes:
// - Make the alias "internal" to match the access level of `StagingStoreObject` and avoid
//   "Type alias cannot be declared public because its underlying type uses an internal type".
// - Avoid invalid redeclaration by only providing the alias when a symbol named `StagingStore`
//   is not already available. We do this via a custom compile-time flag you can define in
//   build settings (e.g., OTHER_SWIFT_FLAGS: -D HAS_STAGING_STORE_SHIM) to enable the shim only where needed.
// - If you later introduce a real `StagingStore` type in a target, simply do not define
//   `HAS_STAGING_STORE_SHIM` for that target (or remove this file entirely).

#if !canImport(ObjectiveC) || !swift(>=5.0)
// No-op on exotic platforms, but keep the alias available where Swift compiles.
#endif

#if HAS_STAGING_STORE_SHIM
// Only provide the alias when explicitly enabled for targets that lack a real `StagingStore`.
// Enable by adding OTHER_SWIFT_FLAGS: -D HAS_STAGING_STORE_SHIM in the target's build settings.
// Keep the access level internal to match `StagingStoreObject` and prevent visibility errors.
internal typealias StagingStore = StagingStoreObject
#endif
