public import SwiftUI

/// The Android robot's head: a half dome with two antennae and two eyes.
///
/// Based on the Android robot, reproduced or modified from work created and shared by Google and used
/// according to terms described in the Creative Commons 3.0 Attribution License.
public struct AndroidRobotHead: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        // Drawn on a 24×24 grid, then scaled to fit `rect`.
        var path = Path()
        path.move(to: CGPoint(x: 1, y: 20))
        path.addArc(
            center: CGPoint(x: 12, y: 20), radius: 11,
            startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false
        )
        path.closeSubpath()
        for side in [-1.0, 1.0] {
            // Antennae as thin rotated bars, so the shape can be filled.
            let bar = Path(roundedRect: CGRect(x: -0.9, y: -4.2, width: 1.8, height: 4.6), cornerRadius: 0.9)
            let transform = CGAffineTransform(translationX: 12 + side * 6.2, y: 10.2)
                .rotated(by: side * .pi / 6)
            path.addPath(bar, transform: transform)
            path.addEllipse(in: CGRect(x: 12 + side * 5 - 1.4, y: 14.2, width: 2.8, height: 2.8))
        }
        let scale = min(rect.width, rect.height) / 24
        let offset = CGPoint(x: rect.midX - 12 * scale, y: rect.midY - 12 * scale)
        return path.applying(CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale))
    }
}

#Preview {
    AndroidRobotHead()
        .fill(.green, style: FillStyle(eoFill: true))
        .frame(width: 96, height: 96)
        .padding()
}
