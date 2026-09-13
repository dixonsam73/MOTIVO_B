import SwiftUI

struct MetronomeControlStripCard: View {
    @Binding var metronomeIsOn: Bool
    @Binding var settings: MetronomeSettings
    @ObservedObject var metronomeEngine: MetronomeEngine
    let recorderIcon: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showMetronomeVolumePopover = false
    @State private var metronomeSwingRight = false
    @State private var beatListenerToken: UUID?
    @State private var tapTempo = MetronomeTapTempo()
    @State private var beatFlash: Color?
    @State private var showBeatGrouping = false
    @State private var showGroupingHint = false
    @AppStorage("metronomeGroupingPatterns_v1") private var storedGroupings = Data()
    @AppStorage("metronome_hasSeenGroupingHint_v1") private var hasSeenGroupingHint = false
    @ScaledMetric(relativeTo: .body) private var wheelHeight: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var tempoWidth: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var controlMinWidth: CGFloat = 64

    var body: some View {
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { transport; tap; tempo; volume }
                VStack(spacing: 8) {
                    HStack(spacing: 12) { transport; tap }
                    HStack(spacing: 12) { tempo; volume }
                }
            }
            .frame(maxWidth: .infinity)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { meter; downbeat; subdivision }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { meter; downbeat; subdivision }
                    VStack(spacing: 8) { meter; downbeat; subdivision }
                }
            }

            if case .unavailable(let failure) = metronomeEngine.availability {
                VStack(spacing: 6) {
                    Text("Metronome unavailable").font(.headline)
                    Text(failure.explanation).font(.caption).foregroundStyle(.secondary)
                    Button("Try again") { start() }.buttonStyle(.bordered)
                }.frame(maxWidth: .infinity)
            }
        }
        .tint(Theme.Colors.accent)
        .onAppear {
            settings.restoreGroupings(from: storedGroupings)
            metronomeIsOn = metronomeEngine.isRunning
            if let beatListenerToken { metronomeEngine.removeBeatListener(beatListenerToken) }
            beatListenerToken = metronomeEngine.addBeatListener { isDownbeat in
                let duration = 60 / Double(max(20, settings.bpm))
                withAnimation(.spring(response: max(0.12, min(duration * 0.55, 0.35)), dampingFraction: 0.72, blendDuration: 0.1)) {
                    metronomeSwingRight.toggle()
                }
                flashBeat(isDownbeat: isDownbeat, duration: duration)
            }
        }
        .onDisappear {
            if let beatListenerToken { metronomeEngine.removeBeatListener(beatListenerToken) }
            beatListenerToken = nil
            clearBeatFlash()
        }
        .onChange(of: settings.rememberedGroupings) { _, _ in storedGroupings = settings.encodedGroupings() }
        .onChange(of: settings.meter) { _, _ in showBeatGrouping = false }
        .task(id: settings.meter) {
            showGroupingHint = false
            guard settings.meter.supportsGrouping, !hasSeenGroupingHint else { return }
            hasSeenGroupingHint = true
            withAnimation(.easeInOut(duration: 0.15)) { showGroupingHint = true }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            withAnimation(.easeOut(duration: 0.3)) { showGroupingHint = false }
        }
        .onChange(of: settings.meter.beatUnit) { _, _ in tapTempo.reset() }
        .onChange(of: settings.accent) { _, _ in clearBeatFlash() }
        .onChange(of: metronomeEngine.availability) { _, value in
            if value != .running { clearBeatFlash() }
        }
        .onChange(of: reduceMotion) { _, _ in clearBeatFlash() }
    }

    private var transport: some View {
        Button {
            if metronomeEngine.isRunning { metronomeEngine.stop(); metronomeIsOn = false }
            else { start() }
        } label: {
            MetronomeIcon(isOn: metronomeIsOn, swingRight: metronomeSwingRight,
                          color: metronomeIsOn ? Theme.Colors.primaryAction : recorderIcon, animateArm: true)
                .frame(minWidth: controlMinWidth, maxWidth: .infinity)
                .frame(height: wheelHeight)
                .background(metronomeIsOn ? Theme.Colors.primaryAction.opacity(0.18) : recorderIcon.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(metronomeIsOn ? "Stop metronome" : "Start metronome")
    }

    private var tap: some View {
        Button {
            if let value = tapTempo.tap(at: ProcessInfo.processInfo.systemUptime) { settings.bpm = value }
        } label: {
            Text("Tap").font(Theme.Text.body).foregroundStyle(recorderIcon)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .frame(minWidth: controlMinWidth, maxWidth: .infinity)
                .frame(height: wheelHeight)
                .background(recorderIcon.opacity(0.12), in: Capsule())
        }.buttonStyle(.plain).accessibilityLabel("Tap tempo")
    }

    private var tempo: some View {
        HStack(spacing: 2) {
            MetronomeRhythmGlyph(beatUnit: settings.meter.beatUnit)
            Text("=").font(.title3).accessibilityHidden(true)
            Picker("Tempo", selection: $settings.bpm) {
                ForEach(20...400, id: \.self) { value in
                    Text("\(value)").font(Theme.Text.body).monospacedDigit().tag(value)
                }
            }
            .labelsHidden().pickerStyle(.wheel)
            .frame(width: tempoWidth, height: wheelHeight).clipped()
            .accessibilityLabel("Tempo in \(settings.meter.beatLabel.lowercased()) beats per minute")
        }
        .foregroundStyle(recorderIcon)
        .padding(.horizontal, 8)
        .fixedSize(horizontal: true, vertical: false)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var volume: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { showMetronomeVolumePopover.toggle() }
        } label: {
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(recorderIcon)
                .frame(minWidth: controlMinWidth, maxWidth: .infinity)
                .frame(height: wheelHeight)
                .background(recorderIcon.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Metronome volume")
        .accessibilityValue("\(Int(settings.volume * 100)) percent")
        .overlay(alignment: .top) {
            if showMetronomeVolumePopover {
                MetronomeVolumePopover(value: $settings.volume, onChanged: { _ in }, onEditingEnded: {
                    withAnimation(.easeInOut(duration: 0.18)) { showMetronomeVolumePopover = false }
                })
                .offset(y: -24)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)),
                                       removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .bottom))))
                .zIndex(1)
            }
        }.zIndex(2)
    }

    private var meter: some View {
        MetronomeNotationWheel(values: MetronomeMeter.standard,
                                selection: Binding(get: { settings.meter }, set: { settings.selectMeter($0) }),
                                label: "Time signature", valueLabel: { $0.label },
                                height: wheelHeight, contentID: dynamicTypeSize) { value in
            MetronomeMeterGlyph(meter: value)
                .foregroundStyle(recorderIcon).environment(\.dynamicTypeSize, dynamicTypeSize)
        }
        .frame(minWidth: 64, idealWidth: 80, maxWidth: .infinity)
        .frame(height: wheelHeight).clipped()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var downbeat: some View {
        MetronomeDownbeatControl(accent: settings.accent, grouping: settings.grouping,
            supportsGrouping: settings.meter.supportsGrouping, height: wheelHeight,
            recorderIcon: recorderIcon,
            fill: beatFlash ?? (settings.accent && !metronomeEngine.isRunning ? Color.orange.opacity(0.12) : .clear),
            onToggle: { settings.accent.toggle() }, onGrouping: {
                hasSeenGroupingHint = true
                showGroupingHint = false
                showBeatGrouping = true
            })
        .popover(isPresented: $showBeatGrouping, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            MetronomeGroupingPopover(meter: settings.meter, selected: settings.grouping, recorderIcon: recorderIcon) { value in
                settings.selectGrouping(value)
                showBeatGrouping = false
            }
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .presentationCompactAdaptation(.popover)
        }
        .overlay(alignment: .top) {
            if showGroupingHint {
                Text("Touch and hold\nfor beat grouping")
                    .font(.caption).multilineTextAlignment(.center)
                    .foregroundStyle(recorderIcon)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .fixedSize().offset(y: -60)
                    .allowsHitTesting(false).transition(.opacity)
            }
        }
        .zIndex(showGroupingHint ? 3 : 0)
    }

    private var subdivision: some View {
        MetronomeNotationWheel(values: MetronomeSubdivision.choices(in: settings.meter),
                                selection: $settings.subdivision, label: "Subdivision",
                                valueLabel: { $0.label(in: settings.meter) }, height: wheelHeight,
                                contentID: "\(settings.meter.code)-\(dynamicTypeSize)") { value in
            MetronomeRhythmGlyph(subdivision: value, meter: settings.meter)
                .foregroundStyle(recorderIcon).environment(\.dynamicTypeSize, dynamicTypeSize)
        }
        .frame(minWidth: 80, idealWidth: 88, maxWidth: .infinity)
        .frame(height: wheelHeight).clipped()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func flashBeat(isDownbeat: Bool, duration: Double) {
        guard metronomeEngine.isRunning, !reduceMotion else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            beatFlash = isDownbeat && settings.accent
                ? Color.orange.opacity(0.24)
                : Theme.Colors.primaryAction.opacity(0.14)
        }
        withAnimation(.easeOut(duration: min(0.24, duration * 0.65))) { beatFlash = nil }
    }

    private func clearBeatFlash() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { beatFlash = nil }
    }

    private func start() { metronomeIsOn = metronomeEngine.start(settings: settings) }
}

