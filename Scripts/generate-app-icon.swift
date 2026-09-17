// Draws the app icon and writes every size into App/Resources/Assets.xcassets/AppIcon.appiconset.
// Usage: swift Scripts/generate-app-icon.swift
import AppKit
import SwiftUI

struct AppIcon: View {
    var body: some View {
        ZStack {
            // macOS icon grid: an 824 pt rounded square centered in 1024 pt.
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.36, green: 0.85, blue: 0.55), Color(red: 0.05, green: 0.52, blue: 0.40)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 4)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.3), radius: 18, y: 10)

            // A tablet behind a phone.
            device(
                width: 380, height: 500, corner: 44, bezel: 22,
                screen: [Color(red: 0.62, green: 0.86, blue: 0.74), Color(red: 0.78, green: 0.93, blue: 0.85)]
            )
            .rotationEffect(.degrees(-8))
            .offset(x: -95, y: -30)
            device(
                width: 300, height: 600, corner: 58, bezel: 16,
                screen: [Color(red: 0.80, green: 0.97, blue: 0.87), .white]
            )
            .rotationEffect(.degrees(6))
            .offset(x: 95, y: 40)
        }
        .frame(width: 1024, height: 1024)
    }

    private func device(width: CGFloat, height: CGFloat, corner: CGFloat, bezel: CGFloat, screen: [Color]) -> some View
    {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color(white: 0.12))
                .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
            RoundedRectangle(cornerRadius: corner - bezel, style: .continuous)
                .fill(
                    LinearGradient(colors: screen, startPoint: .top, endPoint: .bottom)
                )
                .padding(bezel)
            // App grid on the screen.
            let dot = width * 0.16
            VStack(spacing: dot * 0.45) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: dot * 0.45) {
                        ForEach(0..<3, id: \.self) { column in
                            RoundedRectangle(cornerRadius: dot * 0.3, style: .continuous)
                                .fill(
                                    Color(
                                        hue: 0.38 + Double(row * 3 + column) * 0.025, saturation: 0.7, brightness: 0.7)
                                )
                                .frame(width: dot, height: dot)
                        }
                    }
                }
            }
        }
        .frame(width: width, height: height)
    }
}

@MainActor
func render() throws {
    let folder = URL(filePath: "App/Resources/Assets.xcassets/AppIcon.appiconset", directoryHint: .isDirectory)
    var images: [[String: String]] = []
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = points * scale
            let renderer = ImageRenderer(content: AppIcon())
            renderer.scale = CGFloat(pixels) / 1024
            guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            try data?.write(to: folder.appending(path: name))
            images.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)", "filename": name])
        }
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: folder.appending(path: "Contents.json"))
}

try MainActor.assumeIsolated { try render() }
print("Wrote AppIcon.appiconset")
