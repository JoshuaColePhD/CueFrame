import SwiftUI

/// A superellipse shared by the SwiftUI preview and Core Image export mask.
struct SquircleShape: Shape {
    func path(in rect: CGRect) -> Path { Path(Self.cgPath(in: rect)) }

    static func cgPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        for index in 0...160 {
            let angle = Double(index) / 160 * 2 * Double.pi
            let c = cos(angle), s = sin(angle)
            let x = (c < 0 ? -1.0 : 1.0) * pow(abs(c), 0.5)
            let y = (s < 0 ? -1.0 : 1.0) * pow(abs(s), 0.5)
            let point = CGPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