struct MetronomeCompactTrigger: View {
    @Binding var metronomeIsOn: Bool
    @Binding var settings: MetronomeSettings
    @ObservedObject var metronomeEngine: MetronomeEngine
    let recorderIcon: Color
    let shouldAnimateCompactIcon: Bool
    var onTapHintRequest: (() -> Void)? = nil
    var onLongPressDiscovered: (() -> Void)? = nil
    var onRevealControls: (() -> Void)? = nil
    @State private var metronomeSwingRight = false
    @State private var suppressNextTap = false
    @State private var beatListenerToken: UUID?

    var body: some View {
        Button(action: handleTap) {
            MetronomeIcon(isOn: metronomeIsOn, swingRight: metronomeSwingRight,
                          color: metronomeIsOn ? Theme.Colors.primaryAction : recorderIcon,
                          animateArm: shouldAnimateCompactIcon)
                .frame(width: 24, height: 24).frame(width: 48, height: 48).contentShape(Circle())
        }
        .buttonStyle(.bordered)
        .background(Capsule(style: .continuous)
            .fill(metronomeIsOn ? Theme.Colors.primaryAction.opacity(0.18) : Color.clear))
        .clipShape(Capsule(style: .continuous))
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            suppressNextTap = true
            onLongPressDiscovered?()
            onRevealControls?()
        })
        .accessibilityLabel(metronomeIsOn ? "Stop metronome" : "Start metronome")
        .accessibilityHint("Tap to toggle the metronome. Long press to show controls.")
        .onAppear { metronomeIsOn = metronomeEngine.isRunning; updateCompactBeatHandler() }
        .onChange(of: shouldAnimateCompactIcon) { updateCompactBeatHandler() }
        .onChange(of: metronomeIsOn) { updateCompactBeatHandler() }
        .onDisappear { unregisterBeatListener(resetSwing: true) }
    }
    private func handleTap() {
        if suppressNextTap { suppressNextTap = false; return }
        onTapHintRequest?()
        if metronomeEngine.isRunning { metronomeEngine.stop(); metronomeIsOn = false }
        else { metronomeIsOn = metronomeEngine.start(settings: settings) }
        updateCompactBeatHandler()
    }
    private func updateCompactBeatHandler() {
        metronomeIsOn = metronomeEngine.isRunning
        unregisterBeatListener(resetSwing: !shouldAnimateCompactIcon || !metronomeIsOn)
        guard shouldAnimateCompactIcon, metronomeIsOn else { return }
        beatListenerToken = metronomeEngine.addBeatListener { _ in
            let duration = 60 / Double(max(20, settings.bpm))
            withAnimation(.spring(response: max(0.12, min(duration * 0.55, 0.35)), dampingFraction: 0.72, blendDuration: 0.1)) {
                metronomeSwingRight.toggle()
            }
        }
    }
    private func unregisterBeatListener(resetSwing: Bool) {
        if let beatListenerToken { metronomeEngine.removeBeatListener(beatListenerToken) }
        beatListenerToken = nil
        if resetSwing { withAnimation(.easeOut(duration: 0.12)) { metronomeSwingRight = false } }
    }
}

