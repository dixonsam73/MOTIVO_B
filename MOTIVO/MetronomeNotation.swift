import SwiftUI
import UIKit

/// Vector notation: no font dependency, emoji substitution or fractional rule in time signatures.
struct MetronomeMeterGlyph: View {
    let meter: MetronomeMeter
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 16.5
    var body: some View {
        VStack(spacing: -3) {
            Text("\(meter.numerator)")
            Text("\(meter.denominator)")
        }
        .font(.system(size: size, weight: .semibold, design: .serif))
        .fixedSize()
    }
}

struct MetronomeRhythmGlyph: View {
    var notes = 1
    var beams = 0
    var dotted = false
    var triplet = false
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 28
    private var unitWidth: CGFloat { CGFloat(max(1, notes) - 1) * 12 + (dotted || (notes == 1 && beams > 0) ? 23 : 17) }
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / unitWidth, y: size.height / (triplet ? 36 : 28))
            let top: CGFloat = triplet ? 12 : 4
            for index in 0..<max(1, notes) {
                let x = CGFloat(index) * 12 + 6
                var head = Path(ellipseIn: CGRect(x: x - 4, y: top + 15, width: 8, height: 5.5))
                head = head.applying(CGAffineTransform(translationX: -x, y: -(top + 18)))
                    .applying(CGAffineTransform(rotationAngle: -.pi / 8))
                    .applying(CGAffineTransform(translationX: x, y: top + 18))
                context.fill(head, with: .foreground)
                context.fill(Path(CGRect(x: x + 3, y: top, width: 1.3, height: 18)), with: .foreground)
            }
            if notes > 1 {
                for beam in 0..<beams {
                    context.fill(Path(CGRect(x: 9, y: top + CGFloat(beam) * 5, width: CGFloat(notes - 1) * 12 + 1.3, height: 2.7)), with: .foreground)
                }
            } else {
                for flag in 0..<beams {
                    let y = top + CGFloat(flag) * 5
                    var path = Path()
                    path.move(to: CGPoint(x: 9, y: y))
                    path.addCurve(to: CGPoint(x: 15, y: y + 13),
                                  control1: CGPoint(x: 20, y: y + 4),
                                  control2: CGPoint(x: 21, y: y + 8))
                    path.addCurve(to: CGPoint(x: 9, y: y + 3),
                                  control1: CGPoint(x: 19, y: y + 6),
                                  control2: CGPoint(x: 12, y: y + 5))
                    path.closeSubpath()
                    context.fill(path, with: .foreground)
                }
            }
            if dotted {
                context.fill(Path(ellipseIn: CGRect(x: 16, y: top + 15, width: 2.8, height: 2.8)), with: .foreground)
            }
            if triplet {
                context.draw(Text("3").font(.system(size: 9, weight: .medium)), at: CGPoint(x: unitWidth / 2, y: 4))
            }
        }
        .frame(width: unitWidth * height / 28, height: height * (triplet ? 36 / 28 : 1))
        .accessibilityHidden(true)
    }
}

extension MetronomeRhythmGlyph {
    init(beatUnit: MetronomeBeatUnit) {
        beams = beatUnit == .quaver ? 1 : 0
        dotted = beatUnit == .dottedCrotchet
    }

    init(subdivision: MetronomeSubdivision, meter: MetronomeMeter) {
        notes = subdivision.count(in: meter)
        beams = subdivision == .semiquavers ? 2 : subdivision == .beat ? 0 : 1
        if meter.beatUnit == .quaver { beams += 1 }
        dotted = subdivision == .beat && meter.isCompound
        triplet = subdivision == .triplets
    }
}

/// Native inline wheel with rows tall enough for stacked signatures and beamed notation.
/// Explicit row sizing also prevents overlap at accessibility text sizes.
struct MetronomeNotationWheel<Value: Hashable, Content: View>: UIViewRepresentable {
    let values: [Value]
    @Binding var selection: Value
    let label: String
    let valueLabel: (Value) -> String
    let height: CGFloat
    let contentID: AnyHashable
    @ViewBuilder let content: (Value) -> Content

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MetronomePickerView {
        let picker = MetronomePickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.clipsToBounds = true
        picker.backgroundColor = .clear
        picker.isAccessibilityElement = true
        picker.accessibilityTraits = .adjustable
        picker.adjust = { [weak picker, weak coordinator = context.coordinator] step in
            guard let picker, let coordinator else { return }
            let row = min(coordinator.parent.values.count - 1, max(0, picker.selectedRow(inComponent: 0) + step))
            guard row >= 0 else { return }
            picker.selectRow(row, inComponent: 0, animated: false)
            coordinator.pickerView(picker, didSelectRow: row, inComponent: 0)
        }
        return picker
    }
    func updateUIView(_ picker: MetronomePickerView, context: Context) {
        context.coordinator.synchronize(self, with: picker)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MetronomePickerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 80, height: height)
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: MetronomeNotationWheel
        var images: [Int: UIImage] = [:]
        private var synchronizedSelection: Value?
        init(_ parent: MetronomeNotationWheel) { self.parent = parent }
        func synchronize(_ configuration: MetronomeNotationWheel, with picker: MetronomePickerView) {
            let reload = parent.values != configuration.values || parent.height != configuration.height
                || parent.contentID != configuration.contentID || images.isEmpty
            parent = configuration
            if reload {
                images.removeAll()
                picker.reloadAllComponents()
            }
            // Beat animations redraw this view while a wheel is still scrolling. Only a
            // changed model or new row content may reposition it; its visible row can be
            // ahead of the binding until UIKit commits the user's settled selection.
            if reload || synchronizedSelection != parent.selection {
                if let row = parent.values.firstIndex(of: parent.selection), picker.selectedRow(inComponent: 0) != row {
                    picker.selectRow(row, inComponent: 0, animated: false)
                }
                synchronizedSelection = parent.selection
            }
            picker.accessibilityLabel = parent.label
            picker.accessibilityValue = parent.valueLabel(parent.selection)
        }
        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { parent.values.count }
        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { parent.height * 0.86 }
        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            if images[row] == nil {
                let renderer = ImageRenderer(content: parent.content(parent.values[row]))
                renderer.scale = pickerView.traitCollection.displayScale
                images[row] = renderer.uiImage
            }
            // UIKit may display one row in several wheel bands simultaneously. Cache the
            // immutable glyph image, never the UIView, which can have only one superview.
            let imageView = (view as? UIImageView) ?? UIImageView()
            imageView.image = images[row]
            imageView.contentMode = .center
            imageView.backgroundColor = .clear
            imageView.isUserInteractionEnabled = false
            imageView.frame = CGRect(x: 0, y: 0, width: pickerView.bounds.width, height: parent.height * 0.86)
            return imageView
        }
        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            guard parent.values.indices.contains(row) else { return }
            let value = parent.values[row]
            synchronizedSelection = value
            parent.selection = value
            pickerView.accessibilityValue = parent.valueLabel(value)
        }
    }
}

final class MetronomePickerView: UIPickerView {
    var adjust: ((Int) -> Void)?
    override func accessibilityIncrement() { adjust?(1) }
    override func accessibilityDecrement() { adjust?(-1) }
}
