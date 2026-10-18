//
//  WindowMetrics.swift
//  MOTIVO
//
//  The space the app actually has, instead of the whole screen.
//
//  iPhone Duo (RELEASE.md, decided 2026-10-11): `UIScreen.main.bounds`
//  assumes the app fills the screen. On every ordinary iPhone it does, so
//  the window and the screen are the same rectangle and these helpers give
//  exactly the numbers the old code got (checked by `WindowMetricsTests` on
//  the iPhone simulator). On the unfolded Duo, or
//  in an iPad window, the window can be smaller than the screen, and only
//  the window is right.
//

import UIKit

enum WindowMetrics {

    /// The foreground key window, if there is one.
    @MainActor
    static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let ordered = scenes.filter { $0.activationState == .foregroundActive }
            + scenes.filter { $0.activationState != .foregroundActive }
        return ordered.lazy.compactMap { scene in
            scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        }.first
    }

    /// The window's bounds in its own coordinates, which is SwiftUI's
    /// `.global` space. Falls back to the scene's screen when no window
    /// exists yet.
    @MainActor
    static var windowBounds: CGRect {
        if let window = keyWindow { return window.bounds }
        return fallbackScreenBounds
    }

    /// The window's frame in screen coordinates, the space keyboard frames
    /// are reported in.
    @MainActor
    static var windowFrameInScreen: CGRect {
        guard let window = keyWindow else { return fallbackScreenBounds }
        return window.convert(window.bounds, to: window.screen.coordinateSpace)
    }

    @MainActor
    private static var fallbackScreenBounds: CGRect {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds }
            .first ?? .zero
    }

    /// PURE. How much of the window the keyboard covers, from the bottom.
    /// The old code used the screen's height in place of the window's
    /// bottom edge; on iPhone they are equal.
    static func keyboardOverlap(windowFrameInScreen: CGRect, keyboardFrameInScreen: CGRect) -> CGFloat {
        max(0, windowFrameInScreen.maxY - keyboardFrameInScreen.minY)
    }

    /// The overlap for a keyboard frame from a keyboard notification.
    @MainActor
    static func keyboardOverlap(keyboardFrameInScreen: CGRect) -> CGFloat {
        keyboardOverlap(windowFrameInScreen: windowFrameInScreen, keyboardFrameInScreen: keyboardFrameInScreen)
    }
}
