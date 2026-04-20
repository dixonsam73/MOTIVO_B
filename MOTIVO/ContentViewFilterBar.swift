// CHANGE-ID: 20260420_165900_ContentView_FilterBarExtractionSafetyPass1_7f2a
// SCOPE: Extracted filter-card rendering cluster from ContentView with no behavior, spacing, navigation, or visual changes. Contains only FilterBar, FilterCardRow, FilterCardDivider, FilterCardSearchField, FilterSelectorValueControl, FilterSelectorTrailingControlStyle, and FilterCardUI.
// SEARCH-TOKEN: 20260420_165900_ContentView_FilterBarExtractionSafetyPass1_7f2a

import SwiftUI

// MARK: - Filter bar (unchanged logic, wrapped by a card above)


struct FilterSelectorValueControl: View {
    let valueText: String

    var body: some View {
        HStack(spacing: 5) {
            Text(valueText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.primary.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .animation(nil, value: valueText)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.regular))
                .imageScale(.small)
                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.42))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 3)
    }
}

struct FilterSelectorTrailingControlStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.66))
            .tint(Theme.Colors.secondaryText.opacity(0.66))
            .controlSize(.small)
            .scaleEffect(1.0, anchor: .trailing)
    }
}



enum FilterCardUI {
    static let rowMinHeight: CGFloat = 33
    static let rowVerticalPadding: CGFloat = 2
    static let trailingControlWidth: CGFloat = 160
    static let searchCornerRadius: CGFloat = 12
}

struct FilterCardDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(Theme.Colors.cardStroke(colorScheme).opacity(colorScheme == .dark ? 0.09 : 0.05))
            .frame(height: 1)
    }
}

struct FilterCardRow<Trailing: View>: View {
    let label: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))

            Spacer(minLength: Theme.Spacing.s)

            trailing()
                .frame(width: FilterCardUI.trailingControlWidth, alignment: .trailing)
                .padding(.trailing, 3)
        }
        .frame(minHeight: FilterCardUI.rowMinHeight)
        .padding(.horizontal, Theme.Spacing.card)
        .padding(.vertical, FilterCardUI.rowVerticalPadding)
    }
}