// MARK: - Custom Metronome Icon (Outlined Body + Swinging Arm)

private struct MetronomeIcon: View {
    let isOn: Bool
    let swingRight: Bool
    let color: Color
    let animateArm: Bool

    var body: some View {
        ZStack {
            // Body: trapezoid with a small flat top (reads like a classic wooden metronome)
            Path { path in
                // Top edge (short, centered)
                path.move(to: CGPoint(x: 9, y: 3))    // top-left
                path.addLine(to: CGPoint(x: 15, y: 3)) // top-right

                // Down to base
                path.addLine(to: CGPoint(x: 18, y: 19)) // bottom-right
                path.addLine(to: CGPoint(x: 6, y: 19))  // bottom-left

                // Close back to top-left
                path.closeSubpath()
            }
            .stroke(color, lineWidth: 1.6)

            // Base
            Capsule(style: .continuous)
                .frame(width: 16, height: 3)
                .offset(y: 9)
                .foregroundStyle(color.opacity(0.9))

            // Arm (only thing that moves)
            Rectangle()
                .frame(width: 1.5, height: 14)
                .offset(y: 3)
                .rotationEffect(
                    .degrees(isOn && animateArm ? (swingRight ? 16 : -16) : 0),
                    anchor: .bottom
                )
                .foregroundStyle(color)
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Volume popover

private struct MetronomeVolumePopover: View {
    @Binding var value: Double
    let onChanged: (Double) -> Void
    let onEditingEnded: () -> Void

    var body: some View {
        ZStack {
            // Vertical rail + endpoints
            VStack {
                Circle()
                    .fill(Theme.Colors.secondaryText.opacity(0.4))
                    .frame(width: 4, height: 4)

                Spacer(minLength: 0)

                Capsule()
                    .fill(Theme.Colors.secondaryText.opacity(0.25))
                    .frame(width: 3, height: 72)

                Spacer(minLength: 0)

                Circle()
                    .fill(Theme.Colors.secondaryText.opacity(0.4))
                    .frame(width: 4, height: 4)
            }
            .frame(width: 18, height: 88)

            // Interactive slider rotated vertically
            Slider(
                value: $value,
                in: 0...1,
                step: 0.01,
                onEditingChanged: { editing in
                    if !editing {
                        onEditingEnded()
                    }
                }
            )
            .tint(Theme.Colors.accent)
            .rotationEffect(.degrees(-90))
            .frame(width: 88, height: 32)
            .onChange(of: value) { _, newVal in
                // Clamp + notify
                let clamped = max(0.0, min(1.0, newVal))
                if clamped != value {
                    value = clamped
                }
                onChanged(clamped)
            }
            .contentShape(Rectangle())
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .shadow(radius: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Metronome volume")
        .accessibilityHint("Swipe up or down to adjust the metronome volume.")
    }
}

// A single exclusive gesture prevents a long press from also toggling the downbeat.
struct MetronomeDownbeatControl: View {
    let accent: Bool
    let grouping: MetronomeGrouping
    let supportsGrouping: Bool
    let height: CGFloat
    let recorderIcon: Color
    let fill: Color
    var onToggle: () -> Void
    var onGrouping: () -> Void

    var body: some View {
        VStack(spacing: 1) {
            Text("Downbeat").font(Theme.Text.body).fixedSize()
            if grouping != .even {
                Text(grouping.label).font(.caption2).monospacedDigit().fixedSize()
            }
        }
        .foregroundStyle(recorderIcon).padding(.horizontal, 8)
        .frame(maxWidth: .infinity).frame(height: height)
        .background {
            RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                .overlay { RoundedRectangle(cornerRadius: 16).fill(fill) }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .gesture(LongPressGesture(minimumDuration: 0.45)
            .exclusively(before: TapGesture()).onEnded { value in
                switch value {
                case .first(true): if supportsGrouping { onGrouping() }
                case .second: onToggle()
                default: break
                }
            })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Accent downbeat")
        .accessibilityValue((accent ? "On" : "Off") + (grouping == .even ? "" : ", grouping " + grouping.accessibilityLabel))
        .accessibilityAddTraits(accent ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction { onToggle() }
        .accessibilityHint(supportsGrouping ? "Touch and hold for beat grouping" : "")
        .accessibilityActions {
            if supportsGrouping { Button("Beat grouping", action: onGrouping) }
        }
    }
}

struct MetronomeGroupingPopover: View {
    let meter: MetronomeMeter
    let selected: MetronomeGrouping
    let recorderIcon: Color
    var onSelect: (MetronomeGrouping) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 44

    private var columnCount: Int { dynamicTypeSize.isAccessibilitySize ? 1 : 2 }
    private var listHeight: CGFloat {
        let rows = (meter.groupingChoices.count + columnCount - 1) / columnCount
        return min(300, CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * 8)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Beat grouping").font(.headline).foregroundStyle(recorderIcon)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount), spacing: 8) {
                    ForEach(meter.groupingChoices, id: \.self) { grouping in
                        Button { onSelect(grouping) } label: {
                            Text(grouping.label).font(Theme.Text.body).monospacedDigit()
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(maxWidth: .infinity).frame(minHeight: rowHeight)
                                .background(recorderIcon.opacity(grouping == selected ? 0.22 : 0.07), in: Capsule())
                        }
                        .buttonStyle(.plain).foregroundStyle(recorderIcon)
                        .accessibilityLabel(grouping.accessibilityLabel)
                        .accessibilityAddTraits(grouping == selected ? .isSelected : [])
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: listHeight)
        }
        .padding(16).frame(idealWidth: 300, maxWidth: 340)
        .background(Theme.Colors.surface(colorScheme))
        .tint(Theme.Colors.accent)
    }
}
