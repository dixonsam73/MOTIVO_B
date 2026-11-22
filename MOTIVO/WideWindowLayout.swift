//
//  WideWindowLayout.swift
//  MOTIVO
//
//  How a page sits in a window that has room to spare: an iPad, or any
//  window that is both wide and tall. (RELEASE.md, section B: the iPad work
//  preserves the appearance, navigation and behaviour; it is spacing and
//  sizing, page by page.)
//
//  Everything here is decided by the SPACE, never by the kind of device,
//  and does nothing at all in a phone-sized space, portrait or landscape:
//  an iPhone on its side is wide but not tall, and is left exactly as it is.
//

import SwiftUI
import UIKit

enum WideWindow {

    /// The widest a page's column of content grows before it stays put and
    /// the margins grow instead. Chosen so a line of text and a card stay a
    /// comfortable width; an 11-inch iPad in portrait keeps a clear margin.
    static let columnWidth: CGFloat = 720

    /// Tall enough for a title, Cancel and Done, and a whole wheel picker.
    static let wheelSheetHeight: CGFloat = 380

    /// A window counts as roomy when its shorter side is at least this.
    /// An iPhone's shorter side is under 450 in either orientation.
    static let roomySide: CGFloat = 600

    /// PURE. Whether a space of this size has room to spare.
    static func isRoomy(_ size: CGSize) -> Bool {
        min(size.width, size.height) >= roomySide
    }

    /// Whether the app's window has room to spare right now.
    @MainActor
    static var isRoomy: Bool { isRoomy(WindowMetrics.windowBounds.size) }
}

/// The Timer page in a roomy window (an iPad's, either way up). An opened
/// section (the metronome or drone controls, the tuner, the audio recorder,
/// the list, the attachments) used to push the clock and the buttons down
/// the page; there it now sits beside the column of buttons instead, so the
/// buttons stay where they are.
enum TimerPageArrangement {

    /// The widest the Timer's column of buttons and cards grows in a roomy
    /// window, so a label stays near the button it belongs to.
    static let columnWidth: CGFloat = 560

    /// The widest an opened section grows in the side panel.
    static let panelWidth: CGFloat = 600

    /// Narrower than this there is no room for two parts side by side:
    /// each half must hold the row of three timer buttons, or a card about
    /// as wide as a phone's. An 11-inch iPad in portrait (834) has room; an
    /// iPad mini in portrait (744) does not, and keeps the single column.
    static let sideBySideMinimumWidth: CGFloat = 800

    /// PURE. Two parts side by side: a roomy window wide enough for both,
    /// portrait or landscape (Samuel, 2026-11-21: the same arrangement
    /// whichever way up, so turning the iPad moves nothing). Never a
    /// phone-sized space.
    static func isSideBySide(_ size: CGSize, roomy: Bool) -> Bool {
        roomy && size.width >= sideBySideMinimumWidth
    }

    /// PURE. The arrangement to show. While the audio recorder holds a take
    /// the page keeps the arrangement the take began in (`heldByRecorder`),
    /// whatever the window now fits: moving the recorder would end the take.
    /// Turning an 11-inch or larger iPad no longer changes what fits; this
    /// still matters when a window is made narrow, and on a smaller iPad.
    static func sideBySide(fits: Bool, heldByRecorder: Bool?) -> Bool {
        heldByRecorder ?? fits
    }

    /// PURE. The width the column of buttons keeps while the panel is open.
    /// Never more than half the window, so a held arrangement in a window
    /// that has since been made narrow still shows both parts.
    static func columnRegionWidth(window: CGFloat) -> CGFloat {
        min(max(440, (window * 0.42).rounded()), (window / 2).rounded())
    }

    /// The height the resting page needs: the buttons and the space above
    /// them. An 11-inch iPad in landscape is about this tall, and there the
    /// buttons already sit in the middle of the page.
    static let restingPageHeight: CGFloat = 840

    /// PURE. Extra space above the buttons in a roomy window taller than
    /// the resting page (an iPad in portrait): half the spare height, so
    /// the buttons sit in the middle of the page, not near its top.
    ///
    /// `windowHeight` is the height down to the window's bottom edge, NOT
    /// the height left above the keyboard: the buttons must not jump when
    /// the keyboard comes up, nor when a section is opened.
    static func centringInset(windowHeight: CGFloat) -> CGFloat {
        max(0, ((windowHeight - restingPageHeight) / 2).rounded())
    }

