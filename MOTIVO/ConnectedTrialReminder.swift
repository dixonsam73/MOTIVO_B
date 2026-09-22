//
//  ConnectedTrialReminder.swift
//  MOTIVO
//
//  FOUNDING 500 — the in-feed reminder that a free year is ending.
//
//  Samuel accepted automatic paid renewal on condition of notice near expiry, and
//  approved a subtle, dismissible card in the journal feed reusing the existing
//  milestone-insight styling. This is the decision half; the card is the view.
//
//  IT IS AN IN-APP REMINDER AND NOT ASSURED DELIVERY. A member who does not open
//  Études in the final thirty days never sees it. The app schedules no
//  notifications and none is invented here.
//
//  DISMISSAL IS PER TRIAL, ON THIS DEVICE. Dismissing must last across launches —
//  otherwise it is a delay, not a dismissal — but must NOT carry to a later,
//  different trial, or somebody who resubscribes a year on would be silently not
//  warned. The identity pairs the subscription's `originalID` with the period end
//  precisely so those two cases separate.
//
//  It is `UserDefaults`, so it is **local to this device** and does not follow the
//  member to another one — they would see the card again there. That is accepted:
//  this is a UI preference, not authority. Losing it shows one extra card, and
//  nothing about money or access depends on it.
//

import Foundation

enum ConnectedTrialReminder {

    /// Matches the Profile notice window, so the two cannot disagree about when
    /// "near expiry" begins.
    static var noticeWindow: TimeInterval { ConnectedRenewalPresentation.noticeWindow }

    private static let dismissedKey = "connected.trialReminder.dismissedIdentities_v1"

    /// Whether to show the card.
    ///
    /// Pure, so every branch is testable: no trial, no end date, outside the
    /// window, already ended, already dismissed.
    static func shouldShow(
        trialIdentity: String?,
        periodEnd: Date?,
        dismissedIdentities: [String],
        now: Date = Date()
    ) -> Bool {
        // No identity means no active free trial — the store only sets it inside
        // one — so there is nothing to warn about.
        guard let trialIdentity, !trialIdentity.isEmpty else { return false }
        guard let periodEnd else { return false }
        // An elapsed date describes access that has already ended.
        guard periodEnd > now else { return false }
        guard periodEnd.timeIntervalSince(now) <= noticeWindow else { return false }
        return !dismissedIdentities.contains(trialIdentity)
    }

    /// The card's text. Deliberately shares `ConnectedRenewalPresentation`'s
    /// wording rules — neutral about renewal, and never offering a plan change as
    /// a way to avoid payment.
    ///
    /// **"free trial", not "free year".** `freeTrialIdentity` is set for a free
    /// trial of ANY length, so this text is shown whenever one is ending — and
    /// the Founding 500 offer being a year does not make every trial one. Naming
    /// a duration the offer may not have would be a false statement about
    /// somebody's money.
    ///
    /// **"If automatic renewal is on", NOT "unless you cancel" — corrected
    /// 22 September after Q10 failed on device.** A member who had cancelled was
    /// still being told to cancel, which implies the cancellation did not take.
    /// **"If still active" would have been wrong too**: a cancelled trial remains
    /// active until it expires. Automatic renewal is the actual condition, and
    /// stating it asserts nothing about what the member has already done.
    ///
    /// Identical to `ConnectedRenewalPresentation`'s free-trial notice, so the
    /// feed and Profile cannot drift apart.
    static func message(
        periodEnd: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let date = ConnectedRenewalPresentation.formattedDate(
            periodEnd, locale: locale, timeZone: timeZone)
        return "Your free trial ends on \(date). If automatic renewal is on, Études Connected then continues at the standard price."
    }

    static let title = "Your free trial"
    static let manageActionTitle = "Manage Subscription"
    static let dismissActionLabel = "Dismiss"

    /// Shown when Apple's management sheet cannot be presented, so the member is
    /// not left with a button that silently does nothing.
    static let manageFailureTitle = "Manage Subscription unavailable"
    static let manageFailureMessage =
        "Open Settings › Apple Account › Subscriptions to manage your Études Connected membership."

    // MARK: - Persistence

    static func dismissedIdentities(
        defaults: UserDefaults = .standard
    ) -> [String] {
        defaults.stringArray(forKey: dismissedKey) ?? []
    }

    /// Records a dismissal for one trial.
    ///
    /// Bounded: only the most recent few are kept, because the list would
    /// otherwise grow forever for a member who resubscribes repeatedly, and an
    /// unbounded preference is a slow leak nobody notices.
    static func recordDismissal(
        trialIdentity: String,
        defaults: UserDefaults = .standard
    ) {
        guard !trialIdentity.isEmpty else { return }
        var identities = dismissedIdentities(defaults: defaults)
        guard !identities.contains(trialIdentity) else { return }
        identities.append(trialIdentity)
        if identities.count > 8 { identities.removeFirst(identities.count - 8) }
        defaults.set(identities, forKey: dismissedKey)
    }
}
