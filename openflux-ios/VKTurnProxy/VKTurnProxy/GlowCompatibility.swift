import SwiftUI
struct OpenFluxBackdrop: View {
    var body: some View {
        OpenFluxStyle.background.ignoresSafeArea()
    }
}

struct OpenFluxSupportButton: View {
    var body: some View {
        Link(destination: URL(string: "https://t.me/Igorekk777")!) {
            Label("Поддержка", systemImage: "headphones")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 1, green: 0.85, blue: 0.66))
                .padding(.horizontal, 12).padding(.vertical, 10)
                
        }.accessibilityLabel("Поддержка OpenFlux в Telegram")
    }
}

