import CoreGraphics
import DeviceDomain
import Testing

@testable import DeviceControllers

struct DisplayOverrideTests {
    let phone = DisplayMetrics(physicalSize: PixelSize(width: 1080, height: 2400), physicalDensity: 420)

    @Test func parsesPhysicalAndOverrideValues() {
        let plain = DeviceOutputParsers.displayMetrics(
            size: "Physical size: 1080x2400\n", density: "Physical density: 420\n"
        )
        #expect(plain == phone)

        let overridden = DeviceOutputParsers.displayMetrics(
            size: "Physical size: 1080x2400\nOverride size: 1080x1728\n",
            density: "Physical density: 420\nOverride density: 216\n"
        )
        #expect(overridden?.current == DisplayConfiguration(size: PixelSize(width: 1080, height: 1728), density: 216))
        #expect(overridden?.isOverridden == true)

        #expect(DeviceOutputParsers.displayMetrics(size: "cmd: Can't find service", density: "") == nil)
    }

    @Test func presetsKeepTheirShapeAndDPSize() {
        let tablet = ScreenPreset(name: "Tablet", widthDP: 1280, heightDP: 800)
        let portrait = tablet.configuration(fitting: phone.physicalSize)
        #expect(portrait == DisplayConfiguration(size: PixelSize(width: 1080, height: 1728), density: 216))
        #expect(portrait.sizeDP == PixelSize(width: 800, height: 1280))

        let landscape = tablet.configuration(fitting: PixelSize(width: 2560, height: 1600))
        #expect(landscape.sizeDP == PixelSize(width: 1280, height: 800))
        #expect(landscape.size.width <= 2560 && landscape.size.height <= 1600)
    }

    @Test func densityFollowsTheResolutionToKeepPhysicalSize() {
        #expect(phone.densityKeepingPhysicalSize(for: phone.physicalSize) == 420)
        #expect(phone.densityKeepingPhysicalSize(for: PixelSize(width: 540, height: 1200)) == 210)
        // A wider shape is letterboxed, so the width decides the scale.
        #expect(phone.densityKeepingPhysicalSize(for: PixelSize(width: 2160, height: 2400)) == 840)
    }

    @Test func overridesChangeTheDrawnShapeAndSize() {
        #expect(phone.contentArea == CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(phone.apparentSize == phone.physicalSize)

        var tablet = phone
        tablet.overrideSize = PixelSize(width: 1080, height: 1728)
        tablet.overrideDensity = 216
        #expect(tablet.contentArea.width == 1)
        #expect(abs(tablet.contentArea.height - 0.72) < 0.0001)
        #expect(abs(tablet.contentArea.minY - 0.14) < 0.0001)
        // 800 × 1280 dp drawn at the panel's 420 dpi.
        #expect(tablet.apparentSize == PixelSize(width: 2100, height: 3360))

        var denser = phone
        denser.overrideDensity = 840
        #expect(denser.apparentSize == PixelSize(width: 540, height: 1200))
    }

    @Test func rejectsValuesAndroidWouldRefuse() {
        #expect(DisplayConfiguration(size: PixelSize(width: 100, height: 2400), density: 420).validationError != nil)
        #expect(DisplayConfiguration(size: PixelSize(width: 1080, height: 2400), density: 20).validationError != nil)
        #expect(phone.current.validationError == nil)
    }
}
