//
//  ConnectedOfferPresentation.swift
//  MOTIVO
//
//  FOUNDING 500 — what the membership screen says about an introductory offer.
//
//  Apple owns entitlement: the offer is Apple's own introductory offer on the
//  Connected subscriptions, applied and renewed by Apple. Nothing here grants
//  anything, and no authority predicate consults it.
//
//  TWO LAYERS, DELIBERATELY. `copy(isEligible:offer:displayPrice:cadence:)` is a
//  pure function of plain values, so every branch is unit-testable; the `Product`
//  overload is a thin adapter that only extracts those values. A `Product` cannot
//  be constructed in a test, so putting the decisions in the adapter would make
//  them untestable.
//
//  THE DISCLOSURE RULE. Samuel accepted automatic paid renewal on condition of
//  clear upfront terms, so wherever a free period is shown the copy also states
//  the price that follows, the cadence, that it renews automatically, and that it
//  can be cancelled. The `freeTrial` case carries all four as parameters — which
//  makes omission awkward, NOT impossible, since empty strings compile. The
//  guarantee is the function's behaviour, asserted by tests, not the type.
//

import Foundation
import StoreKit

enum ConnectedOfferPresentation {

    /// An introductory offer reduced to the values the copy needs. Constructible
    /// in a test, unlike `Product.SubscriptionOffer`.
    struct IntroductoryOffer: Equatable {
        enum Unit: Equatable { case day, week, month, year }
        let unit: Unit
        let value: Int
        /// Apple expresses three months as one 3-month period or three 1-month
        /// periods; this multiplies the period, so the second is not read as one.
        let periodCount: Int
        /// A pay-up-front or pay-as-you-go introductory price is a discount, not
        /// a free trial, and must never be described as free.
        let isFreeTrial: Bool
    }

    enum OfferCopy: Equatable {
        case standard(price: String, cadence: String)
        case freeTrial(
            duration: String,
            thenPrice: String,
            cadence: String,
            renewalNotice: String,
            cancellationNotice: String
        )
    }

    // MARK: - The pure decision

    /// Every branch that decides whether a member is shown trial language.
    static func copy(
        isEligible: Bool,
        offer: IntroductoryOffer?,
        displayPrice: String,
        cadence: String,
        locale: Locale = .autoupdatingCurrent
    ) -> OfferCopy {
        guard isEligible,
              let offer,
              offer.isFreeTrial else {
            return .standard(price: displayPrice, cadence: cadence)
        }
        return .freeTrial(
            duration: durationText(offer, locale: locale),
            thenPrice: displayPrice,
            cadence: cadence,
            renewalNotice: renewalNotice,
            cancellationNotice: cancellationNotice
        )
    }

    /// A localized duration for the offer period.
    ///
    /// **`DateComponents.FormatStyle`, not hand-written plurals.** The previous
    /// version built "1 year" / "3 months" in English by hand, which is wrong in
    /// every other language and gets plural rules wrong in several. Foundation
    /// already knows them.
    ///
    /// `locale` is a parameter so tests are deterministic and can assert that a
    /// different locale actually produces different text — a hardcoded English
    /// string would pass a "localisation" test while localising nothing.
    static func durationText(
        _ offer: IntroductoryOffer,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let total = offer.value * max(offer.periodCount, 1)

        var components = DateComponents()
        switch offer.unit {
        case .day:   components.day = total
        case .week:  components.weekOfMonth = total
        case .month:
            // Twelve months is the offer Samuel is making, and "1 year" is how it
            // was described. Normalised here rather than left as "12 months".
            if total == 12 { components.year = 1 } else { components.month = total }
        case .year:  components.year = total
        }

        // `DateComponentsFormatter`, not `Date.ComponentsFormatStyle`: the latter
        // formats a Range<Date>, and we have a count of units with no dates.
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.year, .month, .weekOfMonth, .day]
        formatter.maximumUnitCount = 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar

        // A formatter that produced nothing must not leave the member reading
        // "Free for ". Falling back to the raw count is ugly and honest.
        guard let formatted = formatter.string(from: components), !formatted.isEmpty else {
            return "\(total)"
        }
        return formatted
    }

    /// Never softened, and never shown without a free period alongside it.
    static let renewalNotice =
        "Your subscription renews automatically at the end of the free period unless you cancel."

    /// Apple, not Études, is where a subscription is managed.
    static let cancellationNotice =
        "Cancel any time in Settings › Apple Account › Subscriptions."

    // MARK: - StoreKit adapter

    /// Extracts the values above from a product. No decisions here.
    static func introductoryOffer(from product: Product) -> IntroductoryOffer? {
        guard let offer = product.subscription?.introductoryOffer else { return nil }
        let unit: IntroductoryOffer.Unit
        switch offer.period.unit {
        case .day:   unit = .day
        case .week:  unit = .week
        case .month: unit = .month
        case .year:  unit = .year
        @unknown default:
            // An unrecognised unit cannot be described honestly, so no offer is
            // reported and ordinary pricing is shown.
            return nil
        }
        return IntroductoryOffer(
            unit: unit,
            value: offer.period.value,
            periodCount: offer.periodCount,
            isFreeTrial: offer.paymentMode == .freeTrial
        )
    }

    static func copy(for product: Product, isEligible: Bool, cadence: String) -> OfferCopy {
        copy(
            isEligible: isEligible,
            offer: introductoryOffer(from: product),
            displayPrice: product.displayPrice,
            cadence: cadence
        )
    }
}
