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

extension View {

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
