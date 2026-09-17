import ADHTestSupport
import APKMetadata
import Foundation
import Testing

/// Fixtures are the compiled manifest and resource table of two AOSP apps from an API 36 emulator.
struct APKLabelReaderTests {
    func label(_ app: String) throws -> String? {
        let manifest = try Fixtures.data("apk/\(app)-AndroidManifest.xml.bin")
        switch try APKLabelReader.manifestLabel(manifest) {
        case let .text(text): return text
        case let .resource(id):
            return try APKLabelReader.string(for: id, in: try Fixtures.data("apk/\(app)-resources.arsc"))
        case nil: return nil
        }
    }

    @Test func resolvesLabelsThroughTheResourceTable() throws {
        #expect(try label("BasicDreams") == "Basic Daydreams")
        #expect(try label("EasterEgg") == "Android Easter Egg")
    }

    @Test func rejectsOtherData() {
        #expect(throws: APKMetadataError.self) { try APKLabelReader.manifestLabel(Data("<manifest/>".utf8)) }
        #expect(throws: APKMetadataError.self) { try APKLabelReader.string(for: 0x7f01_0000, in: Data([2, 0, 12])) }
    }

    @Test func truncatedFilesThrowInsteadOfCrashing() throws {
        let manifest = try Fixtures.data("apk/EasterEgg-AndroidManifest.xml.bin")
        for length in stride(from: 0, to: manifest.count, by: 97) {
            _ = try? APKLabelReader.manifestLabel(manifest.prefix(length))
        }
        let table = try Fixtures.data("apk/EasterEgg-resources.arsc")
        for length in stride(from: 0, to: table.count, by: 1_013) {
            _ = try? APKLabelReader.string(for: 0x7f13_0000, in: table.prefix(length))
        }
    }
}
