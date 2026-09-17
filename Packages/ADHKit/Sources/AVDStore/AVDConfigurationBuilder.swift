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
        // A resizable device starts in the emulator's phone preset, which its screen must match.
        let screen = profile.isResizable ? ResizableScreen.builtIn.first { $0.mode == .phone } : nil
        config["hw.lcd.width"] = String(screen?.width ?? profile.widthPixels)
        config["hw.lcd.height"] = String(screen?.height ?? profile.heightPixels)
        config["hw.lcd.density"] = String(screen?.density ?? profile.density)
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

        if profile.isResizable {
            addResizableSettings(to: &config)
        }

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

    /// The hinge of the unfolded preset, as Android Studio writes it.
    ///
    /// `hw.resizable.configs` is deliberately left out: emulator 36.5 segfaults on start when
    /// `config.ini` has it, and its built-in presets are the same values.
    private static func addResizableSettings(to config: inout IniDocument) {
        let unfolded = ResizableScreen.builtIn.first { $0.mode == .foldable }
        config["hw.sensor.hinge"] = "yes"
        config["hw.sensor.hinge.count"] = "1"
        config["hw.sensor.hinge.type"] = "1"
        config["hw.sensor.hinge.sub_type"] = "1"
        config["hw.sensor.hinge.ranges"] = "180-360"
        config["hw.sensor.hinge.defaults"] = "180"
        config["hw.sensor.hinge.areas"] = unfolded.map { "\($0.width / 2)-0-1-\($0.height)" } ?? ""
        config["hw.sensor.hinge.resizable.config"] = String(ResizableMode.foldable.rawValue)
        config["hw.sensor.posture_list"] = "1, 2, 3"
        config["hw.sensor.hinge_angles_posture_definitions"] = "180-330, 30-180, 0-30"
        config["hw.sensor.hinge.fold_to_displayRegion.0.1_at_posture"] = "4"
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
