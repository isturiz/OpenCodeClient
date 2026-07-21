import SwiftUI

struct AppMark: View {
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(AppTheme.elevated)

            HStack(spacing: size * 0.07) {
                Image(systemName: "chevron.right")
                    .font(.system(size: size * 0.28, weight: .bold))
                VoiceBars(isActive: true, level: 0.72, barWidth: max(2, size * 0.045))
                    .frame(width: size * 0.3, height: size * 0.34)
            }
            .foregroundStyle(AppTheme.signal)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct VoiceBars: View {
    let isActive: Bool
    let level: Double
    var barWidth: CGFloat = 3

    private let factors: [Double] = [0.42, 0.8, 1, 0.64]

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: barWidth) {
                ForEach(Array(factors.enumerated()), id: \.offset) { _, factor in
                    Capsule()
                        .frame(
                            width: barWidth,
                            height: max(
                                barWidth,
                                proxy.size.height * (isActive ? max(0.2, level) : 0.2) * factor
                            )
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