    /// PURE. Where the first opened section starts: level with the top of
    /// the column's first button, whichever way up (Samuel, 2026-11-21:
    /// starting the cards higher in portrait "feels weird"; level, as in
    /// landscape). `pageHeight` is the height the page is laid out in (it
    /// shrinks above the keyboard, as the column's own top space does);
    /// `windowHeight` is as for `centringInset`.
    static func panelTopInset(pageHeight: CGFloat, windowHeight: CGFloat) -> CGFloat {
        max(6, pageHeight * 0.024) + 95 + centringInset(windowHeight: windowHeight)
    }

    /// Where the list is shown.
    enum ListPlace: Equatable {
        /// In the single column, under its button (a phone, a narrow window).
        case column
        /// Beside the buttons, with the tools.
        case panel
        /// In its own area beneath both columns, centred on the page.
        case beneath
    }

    /// PURE. The tools (drone, metronome, tuner, audio recorder) go beside
    /// the buttons whichever way up. The list is different: it is the
    /// session's own page, not a tool (Samuel, 2026-11-21). In portrait
    /// there is room for it beneath the buttons, where it opens on a phone;
    /// it is centred beneath both columns, so a tool opening beside the
    /// buttons neither moves nor narrows it. In landscape there is no room
    /// beneath, and it goes beside with the rest.
    static func listPlace(sideBySide: Bool, landscape: Bool) -> ListPlace {
        guard sideBySide else { return .column }
        return landscape ? .panel : .beneath
    }

    /// The least height the list keeps beneath the columns, so a line being
    /// typed stays in view above the keyboard.
    static let minimumListHeight: CGFloat = 160

    /// PURE. The height of the two columns while the list is beneath them:
    /// as tall as the buttons need, so the list starts straight under them,
    /// but leaving the list its minimum. Nil until the buttons have been
    /// measured (the columns then fill the page, as without a list).
    static func columnsHeight(columnContent: CGFloat, pageHeight: CGFloat) -> CGFloat? {
        guard columnContent > 0 else { return nil }
        return min(columnContent, max(0, pageHeight - minimumListHeight))
    }

    /// PURE. Landscape, judged from the window (`windowHeight` as above),
    /// so the keyboard coming up in portrait is not mistaken for a turn.
    static func isLandscape(width: CGFloat, windowHeight: CGFloat) -> Bool {
        width > windowHeight
    }
}

/// The system's window controls: the close, minimise and resize buttons at
/// the top leading corner of an iPad window that is not full screen. Their
/// size is `GeometryProxy.containerCornerInsets.topLeading`, read at a
/// page's root; it is zero in a full-screen window and on an iPhone.
enum WindowControls {
    /// Clear space between the controls and the first button of a bar.
    static let gap: CGFloat = 8

    /// The leading padding to ADD to a bar that starts at the window's
    /// leading edge and already has `existing` padding there.
    static func extraLeading(controls: CGFloat, existing: CGFloat) -> CGFloat {
        guard controls > 0 else { return 0 }
        return max(0, controls + gap - existing)
    }
}

private struct WideWindowColumn: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontal
    @Environment(\.verticalSizeClass) private var vertical
    let width: CGFloat

    func body(content: Content) -> some View {
        // Regular in both directions: an iPad window with room, never an
        // iPhone (compact one way or the other), never a narrow iPad window.
        if horizontal == .regular && vertical == .regular {
            content
                .frame(maxWidth: width)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

/// A sheet the height of a page and no wider than a page's column: for an
/// editor opened as a sheet in a roomy window. In landscape the system's
/// page sheet is much wider than the content it holds.
struct ColumnPageSizing: PresentationSizing {
    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        let system: PagePresentationSizing = .page
        let page = system.proposedSize(for: root, context: context)
        let width = min(page.width ?? WideWindow.columnWidth, WideWindow.columnWidth)
        return ProposedViewSize(width: width, height: page.height)
    }
}

/// A small panel, for a sheet that holds one action (the sign-in sheet).
/// In a roomy window the system's sheet is a panel about 580 by 650 pt, and
/// one button sat a third of the way down a large blank. This asks for a
/// narrower, shorter panel that still leaves room around the button for a
/// line of explanation and for larger text: its height is given by the
/// caller, scaled with the text size, and is never less than `baseHeight`.
/// Only where `roomy`: in a phone-sized space it hands back the system's
/// own sizing untouched, so the sheet there is exactly as it always was.
struct CompactPanelSizing: PresentationSizing {
    static let width: CGFloat = 440
    /// The height at the default text size.
    static let baseHeight: CGFloat = 340
    var height: CGFloat = baseHeight
    /// `WideWindow.isRoomy`, read by the view that presents the sheet.
    var roomy: Bool

    /// PURE. Never wider or taller than the system's own form sheet.
    static func size(formWidth: CGFloat?, formHeight: CGFloat?, height: CGFloat) -> CGSize {
        let wanted = max(height, baseHeight)
        return CGSize(width: min(formWidth ?? width, width),
                      height: min(wanted, formHeight ?? wanted))
    }

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        guard roomy else {
            let unchanged: AutomaticPresentationSizing = .automatic
            return unchanged.proposedSize(for: root, context: context)
        }
        let system: FormPresentationSizing = .form
        let form = system.proposedSize(for: root, context: context)
        let size = Self.size(formWidth: form.width, formHeight: form.height, height: height)
        return ProposedViewSize(width: size.width, height: size.height)
    }
}

