import HardwareProfiles
import SDKDomain
import Testing

struct HardwareProfilesTests {
    let profiles = BundledHardwareProfiles().profiles()

    @Test func loadsAllBundledProfiles() {
        #expect(profiles.count == 88)
        #expect(Set(profiles.map(\.id)).count == profiles.count)
    }

    @Test func listsPixelsFirst() throws {
        let firstPhone = try #require(profiles.first { $0.formFactor == .phone })
        #expect(firstPhone.id.hasPrefix("pixel"))
        let pixel8 = try #require(profiles.first { $0.id == "pixel_8" })
        #expect(pixel8.density == 420)
        #expect(pixel8.playStore)
        #expect(pixel8.resolutionText == "1080×2400")
    }

    @Test func coversEveryFormFactor() {
        for factor in FormFactor.allCases {
            #expect(profiles.contains { $0.formFactor == factor }, "missing \(factor)")
        }
    }
}
