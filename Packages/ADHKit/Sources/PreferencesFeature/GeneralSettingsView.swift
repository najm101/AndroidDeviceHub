import AppKit
import DesignSystem
import DeviceDomain
import Foundations
import SDKDomain
public import SwiftUI

/// Settings → General.
public struct GeneralSettingsView: View {
    @AppStorage(PreferenceKey.defaultBootMode) private var defaultBootMode = BootMode.quick.rawValue
    @AppStorage(PreferenceKey.showEmulatorWindow) private var showEmulatorWindow = false
    @AppStorage(PreferenceKey.captureFolder) private var captureFolder = ""
    @AppStorage(PreferenceKey.recordingQuality) private var recordingQuality = RecordingQuality.standard.rawValue
    @State private var isChoosingFolder = false

    public init() {}

    public var body: some View {
        Form {
            Section("New Devices") {
                Picker("Default boot", selection: $defaultBootMode) {
                    ForEach(BootMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
            }

            Section {
                Toggle("Show emulators in their own window", isOn: $showEmulatorWindow)
            } header: {
                Text("Running Devices")
            } footer: {
                Text(
                    "The emulator's own window replaces the screen inside this app. "
                        + "Settings, apps and files stay available. Applies the next time a device starts."
                )
                .foregroundStyle(.secondary)
            }

            Section("Screenshots and Recordings") {
                LabeledContent("Save to") {
                    HStack(spacing: Spacing.small) {
                        Text(
                            folderURL.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~")
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(folderURL.path(percentEncoded: false))
                        Menu("Change") {
                            Button("Choose Folder…") { isChoosingFolder = true }
                            Button("Use Desktop") { captureFolder = "" }
                                .disabled(captureFolder.isEmpty)
                            Divider()
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([folderURL])
                            }
                        }
                        .fixedSize()
                    }
                }
                Picker("Recording quality", selection: $recordingQuality) {
                    ForEach(RecordingQuality.allCases) { quality in
                        Text(quality.title).tag(quality.rawValue)
                    }
                }
            }

            Section {
                LabeledContent("When quitting", value: "Running emulators keep running")
            } footer: {
                Text("Shut a device down from its ⋯ menu. Emulators left running reconnect when the app opens again.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                captureFolder = url.path(percentEncoded: false)
            }
        }
    }

    private var folderURL: URL {
        captureFolder.isEmpty ? URL.desktopDirectory : URL(filePath: captureFolder, directoryHint: .isDirectory)
    }
}