struct FilterCardSearchField: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))

            TextField(
                "Search",
                text: $text,
                prompt: Text("Search")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(colorScheme == .dark ? 0.92 : 0.86))
            )
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .font(.footnote)
            .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: FilterCardUI.searchCornerRadius, style: .continuous)
                .fill(
                    colorScheme == .dark
                    ? Theme.Colors.surface(colorScheme).opacity(0.94)
                    : Color.primary.opacity(0.035)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: FilterCardUI.searchCornerRadius, style: .continuous)
                .stroke(
                    colorScheme == .dark
                    ? Theme.Colors.cardStroke(colorScheme).opacity(0.18)
                    : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
struct FilterBar: View {
    @Binding var filtersExpanded: Bool
    let instruments: [Instrument]
    let customNames: [String]
    @Binding var selectedInstrument: Instrument?
    @Binding var selectedActivity: ActivityFilter
    @Binding var searchText: String
    @Binding var savedOnly: Bool
    @Binding var selectedThread: String?
    @Binding var selectedEnsembleID: String?
    let threadOptions: [String]
    let ensembles: [Ensemble]

    @State private var showThreadPicker: Bool = false

    private var sortedEnsembles: [Ensemble] {
        ensembles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedEnsembleName: String {
        guard let selectedEnsembleID,
              let ensemble = sortedEnsembles.first(where: { $0.id == selectedEnsembleID }) else {
            return "Any"
        }
        return ensemble.name
    }

    private var selectedInstrumentLabel: String {
        if let inst = selectedInstrument {
            let name = (inst.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "(Unnamed)" : name
        } else {
            return "Any"
        }
    }

    var body: some View {
        if filtersExpanded {
            VStack(alignment: .leading, spacing: 0) {
                FilterCardDivider()
                    .padding(.horizontal, Theme.Spacing.card)

                HStack(spacing: 0) {
                    FilterCardSearchField(text: $searchText)
                }
                .frame(minHeight: FilterCardUI.rowMinHeight)
                .padding(.horizontal, Theme.Spacing.card)
                .padding(.vertical, FilterCardUI.rowVerticalPadding)

                FilterCardRow(label: "Instrument") {
                    Menu {
                        Button("Any") {
                            #if canImport(UIKit)
                            ContentViewKeyboardDismiss.dismiss()
                            #endif
                            selectedInstrument = nil
                        }
                        ForEach(instruments, id: \.objectID) { inst in
                            Button(((inst.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? "(Unnamed)" : (inst.name ?? "")) {
                                #if canImport(UIKit)
                                ContentViewKeyboardDismiss.dismiss()
                                #endif
                                selectedInstrument = inst
                            }
                        }
                    } label: {
                        FilterSelectorValueControl(valueText: selectedInstrumentLabel)
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            #if canImport(UIKit)
                            ContentViewKeyboardDismiss.dismiss()
                            #endif
                        }
                    )
                    .modifier(FilterSelectorTrailingControlStyle())
                }

                FilterCardDivider()
                    .padding(.horizontal, Theme.Spacing.card)

                FilterCardRow(label: "Activity") {
                    Menu {
                        Button("Any") {
                            #if canImport(UIKit)
                            ContentViewKeyboardDismiss.dismiss()
                            #endif
                            selectedActivity = .any
                        }
                        ForEach(ActivityType.allCases) { a in
                            Button(a.label) {
                                #if canImport(UIKit)
                                ContentViewKeyboardDismiss.dismiss()
                                #endif
                                selectedActivity = .core(a)
                            }
                        }
                        if !customNames.isEmpty {
                            ForEach(customNames, id: \.self) { name in
                                Button(name) {
                                    #if canImport(UIKit)
                                    ContentViewKeyboardDismiss.dismiss()
                                    #endif
                                    selectedActivity = .custom(name)
                                }
                            }
                        }
                    } label: {
                        FilterSelectorValueControl(valueText: selectedActivity.label)
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            #if canImport(UIKit)
                            ContentViewKeyboardDismiss.dismiss()
                            #endif
                        }
                    )
                    .modifier(FilterSelectorTrailingControlStyle())
                }

                FilterCardDivider()
                    .padding(.horizontal, Theme.Spacing.card)

                FilterCardRow(label: "Thread") {
                    Button {
                        #if canImport(UIKit)
                        ContentViewKeyboardDismiss.dismiss()
                        #endif
                        showThreadPicker = true
                    } label: {
                        FilterSelectorValueControl(valueText: selectedThread ?? "Any")
                    }
                    .buttonStyle(.plain)
                    .modifier(FilterSelectorTrailingControlStyle())
                    .contentShape(Rectangle())
                }

                FilterCardDivider()
                    .padding(.horizontal, Theme.Spacing.card)

                FilterCardRow(label: "Ensemble") {
                    Menu {
                        Button("Any") {
                            #if canImport(UIKit)
                            ContentViewKeyboardDismiss.dismiss()
                            #endif
                            selectedEnsembleID = nil
                        }
                        ForEach(sortedEnsembles) { ensemble in
                            Button(ensemble.name) {
                                #if canImport(UIKit)
                                ContentViewKeyboardDismiss.dismiss()
                                #endif
                                selectedEnsembleID = ensemble.id
                            }
                        }
                    } label: {
                        FilterSelectorValueControl(valueText: selectedEnsembleName)
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            #if canImport(UIKit)
                            ContentViewKeyboardDismiss.dismiss()
                            #endif
                        }
                    )
                    .modifier(FilterSelectorTrailingControlStyle())
                }

                FilterCardDivider()
                    .padding(.horizontal, Theme.Spacing.card)

                FilterCardRow(label: "Saved only") {
                    Toggle("", isOn: $savedOnly)
                        .labelsHidden()
                        .tint(Theme.Colors.accent.opacity(0.72))
                        .controlSize(.small)
                        .scaleEffect(1.0, anchor: .trailing)
                        .onChange(of: savedOnly) { _ in
                            #if canImport(UIKit)
                            ContentViewKeyboardDismiss.dismiss()
                            #endif
                        }
                }
            }
            .padding(.top, 1)
            .padding(.bottom, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                #if canImport(UIKit)
                ContentViewKeyboardDismiss.dismiss()
                #endif
            }
            .sheet(isPresented: $showThreadPicker) {
                ThreadPickerView(
                    selectedThread: $selectedThread,
                    title: "Thread",
                    recentThreads: threadOptions,
                    maxLength: 32
                )
            }
        }
    }
}
