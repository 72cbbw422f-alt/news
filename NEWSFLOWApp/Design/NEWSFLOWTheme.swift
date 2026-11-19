import SwiftUI

enum NEWSFLOWTheme {
    static let ink = Color(red: 0.12, green: 0.16, blue: 0.20)
    static let secondaryInk = Color(red: 0.43, green: 0.46, blue: 0.48)
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let card = Color.white
    static let accent = Color(red: 0.82, green: 0.31, blue: 0.20)
    static let line = Color(red: 0.88, green: 0.87, blue: 0.83)

    static func pageBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.07, green: 0.09, blue: 0.11) : paper
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.12, green: 0.14, blue: 0.16) : card
    }

    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.93, green: 0.93, blue: 0.90) : ink
    }
}
