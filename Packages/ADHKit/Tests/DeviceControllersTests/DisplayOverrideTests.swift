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

    @Test func rejectsValuesAndroidWouldRefuse() {
        #expect(DisplayConfiguration(size: PixelSize(width: 100, height: 2400), density: 420).validationError != nil)
        #expect(DisplayConfiguration(size: PixelSize(width: 1080, height: 2400), density: 20).validationError != nil)
        #expect(phone.current.validationError == nil)
    }
}
