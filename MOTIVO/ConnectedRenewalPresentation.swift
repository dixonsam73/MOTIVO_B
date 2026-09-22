//
//  ConnectedRenewalPresentation.swift
//  MOTIVO
//
//  FOUNDING 500 — telling a member when their free year ends, before it does.
//
//  Samuel accepted automatic paid renewal on condition of clear upfront terms
//  AND notice near expiry. This is the notice half.
//
//  IT IS IN-APP, AND THAT IS A MEASURED CONSTRAINT RATHER THAN A PREFERENCE.
//  The app contains no `UNUserNotificationCenter` usage anywhere, so there is no
//  notification infrastructure to schedule a reminder through, and none is
//  invented here. Promising delivery we cannot make — a push the member has
//  disabled, or an email system that does not exist — would be worse than
//  showing it where they already look.
//
//  Pure values in, strings out, so the wording can be tested without StoreKit.
//

import Foundation

enum ConnectedRenewalPresentation {

    /// How close to the end the reminder starts appearing.
    ///
    /// Long enough to act — cancelling, or switching plan — and short enough not
    /// to nag for eleven months of a twelve-month offer.
    static let noticeWindow: TimeInterval = 30 * 24 * 60 * 60

    enum Notice: Equatable {
        /// Nothing to say yet.
        case none
        /// A period is ending soon.
        case periodEnding(String)
    }

    /// Whether and what to tell the member.
    ///
    /// **Absent dates produce `.none`.** A missing expiry is not evidence that
    /// something is about to end, and inventing a warning from it would be the
    /// same error as inferring absence from a missing field.
    ///
    /// **NOTHING HERE SAYS "RENEWS".** `expirationDate` is when the current
    /// period ends; after a cancellation it is when access stops. Telling a
    /// member who has already cancelled that their membership "renews on" a date
    /// would be false, and we do not read verified renewal info, so the wording
    /// stays neutral.
    ///
    /// **CORRECTED 22 September, and the earlier reasoning was falsified on
    /// device.** This comment used to claim that saying payment "continues
    /// unless you cancel" was *"safe in the other direction: somebody who has
    /// already cancelled is not misled"*. **Q10 showed otherwise** — cancelled at
    /// 15:57, and at 15:59 Profile still told the member to cancel. That implies
    /// their cancellation did not take, which on a screen about money is the more
    /// damaging error, not the harmless one.
    ///
    /// The condition is now stated as what it actually is: **automatic renewal**.
    /// Note that "still active" would ALSO have been wrong — a cancelled trial
    /// remains active until it expires.
    static func notice(
        periodEnd: Date?,
        isFreeTrial: Bool,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Notice {
        guard let periodEnd else { return .none }
        guard periodEnd > now else { return .none }
        guard periodEnd.timeIntervalSince(now) <= noticeWindow else { return .none }

        let date = formattedDate(periodEnd, locale: locale, timeZone: timeZone)
        // "change plan" is deliberately absent: switching between monthly and
        // annual does not avoid payment, and offering it as a way out would be
        // a false escape route. Q12 measured the switch preserving the free
        // trial, which makes that even clearer.
        //
        // "free trial", not "free period": the same words the member was shown
        // at purchase, and the same sentence the feed card uses.
        return .periodEnding(
            isFreeTrial
            ? "Your free trial ends on \(date). If automatic renewal is on, Études Connected then continues at the standard price."
            : "Your current period ends on \(date)."
        )
    }

    /// The exact end date, answerable at any time rather than only in the last
    /// month.
    ///
    /// Neutral for the same reason as `notice`: this cannot distinguish a period
    /// that will renew from one that will lapse.
    static func periodEndSummary(
        periodEnd: Date?,
        isFreeTrial: Bool,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        guard let periodEnd else { return nil }
        let date = formattedDate(periodEnd, locale: locale, timeZone: timeZone)
        return isFreeTrial ? "Free until \(date)" : "Current period ends \(date)"
    }

    /// Localized, and in the member's own time zone — a renewal date shown in
    /// UTC can be a day out, which is exactly the kind of small wrongness that
    /// costs trust on a page about money.
    static func formattedDate(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        // Set as properties: `.timeZone(_:)` on the style takes a formatting
        // SYMBOL, not a `TimeZone`, and reads as though it would work.
        var style = Date.FormatStyle(date: .long, time: .omitted)
        style.locale = locale
        style.timeZone = timeZone
        return date.formatted(style)
    }
}
