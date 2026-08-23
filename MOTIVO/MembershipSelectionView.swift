//
//  MembershipSelectionView.swift
//  MOTIVO
//
//  M9B: User-facing Études Connected membership selection and StoreKit actions.
//

import SwiftUI
import StoreKit

struct MembershipSelectionView: View {
    @EnvironmentObject private var membershipStore: ConnectedMembershipStore
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var attestation: MembershipAttestationCoordinator
    @Environment(\.colorScheme) private var colorScheme

    let onAuthenticationRequired: () -> Void
    let onJoinComplete: () -> Void

    @State private var selectedProductID: String?
    @State private var notice: MembershipNotice?

    /// Fetched when this screen appears, so the purchase can carry it. **Never
    /// generated here** — it is the server's to issue (B-24), and a client-minted
    /// value would be a token nobody recorded.
    @State private var bindingToken: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                membershipOptions
                actionSection
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.xxl)
            .padding(.bottom, Theme.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Études Connected")
                    .font(Theme.Text.pageTitle)
                    .foregroundStyle(.primary)
            }
        }
        .onAppear {
            selectDefaultProductIfNeeded()

            if membershipStore.isEntitled {
                DispatchQueue.main.async {
                    onJoinComplete()
                }
                return
            }

            // Fetch the binding token now, so it is in hand before the member
            // taps Subscribe. Doing it here rather than inside the purchase
            // keeps a network round trip off the purchase path -- C-13's hazard
            // is exactly a purchase that stalls behind something else.
            Task { await loadBindingToken() }
        }
        .onChange(of: membershipStore.products.map(\.id)) { _, _ in
            selectDefaultProductIfNeeded()
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var membershipOptions: some View {
        if let monthlyProduct = membershipStore.monthlyProduct,
           let annualProduct = membershipStore.annualProduct {
            VStack(spacing: Theme.Spacing.l) {
                membershipOption(
                    product: monthlyProduct,
                    cadence: "per month"
                )

                membershipOption(
                    product: annualProduct,
                    cadence: "per year"
                )
            }
        } else if membershipStore.isLoadingProducts {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(minHeight: 180)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Membership options are unavailable.")
                    .font(Theme.Text.body.weight(.semibold))
                    .foregroundStyle(.primary)

                if let error = membershipStore.productLoadError {
                    Text(error.localizedDescription)
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.card)
            .background(Color(.systemBackground))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Theme.Radius.card,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: Theme.Radius.card,
                    style: .continuous
                )
                .stroke(
                    Theme.Colors.stroke(colorScheme).opacity(0.72),
                    lineWidth: 1
                )
            }
        }
    }

    private func membershipOption(
        product: Product,
        cadence: String
    ) -> some View {
        let isSelected = selectedProductID == product.id

        return Button {
            selectedProductID = product.id
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                    Text(product.displayName)
                        .font(Theme.Text.pageTitle)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(
                            isSelected
                            ? Theme.Colors.primaryAction
                            : Theme.Colors.secondaryText
                        )
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(product.displayPrice)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(cadence)
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.card)
            .background(Color(.systemBackground))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Theme.Radius.card,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: Theme.Radius.card,
                    style: .continuous
                )
                .stroke(
                    isSelected
                    ? Theme.Colors.primaryAction.opacity(0.72)
                    : Theme.Colors.stroke(colorScheme).opacity(0.72),
                    lineWidth: isSelected ? 1.5 : 1
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var actionSection: some View {
        VStack(spacing: Theme.Spacing.l) {
            Button {
                purchaseSelectedProduct()
            } label: {
                Group {
                    if membershipStore.isPurchasing {
                        ProgressView()
                            .tint(Theme.Colors.primaryAction)
                    } else {
                        Text("Continue")
                    }
                }
                .font(Theme.Text.body.weight(.semibold))
                .foregroundStyle(Theme.Colors.primaryAction.opacity(0.92))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(
                        cornerRadius: Theme.Radius.control,
                        style: .continuous
                    )
                    .fill(Theme.Colors.primaryAction.opacity(0.18))
                )
            }
            .buttonStyle(.plain)
            .disabled(
                selectedProduct == nil
                || membershipStore.isPurchasing
                || membershipStore.isRestoringPurchases
            )
            .opacity(selectedProduct == nil ? 0.55 : 1)

            Button {
                restorePurchases()
            } label: {
                Group {
                    if membershipStore.isRestoringPurchases {
                        ProgressView()
                    } else {
                        Text("Restore Purchases")
                    }
                }
                .font(Theme.Text.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(
                membershipStore.isPurchasing
                || membershipStore.isRestoringPurchases
            )
        }
    }

    private var selectedProduct: Product? {
        guard let selectedProductID else { return nil }

        if membershipStore.monthlyProduct?.id == selectedProductID {
            return membershipStore.monthlyProduct
        }

        if membershipStore.annualProduct?.id == selectedProductID {
            return membershipStore.annualProduct
        }

        return nil
    }

    private func selectDefaultProductIfNeeded() {
        guard selectedProduct == nil else { return }

        selectedProductID = membershipStore.monthlyProduct?.id
            ?? membershipStore.annualProduct?.id
    }

    /// Obtains this identity's server-issued binding token.
    ///
    /// A failure here is deliberately NOT surfaced and NOT blocking. The purchase
    /// proceeds without a token and the server's legacy-claim path binds the
    /// subscription on a later attestation -- so a transient network problem
    /// costs a slightly longer route to the same state, not a lost sale and not
    /// an error the member can do anything about.
    private func loadBindingToken() async {
        guard auth.hasConnectedIdentity else { return }
        if case .success(let token) = await MembershipBindingService.ensureBindingToken(
            auth: auth, reason: "membershipSelection"
        ) {
            bindingToken = token
        }
    }

    private func purchaseSelectedProduct() {
        guard let selectedProduct else { return }

        Task {
            // Last chance to bind at source: if the token was not in hand yet,
            // try once more before falling back to the legacy path.
            if bindingToken == nil { await loadBindingToken() }

            let outcome = await membershipStore.purchase(
                selectedProduct,
                appAccountToken: bindingToken
            )

            switch outcome {
            case .verified:
                // F10. THE PURCHASE SUCCEEDED. Attestation tells the SERVER about
                // it, and whatever the server says, the purchase is not undone
                // and must never be reported as having failed.
                await attestation.attestIfNeeded(
                    auth: auth,
                    isLocallyEntitled: membershipStore.isEntitled,
                    reason: "purchase",
                    force: true
                )
                if let pending = Self.postPurchaseNotice(for: attestation.lastOutcome) {
                    notice = pending
                }
                await MainActor.run {
                    onJoinComplete()
                }

            case .unverified:
                notice = MembershipNotice(
                    title: "Purchase unavailable",
                    message: "The purchase could not be verified."
                )

            case .pending:
                notice = MembershipNotice(
                    title: "Purchase pending",
                    message: "Your purchase is pending. Études will update when it is approved."
                )

            case .userCancelled:
                break

            case .failed(let error):
                notice = MembershipNotice(
                    title: "Purchase unavailable",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func restorePurchases() {
        Task {
            await membershipStore.restorePurchases()

            if let error = membershipStore.restoreError {
                notice = MembershipNotice(
                    title: "Restore unavailable",
                    message: error.localizedDescription
                )
            } else if membershipStore.isEntitled {
                // A restore is user-initiated, so it forces attestation past the
                // cooldown: this is exactly the returning member the server may
                // not know about yet.
                await attestation.attestIfNeeded(
                    auth: auth,
                    isLocallyEntitled: true,
                    reason: "restorePurchases",
                    force: true
                )
                await MainActor.run {
                    onJoinComplete()
                }
            } else {
                notice = MembershipNotice(
                    title: "No membership found",
                    message: "No active Études Connected membership was found."
                )
            }
        }
    }
}

extension MembershipSelectionView {
    /// F10 — WHAT THE MEMBER IS TOLD AFTER A **SUCCESSFUL** PURCHASE.
    ///
    /// Pure and static so the mapping is unit-testable without StoreKit, a
    /// network or a view.
    ///
    /// **`nil` MEANS SAY NOTHING, AND IT IS THE COMMON CASE.** The purchase
    /// worked and membership was established; interrupting that with an alert
    /// would be noise. Only two situations earn a word, and neither is phrased
    /// as a failure:
    ///
    ///   - **pending** — Apple accepted the binding and has not surfaced it yet.
    ///     This finishes by itself on a later attestation, which runs on every
    ///     foreground. **It is propagation, not an error**, so it gets a calm
    ///     sentence and no action to take. Inventing destructive or alarming
    ///     semantics for a delay is exactly what this row exists to prevent.
    ///   - **conflict / terminal refusal** — the subscription is bound to a
    ///     different Etudes account, or Apple will never bind it. The member
    ///     cannot fix this alone and must not be told to try again.
    ///
    /// Everything else -- transport failures, Apple briefly unavailable -- is
    /// silent: the next foreground retries, and the member has nothing to do.
    static func postPurchaseNotice(
        for outcome: MembershipAttestationService.Outcome?
    ) -> MembershipNotice? {
        switch outcome {
        case .pending:
            return MembershipNotice(
                title: "Finishing setup",
                message: "Your membership is being confirmed. This completes on its own — no action needed."
            )
        case .conflict:
            return MembershipNotice(
                title: "Membership already in use",
                message: "This subscription is already linked to a different Études account. Your purchase is safe. Please contact support so we can sort it out."
            )
        case .terminalRefusal, .claimRefused(_, terminal: true):
            return MembershipNotice(
                title: "We couldn't link this subscription",
                message: "Your purchase is safe. Please contact support so we can link it to your Études account."
            )
        default:
            // Includes established, alreadyEstablished, appleUnavailable,
            // transport, ineligible and nil. Nothing to say and nothing to do.
            return nil
        }
    }
}

struct MembershipNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
