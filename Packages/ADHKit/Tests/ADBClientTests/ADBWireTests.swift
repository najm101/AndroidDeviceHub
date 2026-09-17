import Foundation
import Testing

@testable import ADBClient

struct ADBWireTests {
    @Test func requestsArePrefixedWithHexLength() {
        #expect(String(decoding: ADBWire.request("host:version"), as: UTF8.self) == "000chost:version")
    }

    @Test func hexLengthRejectsGarbage() throws {
        #expect(try ADBWire.hexLength(Data("001a".utf8)) == 26)
        #expect(throws: ADBError.self) { try ADBWire.hexLength(Data("zz".utf8)) }
    }

    @Test func parsesTheLongDeviceList() {
        let text = """
            emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:4
            R58M123ABC             unauthorized usb:1-1 transport_id:7

            """
        let devices = ADBDeviceEntry.parseList(text)
        #expect(devices.count == 2)
        #expect(devices[0].serial == "emulator-5554")
        #expect(devices[0].isReady)
        #expect(devices[0].model == "sdk_gphone64_arm64")
        #expect(devices[1].state == .unauthorized)
    }

    @Test func decodesShellV2PacketsAcrossChunks() throws {
        var stream = Data()
        stream.append(packet(1, "hello "))
        stream.append(packet(2, "oops"))
        stream.append(packet(1, "world"))
        stream.append(packet(3, Data([7])))

        var decoder = ShellV2Decoder()
        var packets: [ShellV2Packet] = []
        // Feed the bytes in awkward pieces.
        var offset = 0
        for size in [3, 1, 9, 2, 100] where offset < stream.count {
            let end = min(offset + size, stream.count)
            decoder.append(stream[offset..<end])
            offset = end
            while let next = try decoder.next() { packets.append(next) }
        }
        #expect(packets.map(\.kind) == [.stdout, .stderr, .stdout, .exit])
        #expect(String(decoding: packets[0].payload + packets[2].payload, as: UTF8.self) == "hello world")
        #expect(packets[3].payload == Data([7]))
    }

    @Test func syncRequestsUseLittleEndianLengths() {
        let data = ADBSyncSession.request("LIS2", "/sdcard")
        #expect(data.prefix(4) == Data("LIS2".utf8))
        #expect(data.littleEndianInteger(at: 4, as: UInt32.self) == 7)
        #expect(data.suffix(7) == Data("/sdcard".utf8))
    }

    @Test func decodesStatV2() {
        var stat = Data(count: 68)
        stat.replaceSubrange(20..<24, with: le(UInt32(0o040755)))
        stat.replaceSubrange(36..<44, with: le(Int64(4096)))
        stat.replaceSubrange(52..<60, with: le(Int64(1_700_000_000)))
        let entry = ADBSyncSession.entryV2(name: "Download", stat: stat)
        #expect(entry.isDirectory)
        #expect(entry.size == 4096)
        #expect(entry.modified == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func packageManagerResults() throws {
        try PackageManagerOutput.check("Success\n")
        #expect(PackageManagerOutput.sessionID("Success: created install session [1234]") == 1234)
        #expect {
            try PackageManagerOutput.check("Failure [INSTALL_FAILED_OLDER_SDK: Requires newer sdk version #99]")
        } throws: { error in
            (error as? ADBError) == .failed("The app needs a newer Android version.")
        }
    }

    @Test func installCommandsForBothTransports() {
        #expect(
            ADBDevice.command(["package", "install", "-S", "10"], abb: true) == "package\u{0}install\u{0}-S\u{0}10")
        #expect(
            ADBDevice.command(["package", "install", "-S", "10"], abb: false) == "cmd 'package' 'install' '-S' '10'")
        #expect(shellQuoted("it's") == "'it'\\''s'")
    }

    private func packet(_ id: UInt8, _ text: String) -> Data {
        packet(id, Data(text.utf8))
    }

    private func packet(_ id: UInt8, _ payload: Data) -> Data {
        var data = Data([id])
        data.appendLittleEndian(UInt32(payload.count))
        data.append(payload)
        return data
    }

    private func le<T: FixedWidthInteger>(_ value: T) -> Data {
        var data = Data()
        data.appendLittleEndian(value)
        return data
    }
}