/// A small panel as tall as what it holds: the profile peek, a card of a
/// few lines. In a roomy window the system's sheet is about 580 by 650 pt
/// and the card sat low in a mostly empty panel. This asks for the small
/// panel's width and the content's own height at that width, so the panel
/// grows with larger text and with a longer list of instruments, and is
/// never larger than the system's own sheet. Only where `roomy`: in a
/// phone-sized space the system's sizing is handed back untouched.
struct FittedPanelSizing: PresentationSizing {
    /// `WideWindow.isRoomy`, read by the view that presents the sheet.
    var roomy: Bool

    /// PURE. `contentHeight` is the content's height at the panel's width,
    /// its own margins included.
    static func size(formWidth: CGFloat?, formHeight: CGFloat?, contentHeight: CGFloat) -> CGSize {
        let width = min(formWidth ?? CompactPanelSizing.width, CompactPanelSizing.width)
        let wanted = max(contentHeight.rounded(.up), 1)
        return CGSize(width: width, height: min(wanted, formHeight ?? wanted))
    }

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        guard roomy else {
            let unchanged: AutomaticPresentationSizing = .automatic
            return unchanged.proposedSize(for: root, context: context)
        }
        let system: FormPresentationSizing = .form
        let form = system.proposedSize(for: root, context: context)
        let width = min(form.width ?? CompactPanelSizing.width, CompactPanelSizing.width)
        let content = root.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let size = Self.size(formWidth: form.width, formHeight: form.height, contentHeight: content.height)
        return ProposedViewSize(width: size.width, height: size.height)
    }
}

/// The on-screen keyboard as it sits across the foot of the screen, from
/// the keyboard's own reports. For a panel that keeps its content clear of
/// the keyboard itself (`clearOfKeyboardInPanel`).
enum DockedKeyboard {

    /// PURE. The keyboard's top edge, in screen coordinates, when it is
    /// docked across the foot of the screen. Nil for a keyboard that is
    /// away, floating, split, or has no height: nothing is covered then.
    static func top(endFrame: CGRect, screen: CGRect) -> CGFloat? {
        guard endFrame.height > 0,
              endFrame.minY < screen.maxY,
              endFrame.maxY >= screen.maxY - 1,
              endFrame.width >= screen.width - 1 else { return nil }
        return endFrame.minY
    }

    /// PURE. How much of a view whose bottom edge is at `viewBottom` (screen
    /// coordinates) lies under a keyboard whose top edge is at
    /// `keyboardTop`. Never negative, and never more than the view.
    static func overlap(viewBottom: CGFloat, viewHeight: CGFloat, keyboardTop: CGFloat?) -> CGFloat {
        guard let keyboardTop else { return 0 }
        return min(max(0, viewBottom - keyboardTop), max(0, viewHeight))
    }
}

