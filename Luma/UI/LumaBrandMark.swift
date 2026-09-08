import SwiftUI

struct LumaBrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.47, green: 0.28, blue: 0.98),
                            Color(red: 0.19, green: 0.73, blue: 0.94)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(.white.opacity(0.94))
                .frame(width: size * 0.30, height: size * 0.30)
                .blur(radius: size * 0.02)
                .offset(x: size * 0.05, y: -size * 0.04)

            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .symbolRenderingMode(.hierarchical)
                .offset(y: size * 0.08)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.10), radius: size * 0.15, y: size * 0.08)
        .accessibilityHidden(true)
    }
}
