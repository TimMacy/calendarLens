import AppKit
import SwiftUI

extension AppModel {
    static let minimumContrast = 3.0

    static func dashboardColor(_ color: Color, isCustom: Bool) -> Color {
        isCustom ? color : color.toned(toward: Palette.panel, by: 0.25)
    }

    static func isTooDark(_ dashboardColor: Color) -> Bool {
        dashboardColor.contrastRatio(with: Palette.panel) < minimumContrast
    }

    static func lighterColor(for dashboardColor: Color) -> Color {
        dashboardColor.lightened(toContrast: minimumContrast, against: Palette.panel)
    }
}

extension Color {
    func toned(toward base: Color, by amount: CGFloat) -> Color {
        guard let color = NSColor(self).usingColorSpace(.sRGB), let base = NSColor(base).usingColorSpace(.sRGB),
              let mixed = color.blended(withFraction: amount, of: base) else { return self }
        return Color(nsColor: mixed)
    }

    func contrastRatio(with other: Color) -> Double {
        guard let first = relativeLuminance, let second = other.relativeLuminance else { return 21 }
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    func lightened(toContrast target: Double, against background: Color) -> Color {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return self }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let brightest = NSColor(colorSpace: .sRGB, hue: hue, saturation: saturation, brightness: 1, alpha: 1)
        for step in 1...100 {
            let amount = CGFloat(step) / 50
            let candidate = amount <= 1
                ? NSColor(colorSpace: .sRGB, hue: hue, saturation: saturation, brightness: brightness + (1 - brightness) * amount, alpha: 1)
                : brightest.blended(withFraction: amount - 1, of: .white) ?? .white
            if let saved = Color(hex: Color(nsColor: candidate).hexString), saved.contrastRatio(with: background) >= target {
                return saved
            }
        }
        return .white
    }

    private var relativeLuminance: Double? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        func linear(_ value: CGFloat) -> Double {
            let value = Double(min(max(value, 0), 1))
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
    }
}
