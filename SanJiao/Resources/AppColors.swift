import SwiftUI
import UIKit

// MARK: - Design System Colors (adaptive — responds to dark / light mode)
// Using `extension ShapeStyle where Self == Color` lets .appPrimary work
// in .foregroundStyle(), .fill() etc. without explicit Color.xxx syntax.
// Color.appPrimary also keeps working because Color satisfies Self == Color.
extension ShapeStyle where Self == Color {
    static var appBg: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "1C1C1E") : UIColor(hex: "F2F2F7")
        })
    }
    static var appCard: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "2C2C2E") : .white
        })
    }
    static var appPrimary: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "F5F5F5") : UIColor(hex: "1C1C1E")
        })
    }
    static var appSecondary: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "AEAEB2") : UIColor(hex: "6C6C70")
        })
    }
    static var appTertiary: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "6C6C70") : UIColor(hex: "AEAEB2")
        })
    }
    static var appSeparator: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "38383A") : UIColor(hex: "E5E5EA")
        })
    }
    // Accent colours — same in both modes
    static var appAccent:     Color { Color(hex: "6A60E9") }
    static var appAccentSoft: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "373179") : UIColor(hex: "EFECFF")
        })
    }
    /// 柔和墨绿——莫兰迪色系，承担"收入 / 完成"等正向语义；
    /// 避开 iOS 标准 #34C759 那种"超市价签"感，留出空间让品牌紫保持稀缺。
    static var appGreen: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "7CAA94") : UIColor(hex: "4A8B70")
        })
    }
    /// 荧青——"数据洞察"语义色，与 App 图标的数据点同源；
    /// 仅用于图表活动点、点选后的洞察读数，禁止用于按钮和大面积填充。
    /// 浅色模式加深为墨青，保证白卡片上的可读性。
    static var appTeal: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "3FE8D4") : UIColor(hex: "0FA896")
        })
    }
    static var appRed: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "E8504A") : UIColor(hex: "D03A34")
        })
    }
    static var appOrange: Color { Color(hex: "F0920A") }
    static var appWarning: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "FFB340") : UIColor(hex: "E58A00")
        })
    }
    static var appWarningSoft: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "4A3414") : UIColor(hex: "FFF1D6")
        })
    }
}

// MARK: - Hex initialiser for SwiftUI Color
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red:     Double(r) / 255,
                  green:   Double(g) / 255,
                  blue:    Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - Hex initialiser for UIColor (used by dynamic providers above)
extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var int: UInt64 = 0
        Scanner(string: s).scanHexInt64(&int)
        self.init(
            red:   CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8)  & 0xFF) / 255,
            blue:  CGFloat(int         & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Accent gradient (record button, onboarding CTA)
extension LinearGradient {
    static let accentGradient = LinearGradient(
        colors: [Color(hex: "9B92F1"), Color(hex: "5143EF")],
        startPoint: UnitPoint(x: 0.15, y: 0),
        endPoint:   UnitPoint(x: 0.85, y: 1)
    )
}
