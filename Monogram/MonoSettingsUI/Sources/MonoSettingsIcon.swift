import Foundation
import UIKit

// 30x30 settings-row icon: white lowercase "m" on a black rounded square,
// same geometry as the app icon (1024 grid scaled down).
public enum MonoSettingsIcon {
    public static let image: UIImage = render()

    private static func render() -> UIImage {
        let side: CGFloat = 30.0
        let scale = side / 1024.0
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { _ in
            let tile = UIBezierPath(roundedRect: CGRect(x: 0.0, y: 0.0, width: side, height: side), cornerRadius: 7.0)
            UIColor(white: 0.04, alpha: 1.0).setFill()
            tile.fill()
            UIColor(white: 1.0, alpha: 0.18).setStroke()
            tile.lineWidth = 0.5
            tile.stroke()

            let glyph = UIBezierPath()
            let radius = 111.0 * scale
            let arcY = 470.0 * scale
            let bottomY = 720.0 * scale
            let left = 290.0 * scale
            let middle = 512.0 * scale
            let right = 734.0 * scale

            glyph.move(to: CGPoint(x: left, y: bottomY))
            glyph.addLine(to: CGPoint(x: left, y: arcY))
            glyph.addArc(withCenter: CGPoint(x: left + radius, y: arcY), radius: radius, startAngle: .pi, endAngle: 0.0, clockwise: true)
            glyph.addLine(to: CGPoint(x: middle, y: bottomY))
            glyph.move(to: CGPoint(x: middle, y: arcY))
            glyph.addArc(withCenter: CGPoint(x: middle + radius, y: arcY), radius: radius, startAngle: .pi, endAngle: 0.0, clockwise: true)
            glyph.addLine(to: CGPoint(x: right, y: bottomY))

            glyph.lineWidth = 84.0 * scale
            glyph.lineCapStyle = .round
            glyph.lineJoinStyle = .round
            UIColor.white.setStroke()
            glyph.stroke()
        }
    }
}
