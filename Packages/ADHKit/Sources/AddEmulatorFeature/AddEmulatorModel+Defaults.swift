import DeviceDomain
import SDKDomain

extension AddEmulatorModel {
    func profileChanged() {
        guard let profile = selectedProfile else { return }
        withDefaults {
            ramMiB = profile.recommendedRAMMiB
            orientation = profile.widthPixels > profile.heightPixels ? .landscape : .portrait
            useHostKeyboard = true
            if !availableServices.contains(services) {
                services = profile.playStore ? .googlePlay : .googleAPIs
            }
        }
        selectDefaultAPILevel()
        applyDefaultName()
    }

    func selectDefaultAPILevel() {
        let choices = apiChoices
        if let selectedAPI, choices.contains(selectedAPI) {
            selectDefaultImage()
            return
        }
        // Prefer the newest level that already has an installed image, then the newest stable one.
        let installed = compatibleImages.first { $0.isInstalled }
            .map { APIChoice(level: $0.details.apiLevel, stageLabel: $0.details.stage.label) }
        selectedAPI = installed ?? choices.first { $0.stageLabel == nil } ?? choices.first
        selectDefaultImage()
    }

    func selectDefaultImage() {
        let candidates = imagesForSelectedAPI
        if let selectedImagePath, candidates.contains(where: { $0.path == selectedImagePath }) { return }
        selectedImagePath = candidates.first?.path
    }

    func applyDefaultName() {
        guard !nameWasEdited, let profile = selectedProfile else { return }
        let api = selectedImage.map { " API \($0.details.apiLevel)" } ?? ""
        withDefaults { name = uniqueName(base: "\(profile.name)\(api)") }
    }

    private func uniqueName(base: String) -> String {
        let existing = Set(dependencies.repository.devices.map { $0.name.lowercased() })
        var candidate = base
        var index = 2
        while existing.contains(candidate.lowercased()) {
            candidate = "\(base) (\(index))"
            index += 1
        }
        return candidate
    }
}
