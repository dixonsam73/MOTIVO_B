//
//  ManuscriptIcon.swift
//  MOTIVO
//
//  The manuscript button's icon: five stave lines and a pencil, drawn as a
//  vector (Samuel's design, 2026-11-21). It is drawn, not an image, so it
//  is sharp at every scale and takes the button's colour.
//
//  It is sized to sit beside the SF Symbols on the same buttons, which are
//  set with `.font(.system(size: 22, weight: .semibold))`: about the same
//  width and height as those glyphs, with a stroke of the same weight.
//
//  THE FIVE LINES MUST STAY FIVE. At the button's size the lines are 1.9 pt
//  thick on a 3.5 pt pitch, which leaves 1.6 pt of clear space between
//  them: nearly five device pixels on an iPhone, more than three on an
//  iPad. The reference drawing's lines are thinner and closer; copied at
//  this size they would close up, so the stave here is a little taller and
//  the lines a little heavier. `ManuscriptIconTests` pins the clear space.
//

import SwiftUI

/// The icon, at the size of an SF Symbol set with `.system(size: pointSize,
/// weight: .semibold)`. It takes the foreground style it is given.
struct ManuscriptIcon: View {
    var pointSize: CGFloat = 22

    var body: some View {
        let scale = pointSize / ManuscriptIconGeometry.referencePointSize
        ManuscriptIconShape()
            .stroke(style: StrokeStyle(lineWidth: ManuscriptIconGeometry.stroke * scale,
                                       lineCap: .round, lineJoin: .round))
            .frame(width: ManuscriptIconGeometry.box.width * scale,
                   height: ManuscriptIconGeometry.box.height * scale)
            .accessibilityHidden(true)
    }
}

/// The drawing's measurements, in points at the Timer button's size.
enum ManuscriptIconGeometry {
    /// The SF Symbol point size these measurements sit beside.
    static let referencePointSize: CGFloat = 22

    /// The whole icon, strokes included.
    static let box = CGSize(width: 26.2, height: 21.2)

    /// One weight for the stave and the pencil.
    static let stroke: CGFloat = 1.9

    /// The five stave lines: the y of each, top to bottom.
    static let lineYs: [CGFloat] = [2.0, 5.5, 9.0, 12.5, 16.0]
    static let lineStartX: CGFloat = 1.1
    /// Where each line ends. They shorten down the stave to leave the
    /// pencil room, as in the design.
    static let lineEndXs: [CGFloat] = [18.5, 16.1, 13.5, 10.9, 8.3]

    /// The clear space between neighbouring stave lines.
    static var clearSpaceBetweenLines: CGFloat {
        let pitches = zip(lineYs.dropFirst(), lineYs).map { $0 - $1 }
        return (pitches.min() ?? 0) - stroke
    }

    /// The pencil: its point, the middle of its far end, and its measures.
    static let pencilTip = CGPoint(x: 10.7, y: 20.2)
    static let pencilEnd = CGPoint(x: 23.5, y: 4.2)
    static let pencilHalfWidth: CGFloat = 2.2
    /// From the point to where the barrel starts.
    static let pencilConeLength: CGFloat = 4.4
    /// From the far end back to the band.
    static let pencilBandInset: CGFloat = 3.7
    static let pencilEndRadius: CGFloat = 1.5
}

struct ManuscriptIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        typealias G = ManuscriptIconGeometry
        var path = Path()

        // The stave.
        for (y, endX) in zip(G.lineYs, G.lineEndXs) {
            path.move(to: CGPoint(x: G.lineStartX, y: y))
            path.addLine(to: CGPoint(x: endX, y: y))
        }

        // The pencil, drawn along its own axis: `s` runs from the point to
        // the far end, `w` across it.
        let tip = G.pencilTip, end = G.pencilEnd
        let dx = end.x - tip.x, dy = end.y - tip.y
        let length = (dx * dx + dy * dy).squareRoot()
        let ux = dx / length, uy = dy / length
        func point(_ s: CGFloat, _ w: CGFloat) -> CGPoint {
            // (ux, uy) along the pencil; (-uy, ux) across it.
            CGPoint(x: tip.x + ux * s - uy * w, y: tip.y + uy * s + ux * w)
        }
        let h = G.pencilHalfWidth, cone = G.pencilConeLength, r = G.pencilEndRadius

        // Outline: point, up one side, round the far end, down the other.
        path.move(to: point(0, 0))
        path.addLine(to: point(cone, h))
        path.addLine(to: point(length - r, h))
        path.addQuadCurve(to: point(length, h - r), control: point(length, h))
        path.addLine(to: point(length, -h + r))
        path.addQuadCurve(to: point(length - r, -h), control: point(length, -h))
        path.addLine(to: point(cone, -h))
        path.closeSubpath()

        // Where the point meets the barrel, and the band near the far end.
        path.move(to: point(cone, h))
        path.addLine(to: point(cone, -h))
        path.move(to: point(length - G.pencilBandInset, h))
        path.addLine(to: point(length - G.pencilBandInset, -h))

        // The measurements are for `box`; fit them to the space given.
        let scale = min(rect.width / G.box.width, rect.height / G.box.height)
        let fitted = path.applying(CGAffineTransform(scaleX: scale, y: scale))
        let offsetX = rect.minX + (rect.width - G.box.width * scale) / 2
        let offsetY = rect.minY + (rect.height - G.box.height * scale) / 2
        return fitted.applying(CGAffineTransform(translationX: offsetX, y: offsetY))
    }
}
