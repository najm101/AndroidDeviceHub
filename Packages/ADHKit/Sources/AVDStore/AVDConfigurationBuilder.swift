import Foundation
import Foundations
import SDKDomain

/// Builds `config.ini` for a new device, matching what Android Studio writes.
enum AVDConfigurationBuilder {
    static func configuration(for spec: VirtualDeviceSpecification) -> IniDocument {
        var config = IniDocument(style: .spaced)
        let profile = spec.profile
        let image = spec.image

        config["AvdId"] = spec.id
        config["avd.ini.displayname"] = spec.displayName
        config["avd.ini.encoding"] = "UTF-8"
        config["PlayStore.enabled"] = yesNo(image.hasPlayStore && profile.playStore)
        config["abi.type"] = image.abi.rawValue
        config["hw.cpu.arch"] = image.abi.cpuArchitecture
        config["hw.cpu.ncore"] = String(spec.cpuCores)
        config["hw.ramSize"] = String(spec.ramMiB)
        config["vm.heapSize"] = String(spec.vmHeapMiB)
        config["disk.dataPartition.size"] = String(Int64(spec.internalStorageMiB) * .mebibyte)

        config["hw.device.manufacturer"] = profile.manufacturer
        config["hw.device.name"] = profile.id
        config["hw.lcd.width"] = String(profile.widthPixels)
        config["hw.lcd.height"] = String(profile.heightPixels)
        config["hw.lcd.density"] = String(profile.density)
        config["hw.initialOrientation"] = spec.orientation.rawValue
        config["hw.keyboard"] = yesNo(spec.useHostKeyboard || profile.hasHardwareKeyboard)
        config["hw.mainKeys"] = yesNo(profile.hasHardwareButtons)
        config["hw.dPad"] = yesNo(profile.hasDPad)
        config["hw.trackBall"] = "no"
        config["hw.gpu.enabled"] = "yes"
        config["hw.gpu.mode"] = spec.graphics.rawValue
        config["hw.camera.front"] = profile.hasFrontCamera ? spec.frontCamera.rawValue : CameraMode.none.rawValue
        config["hw.camera.back"] = profile.hasBackCamera ? spec.backCamera.rawValue : CameraMode.none.rawValue
        config["hw.audioInput"] = "yes"
        config["hw.battery"] = "yes"
        config["hw.gps"] = "yes"
        config["hw.accelerometer"] = "yes"
        config["hw.gyroscope"] = "yes"
        config["hw.sensors.proximity"] = "yes"
        config["hw.sensors.orientation"] = "yes"
        config["hw.sensors.light"] = "yes"
        config["hw.sensors.pressure"] = "yes"
        config["hw.sensors.magnetic_field"] = "yes"
        config["hw.arc"] = "false"

        if let sdCard = spec.sdCardMiB, sdCard > 0 {
            config["hw.sdCard"] = "yes"
            config["sdcard.size"] = "\(sdCard)M"
        } else {
            config["hw.sdCard"] = "no"
        }

        config["image.sysdir.1"] = image.sysdir
        config["tag.id"] = image.primaryTag.id
        config["tag.display"] = image.primaryTag.display
        config["tag.ids"] = image.tags.map(\.id).joined(separator: ",")
        config["tag.displaynames"] = image.tags.map(\.display).joined(separator: ",")

        config["fastboot.forceColdBoot"] = yesNo(spec.bootMode == .cold)
        config["fastboot.forceFastBoot"] = yesNo(spec.bootMode == .quick)
        config["fastboot.forceChosenSnapshotBoot"] = "no"
        config["fastboot.chosenSnapshotFile"] = ""

        config["runtime.network.speed"] = spec.networkSpeed.rawValue
        config["runtime.network.latency"] = spec.networkLatency.rawValue

        if let skin = spec.skinPath {
            config["skin.name"] = skin.lastPathComponent
            config["skin.path"] = skin.path(percentEncoded: false)
            config["skin.dynamic"] = "yes"
            config["showDeviceFrame"] = "yes"
        } else {
            config["skin.name"] = "\(profile.widthPixels)x\(profile.heightPixels)"
            config["skin.dynamic"] = "yes"
            config["showDeviceFrame"] = "no"
        }
        return config
    }

    /// `<AVD_HOME>/<id>.ini`
    static func pointer(id: String, avdDirectory: URL, image: SystemImageDetails?) -> IniDocument {
        var ini = IniDocument(style: .compact)
        ini["avd.ini.encoding"] = "UTF-8"
        ini["path"] = avdDirectory.path(percentEncoded: false).trimmingSuffix("/")
        ini["path.rel"] = "avd/\(avdDirectory.lastPathComponent)"
        if let image {
            ini["target"] =
                image.platformFolder.hasPrefix("android-")
                ? "android-\(image.apiLevel)"
                : image.platformFolder
        }
        return ini
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }
}

extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
