import SwiftUI
import UIKit

enum AppTheme {
    static let canvas = dynamicColor(light: 0xF8F8F6, dark: 0x050605)
    static let elevated = dynamicColor(light: 0xF0F1EE, dark: 0x111310)
    static let surface = dynamicColor(light: 0xE8EAE6, dark: 0x191C18)
    static let divider = dynamicColor(light: 0xD9DDD6, dark: 0x292D28)
    static let signal = dynamicColor(light: 0x177D52, dark: 0x5FD09A)
    static let signalMuted = dynamicColor(light: 0xDDEFE6, dark: 0x163426)
    static let warning = dynamicColor(light: 0x936611, dark: 0xE2B95C)

    static let contentMaxWidth: CGFloat = 760
    static let standardPadding: CGFloat = 20
    static let compactPadding: CGFloat = 16
    static let minimumHitTarget: CGFloat = 44

    private static func dynamicColor(light: UInt32, dark: UInt32) -> Color {
        Color(
            uiColor: UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
            }
        )
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
