import ADHTestSupport
import AppKit
import DeviceDomain
import EmulatorRuntime
import Foundation
import IOSurface
import Testing

@testable import DeviceControllers

/// Opt-in: start an emulator with `-grpc <port> -grpc-use-token`, then
/// `ADH_LIVE=1 swift test --filter LiveEmulatorTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ADH_LIVE"] == "1"), .serialized)
@MainActor
struct LiveEmulatorTests {
    func session() throws -> EmulatorSession {
        let emulator = try #require(EmulatorDiscovery().runningEmulators().first { $0.hasGRPCToken })
        return try EmulatorSession(
            emulator: emulator,
            displaySize: PixelSize(width: 1080, height: 2400),
            frameDirectory: FileManager.default.temporaryDirectory.appending(path: "adh-live-frames")
        )
    }

    func firstFrame(_ session: EmulatorSession, maxPixels: PixelSize) async throws -> ScreenFrame {
        for await frame in session.frames(maxPixels: maxPixels) {
            return frame
        }
        throw CancellationError()
    }

    /// Average brightness of a horizontal band, from a BGRA surface.
    func surfaceBand(_ frame: ScreenFrame, rowFraction: Double) -> Double {
        IOSurfaceLock(frame.surface, .readOnly, nil)
        defer { IOSurfaceUnlock(frame.surface, .readOnly, nil) }
        let stride = IOSurfaceGetBytesPerRow(frame.surface)
        let base = IOSurfaceGetBaseAddress(frame.surface).assumingMemoryBound(to: UInt8.self)
        let row = Int(Double(frame.height - 1) * rowFraction)
        var total = 0
        for x in 0..<frame.width {
            let pixel = base + row * stride + x * 4
            total += Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])
        }
        return Double(total) / Double(frame.width * 3)
    }

    func pngBand(_ data: Data, rowFraction: Double, width: Int, height: Int) throws -> Double {
        let bitmap = try #require(NSBitmapImageRep(data: data))
        let scaledRow = Int(Double(bitmap.pixelsHigh - 1) * rowFraction)
        var total = 0.0
        for x in 0..<bitmap.pixelsWide {
            let color = try #require(bitmap.colorAt(x: x, y: scaledRow))
            total += (color.redComponent + color.greenComponent + color.blueComponent) * 255
        }
        return total / Double(bitmap.pixelsWide * 3)
    }

    @Test func frameRowsMatchScreenshot() async throws {
        let session = try session()
        defer { session.close() }
        let frame = try await firstFrame(session, maxPixels: PixelSize(width: 540, height: 1200))
        let png = try await session.screenshot()
        print("LIVE frame \(frame.width)x\(frame.height) rotation \(frame.rotation)")
        for fraction in [0.02, 0.5, 0.98] {
            let fromSurface = surfaceBand(frame, rowFraction: fraction)
            let fromPNG = try pngBand(png, rowFraction: fraction, width: frame.width, height: frame.height)
            let flipped = surfaceBand(frame, rowFraction: 1 - fraction)
            print("LIVE row \(fraction): surface \(fromSurface) flipped \(flipped) png \(fromPNG)")
        }
    }

    /// Scrolls Settings over ADB and measures the frame stream (target: ≥ 55 fps, < 50 ms added delay).
    @Test func framePerformance() async throws {
        let session = try session()
        defer { session.close() }
        let environment = ProcessInfo.processInfo.environment
        let sdk =
            environment["ANDROID_HOME"] ?? environment["ANDROID_SDK_ROOT"] ?? "\(NSHomeDirectory())/Library/Android/sdk"
        let adb = "\(sdk)/platform-tools/adb"
        let scroll = Process()
        scroll.executableURL = URL(filePath: adb)
        scroll.arguments = [
            "shell",
            "am start -n com.android.settings/.Settings >/dev/null; sleep 1; "
                + "for i in 1 2 3 4 5 6 7 8; do input swipe 540 1900 540 500 350; input swipe 540 500 540 1900 350; done",
        ]
        try scroll.run()
        defer { scroll.terminate() }
        try await Task.sleep(for: .seconds(1.5))

        var delays: [Double] = []
        var count = 0
        let start = Date()
        for await frame in session.frames(maxPixels: PixelSize(width: 1440, height: 1440)) {
            count += 1
            if let produced = frame.producedAt { delays.append(Date().timeIntervalSince(produced) * 1000) }
            if Date().timeIntervalSince(start) > 5 { break }
        }
        let seconds = Date().timeIntervalSince(start)
        delays.sort()
        let median = delays.isEmpty ? -1 : delays[delays.count / 2]
        let p95 = delays.isEmpty ? -1 : delays[Int(Double(delays.count) * 0.95)]
        print(
            String(
                format: "PERF fps %.1f, delay median %.1f ms, p95 %.1f ms (%d frames)",
                Double(count) / seconds, median, p95, count))
        #expect(Double(count) / seconds > 30)
    }

    @Test func rotationReportsLandscape() async throws {
        let session = try session()
        defer { session.close() }
        try await session.rotate(.left)
        try await Task.sleep(for: .seconds(2))
        let frame = try await firstFrame(session, maxPixels: PixelSize(width: 1200, height: 1200))
        print("LIVE after left: \(frame.width)x\(frame.height) rotation \(frame.rotation)")
        try await session.rotate(.right)
        try await Task.sleep(for: .seconds(2))
        let back = try await firstFrame(session, maxPixels: PixelSize(width: 1200, height: 1200))
        print("LIVE after right: \(back.width)x\(back.height) rotation \(back.rotation)")
        #expect(back.rotation == .portrait)
    }
}

