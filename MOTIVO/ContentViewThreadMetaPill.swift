import SwiftUI

struct ThreadMetaPill: View {
    let title: String
    let isSelected: Bool
    var font: Font = Theme.Text.body
    var verticalPadding: CGFloat = 2

    var body: some View {
        Text(title)
            .font(font)
            .padding(.horizontal, 8)
            .padding(.vertical, verticalPadding)
            .background(
                isSelected
                ? Color(uiColor: .systemGray2)
                : Color(uiColor: .tertiarySystemFill)
            )
            .clipShape(Capsule())
    }
}