/// Measures, in UIKit, how much of the view it sits behind is under the
/// keyboard, and says so whenever that changes.
private struct KeyboardOverlapProbe: UIViewRepresentable {
    var active: Bool
    var onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.onChange = onChange
        view.active = active
    }

    final class ProbeView: UIView {
        var onChange: ((CGFloat) -> Void)?
        var active = false {
            didSet {
                guard active != oldValue else { return }
                if active { measure() } else { report(0) }
            }
        }
        /// The keyboard's last reported frame, in screen coordinates.
        private var keyboardFrame: CGRect?
        private var reported: CGFloat = 0
        private var observers: [NSObjectProtocol] = []

        override func didMoveToWindow() {
            super.didMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard window != nil else { return }
            let centre = NotificationCenter.default
            // The frame it is going to, and again once it is there: the
            // system moves a sheet up when the keyboard comes, so the
            // panel's own place is only final afterwards.
            for name in [UIResponder.keyboardWillShowNotification, UIResponder.keyboardWillChangeFrameNotification,
                         UIResponder.keyboardDidShowNotification, UIResponder.keyboardDidChangeFrameNotification] {
                observers.append(centre.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                    MainActor.assumeIsolated {
                        self?.keyboardFrame = frame
                        self?.measure()
                        DispatchQueue.main.async { self?.measure() }
                    }
                })
            }
            // Going away is final at once, whatever was reserved before.
            for name in [UIResponder.keyboardWillHideNotification, UIResponder.keyboardDidHideNotification] {
                observers.append(centre.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.keyboardFrame = nil
                        self?.report(0)
                    }
                })
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            measure()
        }

        private func measure() {
            guard active, let window, let keyboardFrame else { return report(0) }
            let screen = window.screen
            let top = DockedKeyboard.top(endFrame: keyboardFrame, screen: screen.bounds)
            let mine = convert(bounds, to: screen.coordinateSpace)
            report(DockedKeyboard.overlap(viewBottom: mine.maxY, viewHeight: mine.height, keyboardTop: top))
        }

        private func report(_ overlap: CGFloat) {
            guard abs(overlap - reported) > 0.5 else { return }
            reported = overlap
            onChange?(overlap)
        }
    }
}

/// See `clearOfKeyboardInPanel`.
private struct PanelKeyboardClearance: ViewModifier {
    @State private var overlap: CGFloat = 0

    func body(content: Content) -> some View {
        // By the WINDOW: inside an iPad's panel the width class is compact,
        // as on a phone, so the size classes cannot tell the two apart.
        let roomy = WideWindow.isRoomy
        content
            .padding(.bottom, roomy ? overlap : 0)
            .background {
                KeyboardOverlapProbe(active: roomy) { new in
                    withAnimation(.easeOut(duration: 0.25)) { overlap = new }
                }
            }
            .ignoresSafeArea(roomy ? .keyboard : [], edges: .bottom)
    }
}

extension View {

    /// For a sheet with a field at its foot (Comments), shown as a panel in
    /// a roomy window. There the content is kept clear of the keyboard by
    /// the keyboard's own reports and not by the system's reckoning: on an
    /// iPad, after a comment was sent in landscape and the keyboard went
    /// away, the space it had taken stayed reserved, and the field sat in
    /// the middle of the panel until the iPad was turned (seen 2026-11-22).
    /// The moment the keyboard starts to leave, nothing is reserved.
    /// In a phone-sized space this does nothing and the system's own
    /// handling is unchanged.
    func clearOfKeyboardInPanel() -> some View {
        modifier(PanelKeyboardClearance())
    }

    /// For the sheet that shows a profile peek: in a roomy window a small
    /// panel as tall as the card (`FittedPanelSizing`). Unchanged on a phone.
    @MainActor
    func profilePeekPanel() -> some View {
        presentationSizing(FittedPanelSizing(roomy: WideWindow.isRoomy))
    }

    /// For a top bar the app draws itself, with a button at its leading
    /// end. In an iPad window that is not full screen the system puts its
    /// window controls in the top leading corner, on top of that button.
    /// This moves the bar's leading end clear of them. Where there are no
    /// window controls (a full-screen window, an iPhone) it does nothing.
    /// It is the system's own measure and has no effect inside a scroll
    /// view; a bar that scrolls takes `WindowControls.extraLeading` from
    /// its page's root instead.
    func clearOfWindowControls() -> some View {
        containerCornerOffset(.leading, sizeToFit: true)
    }

    /// Keeps a page's content in a centred column where the window is wide
    /// and tall. Anywhere else the view is returned untouched.
    func wideWindowColumn(_ width: CGFloat = WideWindow.columnWidth) -> some View {
        modifier(WideWindowColumn(width: width))
    }

    /// For a small picker sheet. In a phone-sized space it is half height,
    /// as it always was. In a roomy window a sheet is a smaller centred
    /// panel, and half of that crowds a wheel and cuts its lower rows: there
    /// a wheel picker gets a fixed height that shows the whole wheel, and a
    /// list of choices gets the whole panel.
    @MainActor
    func pickerSheetHeight(wheel: Bool = false) -> some View {
        presentationDetents(WideWindow.isRoomy ? [wheel ? .height(WideWindow.wheelSheetHeight) : .large] : [.medium])
    }
}