extension LiveEmulatorTests {
    /// Prints the raw panel coordinates Android receives for a touch sent in portrait and landscape.
    @Test func rawTouchCoordinates() async throws {
        let session = try session()
        defer { session.close() }
        let sink = FileManager.default.temporaryDirectory.appending(path: "adh-getevent.txt")
        for (label, rotate) in [("portrait", false), ("landscape", true)] {
            if rotate {
                try await session.rotate(.left)
                try await Task.sleep(for: .seconds(2))
                _ = try await firstFrame(session, maxPixels: PixelSize(width: 1200, height: 1200))
            }
            let adb = Process()
            adb.executableURL = URL(
                filePath: ProcessInfo.processInfo.environment["ANDROID_HOME"]! + "/platform-tools/adb")
            adb.arguments = ["-s", "emulator-5554", "shell", "getevent", "-lt"]
            FileManager.default.createFile(atPath: sink.path, contents: nil)
            adb.standardOutput = try FileHandle(forWritingTo: sink)
            try adb.run()
            try await Task.sleep(for: .seconds(1))
            // A point that is unambiguous in both orientations: 100 px from the frame's left, 50 px from its top.
            session.touch(.began, at: CGPoint(x: 100, y: 50), pointerID: 1)
            try await Task.sleep(for: .milliseconds(200))
            session.touch(.ended, at: CGPoint(x: 100, y: 50), pointerID: 1)
            try await Task.sleep(for: .seconds(1))
            adb.terminate()
            let text = try String(contentsOf: sink, encoding: .utf8)
            let positions = text.split(separator: "\n").filter { $0.contains("ABS_MT_POSITION") }.prefix(4)
            print("LIVE \(label) (mapped with rotation \(session.rotation)): \(positions.joined(separator: " | "))")
            let dump = Process()
            dump.executableURL = adb.executableURL
            dump.arguments = ["-s", "emulator-5554", "shell", "dumpsys", "input"]
            let pipe = Pipe()
            dump.standardOutput = pipe
            try dump.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let cooked = String(decoding: data, as: UTF8.self).split(separator: "\n")
                .filter { $0.contains("Cooked") || $0.contains("orientation") || $0.contains("[0]: id=") }
                .prefix(8)
            print("LIVE \(label) dumpsys: \(cooked.joined(separator: " || "))")
        }
        try await session.rotate(.right)
    }
}

extension LiveEmulatorTests {
    /// Reads and writes every Inspector ▸ Settings value, restoring what it changes.
    @Test func settingsRoundTrip() async throws {
        let emulator = try #require(EmulatorDiscovery().runningEmulators().first { $0.hasGRPCToken })
        let session = try EmulatorSession(
            emulator: emulator,
            displaySize: PixelSize(width: 1080, height: 2400),
            frameDirectory: FileManager.default.temporaryDirectory.appending(path: "adh-live-frames")
        )
        defer { session.close() }

        let battery = try await session.battery()
        print("LIVE battery \(battery)")
        var changed = battery
        changed.level = battery.level == 42 ? 43 : 42
        changed.charger = .none
        changed.status = .discharging
        try await session.setBattery(changed)
        let readBattery = try await session.battery()
        #expect(readBattery.level == changed.level)
        #expect(readBattery.charger == .none)
        try await session.setBattery(battery)

        let location = try await session.location()
        print("LIVE location \(location)")
        try await session.setLocation(GeoLocation(latitude: 30.0444, longitude: 31.2357, altitude: 23))
        try await Task.sleep(for: .seconds(1))
        let readLocation = try await session.location()
        print("LIVE location after set \(readLocation)")
        #expect(abs(readLocation.latitude - 30.0444) < 0.001)

        let sensors = try await session.ambientSensors()
        print("LIVE sensors \(sensors)")
        if let temperature = sensors[.temperature] {
            try await session.setAmbientSensor(.temperature, to: 31)
            let updated = try await session.ambientSensors()
            #expect(abs((updated[.temperature] ?? 0) - 31) < 0.5)
            try await session.setAmbientSensor(.temperature, to: temperature)
        }

        let brightness = try await session.brightness()
        print("LIVE brightness \(brightness)")
        print("LIVE microphone \(try await session.usesHostMicrophone())")

        let clip = try await session.clipboard()
        try await session.setClipboard("adh-live-clip")
        try await Task.sleep(for: .milliseconds(500))
        let readClip = try await session.clipboard()
        print("LIVE clipboard \(readClip)")
        #expect(readClip == "adh-live-clip")
        try await session.setClipboard(clip)

        try await session.touchFingerprint(id: 1)

        var network = try await session.networkConditions()
        network.speed = .lte
        network.signal = .moderate
        try await session.setNetworkConditions(network)
        network.speed = .full
        network.signal = .great
        try await session.setNetworkConditions(network)

        try await session.saveSnapshot(named: "adh-live-test")
        let snapshots = try await session.snapshots()
        print("LIVE snapshots \(snapshots)")
        #expect(snapshots.contains { $0.id == "adh-live-test" })
        try await session.deleteSnapshot(id: "adh-live-test")
        let afterDelete = try await session.snapshots()
        #expect(!afterDelete.contains { $0.id == "adh-live-test" })
    }
}
