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
    @Environment(\.colorScheme) private var colorScheme

    let onAuthenticationRequired: () -> Void

    @State private var selectedProductID: String?
    @State private var notice: MembershipNotice?

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
                    onAuthenticationRequired()
                }
            }
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

    private func purchaseSelectedProduct() {
        guard let selectedProduct else { return }

        Task {
            let outcome = await membershipStore.purchase(selectedProduct)

            switch outcome {
            case .verified:
                await MainActor.run {
                    onAuthenticationRequired()
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
                await MainActor.run {
                    onAuthenticationRequired()
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

private struct MembershipNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
