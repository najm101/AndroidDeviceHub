import DeviceDomain
import Foundation
import SDKDomain

extension AddEmulatorModel {
    var imageStatus: ImageStatus {
        guard let image = selectedImage else { return .none }
        if image.isInstalled { return .installed }
        if installs.activeInstalls[image.path] != nil { return .downloading }
        return .notInstalled
    }

    enum ImageStatus {
        case none, installed, downloading, notInstalled
    }

    var nameProblem: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter a name." }
        let id = VirtualDeviceName.id(fromDisplayName: trimmed)
        guard VirtualDeviceName.isValidID(id) else {
            return "Use letters, numbers, spaces, dots, dashes or underscores."
        }
        let taken = dependencies.repository.devices.contains {
            if case let .emulator(existing) = $0.id { return existing.lowercased() == id.lowercased() }
            return false
        }
        return taken ? "A device with this name already exists." : nil
    }

    var canContinue: Bool {
        selectedProfile != nil
    }

    var canFinish: Bool {
        selectedProfile != nil
            && nameProblem == nil
            && !isCreating
            && [.installed, .downloading].contains(imageStatus)
    }

    var finishHint: String? {
        switch imageStatus {
        case .none: "Select a system image."
        case .notInstalled: "Download the system image first."
        case .downloading: "The device can be created now; it's ready when the download finishes."
        case .installed: nameProblem
        }
    }
}
