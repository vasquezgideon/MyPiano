import SwiftUI
import UIKit

struct AccentChoice: Identifiable {
    let id: String
    let title: String
    let hex: String
}

enum AccentPalette {
    static let presets: [AccentChoice] = [
        .init(id: "apple", title: "Apple Blue", hex: "#007AFF"),
        .init(id: "indigo", title: "Indigo", hex: "#5856D6"),
        .init(id: "teal", title: "Teal", hex: "#008B93"),
        .init(id: "mint", title: "Mint", hex: "#00A884"),
        .init(id: "orange", title: "Orange", hex: "#F07822"),
        .init(id: "pink", title: "Pink", hex: "#E04491")
    ]

    static func color(preset: String, customHex: String) -> UIColor {
        let value = preset == "custom" ? customHex : (presets.first { $0.id == preset }?.hex ?? "#007AFF")
        return UIColor(rgbHex: value) ?? UIColor.systemBlue
    }

    static func textColor(on color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
        let brightness = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return brightness > 0.64 ? UIColor.black : UIColor.white
    }
}

extension UIColor {
    convenience init?(rgbHex: String) {
        let value = rgbHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(red: CGFloat((number >> 16) & 0xFF) / 255,
                  green: CGFloat((number >> 8) & 0xFF) / 255,
                  blue: CGFloat(number & 0xFF) / 255, alpha: 1)
    }

    var rgbHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#007AFF" }
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()),
                      Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
