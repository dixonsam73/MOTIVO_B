import Foundation
import Combine

/// Own block-observer tokens, not the view value that registered them. A generation
/// check also discards notifications already queued when an owner removes/reinstalls.
@MainActor
final class AudioNotificationObservers: ObservableObject {
    private let center: NotificationCenter
    private var tokens: [Notification.Name: NSObjectProtocol] = [:]
    private var generations: [Notification.Name: UUID] = [:]
    var isEmpty: Bool { tokens.isEmpty }

    init(center: NotificationCenter = .default) { self.center = center }

    func observe(_ name: Notification.Name, object: AnyObject? = nil,
                 handler: @escaping @MainActor (Notification) -> Void) {
        guard tokens[name] == nil else { return }
        let generation = UUID()
        generations[name] = generation
        tokens[name] = center.addObserver(forName: name, object: object, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard self?.generations[name] == generation else { return }
                handler(note)
            }
        }
    }

    func removeAll() {
        generations.removeAll()
        tokens.values.forEach(center.removeObserver)
        tokens.removeAll()
    }

    deinit { tokens.values.forEach(center.removeObserver) }
}
