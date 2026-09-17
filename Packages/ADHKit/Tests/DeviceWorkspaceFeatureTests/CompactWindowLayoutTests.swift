import CoreGraphics
import Testing

@testable import DeviceWorkspaceFeature

struct CompactWindowLayoutTests {
    let phone = CompactWindowLayout(deviceAspectRatio: 0.5)
    let screen = CGSize(width: 1500, height: 900)
    let margin = CompactWindowLayout.margin
    let footer = CompactWindowLayout.footerHeight

    /// The empty space beside the device, for a content size.
    func sideGap(_ layout: CompactWindowLayout, _ size: CGSize) -> CGFloat {
        let deviceWidth = layout.deviceHeight(in: size) * layout.deviceAspectRatio
        return (size.width - deviceWidth) / 2
    }

    @Test func contentIsTheDevicePlusMarginAndFooter() {
        let size = phone.contentSize(deviceHeight: 600)
        #expect(size == CGSize(width: 300 + 2 * margin, height: 600 + 2 * margin + footer))
        #expect(phone.deviceHeight(in: size) == 600)
    }

    @Test(arguments: [
        CGSize(width: 400, height: 500), CGSize(width: 330, height: 900), CGSize(width: 900, height: 700),
    ])
    func resizingKeepsTheDeviceShape(proposed: CGSize) {
        let current = phone.contentSize(deviceHeight: 600)
        let size = phone.resized(from: current, to: proposed, within: screen)
        #expect(abs(sideGap(phone, size) - margin) <= 0.5)
    }

    @Test func draggingASideEdgeScalesByWidth() {
        let current = phone.contentSize(deviceHeight: 600)
        let wider = CGSize(width: current.width + 100, height: current.height)
        #expect(phone.resized(from: current, to: wider, within: screen) == phone.contentSize(deviceHeight: 800))
    }

    @Test func draggingTheBottomEdgeScalesByHeight() {
        let current = phone.contentSize(deviceHeight: 600)
        let taller = CGSize(width: current.width, height: current.height - 100)
        #expect(phone.resized(from: current, to: taller, within: screen) == phone.contentSize(deviceHeight: 500))
    }

    @Test func sizeStaysBetweenTheMinimumAndTheScreen() {
        let current = phone.contentSize(deviceHeight: 600)
        let tiny = phone.resized(from: current, to: CGSize(width: 50, height: 50), within: screen)
        #expect(tiny == phone.minimumContentSize)
        #expect(tiny.width >= CompactWindowLayout.minimumWidth)

        let huge = phone.resized(from: current, to: CGSize(width: 3000, height: 3000), within: screen)
        #expect(huge.height <= screen.height)
        #expect(huge.width <= screen.width)
    }

    @Test func minimumKeepsTheFooterAndAMinimumDeviceHeight() {
        let watch = CompactWindowLayout(deviceAspectRatio: 1.1)
        #expect(watch.minimumContentSize.width >= CompactWindowLayout.minimumWidth)
        #expect(watch.deviceHeight(in: watch.minimumContentSize) >= CompactWindowLayout.minimumDeviceHeight)
        // A wide device can't go below the minimum device height either.
        let tv = CompactWindowLayout(deviceAspectRatio: 1.9)
        #expect(tv.deviceHeight(in: tv.minimumContentSize) == CompactWindowLayout.minimumDeviceHeight)
    }

    @Test func rotatingKeepsTheLongSide() {
        let portrait = phone.contentSize(deviceHeight: 600)
        let landscape = CompactWindowLayout(deviceAspectRatio: 2)
        let size = landscape.rotated(from: phone, content: portrait, within: screen)
        #expect(size == landscape.contentSize(deviceHeight: 300))
        #expect(phone.rotated(from: landscape, content: size, within: screen) == portrait)
    }

    @Test func rotatingShrinksToFitTheScreen() {
        let portrait = phone.contentSize(deviceHeight: 800)
        let landscape = CompactWindowLayout(deviceAspectRatio: 2)
        let size = landscape.rotated(from: phone, content: portrait, within: CGSize(width: 700, height: 900))
        #expect(size.width <= 700)
        #expect(abs(sideGap(landscape, size) - margin) <= 0.5)
    }
}
