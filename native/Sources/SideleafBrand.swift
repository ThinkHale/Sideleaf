import SwiftUI

/// Original supplied artwork remains full color and keeps its intrinsic proportions.
struct SideleafWordmark: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Image("SideleafWordmark")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(
                width: horizontalSizeClass == .compact ? 110 : 150,
                height: horizontalSizeClass == .compact ? 36 : 50
            )
            .background(Color.sideleafPaper, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Sideleaf")
    }
}

struct SideleafEmptyPage: View {
    var body: some View {
        VStack(spacing: 18) {
            Image("SideleafLockup")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 330)
                .accessibilityLabel("Sideleaf")
            Text("The next page is yours.")
                .font(.title2)
                .fontDesign(.serif)
                .foregroundStyle(Color(red: 0.04, green: 0.13, blue: 0.23))
            Text("Create a page to write, draw, and gather your thoughts.")
                .font(.body)
                .foregroundStyle(Color(red: 0.32, green: 0.36, blue: 0.37))
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sideleafPaper)
    }
}

private extension Color {
    static let sideleafPaper = Color(red: 1, green: 0.99, blue: 0.97)
}
