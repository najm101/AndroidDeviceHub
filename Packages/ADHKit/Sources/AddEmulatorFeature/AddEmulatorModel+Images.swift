import SDKDomain

extension AddEmulatorModel {
    struct APIChoice: Hashable, Identifiable {
        var level: APILevel
        var stageLabel: String?

        var id: String { "\(level)-\(stageLabel ?? "")" }

        var title: String {
            let base = "API \(level) · \(level.androidVersionTitle)"
            return stageLabel.map { "\(base) (\($0))" } ?? base
        }
    }

    /// What exists for one API level, for the API picker's badges.
    struct APIAvailability: Equatable {
        /// An image with the chosen services is installed (or, for Wear/TV, any image is).
        var isInstalled = false
        /// Service variants offered for this level, in picker order. Empty for Wear/TV profiles.
        var services: [ImageServices] = []
        var installedServices: Set<ImageServices> = []
    }

    var availableServices: [ImageServices] {
        guard let profile = selectedProfile else { return ImageServices.allCases }
        return ImageServices.allCases.filter { $0 != .googlePlay || profile.playStore }
    }

    /// Images that run on the selected hardware with the chosen services and filters.
    var compatibleImages: [SystemImageEntry] {
        guard let profile = selectedProfile else { return [] }
        return images.filter { entry in
            let details = entry.details
            return profile.supports(details)
                && servicesMatch(details)
                && details.usesSixteenKBPages == showSixteenKBImages
                && (showPreviewImages || !details.stage.isPrerelease)
        }
    }

    var apiChoices: [APIChoice] {
        var seen = Set<APIChoice>()
        return
            compatibleImages
            .map { APIChoice(level: $0.details.apiLevel, stageLabel: $0.details.stage.label) }
            .filter { seen.insert($0).inserted }
            .sorted { lhs, rhs in
                if lhs.level != rhs.level { return lhs.level > rhs.level }
                return lhs.stageLabel == nil && rhs.stageLabel != nil
            }
    }

    func availability(of choice: APIChoice) -> APIAvailability {
        guard let profile = selectedProfile else { return APIAvailability() }
        // Same filters as `compatibleImages`, except services, so every variant shows up.
        let forLevel = images.filter { entry in
            let details = entry.details
            return profile.supports(details)
                && details.apiLevel == choice.level
                && details.stage.label == choice.stageLabel
                && details.usesSixteenKBPages == showSixteenKBImages
                && (showPreviewImages || !details.stage.isPrerelease)
        }
        guard profile.formFactor.usesMobileImages else {
            return APIAvailability(isInstalled: forLevel.contains(where: \.isInstalled))
        }
        let offered = Set(forLevel.map(\.details.services))
        let installed = Set(forLevel.filter(\.isInstalled).map(\.details.services))
        return APIAvailability(
            isInstalled: installed.contains(services),
            services: availableServices.filter(offered.contains),
            installedServices: installed
        )
    }

    var imagesForSelectedAPI: [SystemImageEntry] {
        guard let selectedAPI else { return [] }
        return compatibleImages.filter {
            $0.details.apiLevel == selectedAPI.level && $0.details.stage.label == selectedAPI.stageLabel
        }
        .sorted { lhs, rhs in
            if lhs.isInstalled != rhs.isInstalled { return lhs.isInstalled }
            if lhs.details.isBaseExtension != rhs.details.isBaseExtension { return lhs.details.isBaseExtension }
            return (lhs.details.extensionLevel ?? 0) > (rhs.details.extensionLevel ?? 0)
        }
    }

    var selectedImage: SystemImageEntry? {
        selectedImagePath.flatMap { path in images.first { $0.path == path } }
    }

    private func servicesMatch(_ details: SystemImageDetails) -> Bool {
        // Form factors with dedicated images (Wear, TV, …) don't use the Play/APIs/AOSP split.
        guard selectedProfile?.formFactor.usesMobileImages != false else { return true }
        return details.services == services
    }
}
