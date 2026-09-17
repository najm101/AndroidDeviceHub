import DesignSystem
import DeviceDomain
import SwiftUI

struct SnapshotsSection: View {
    let model: DeviceSettingsModel

    @State private var isNaming = false
    @State private var newName = ""
    @State private var pendingLoad: DeviceSnapshot?
    @State private var pendingDelete: DeviceSnapshot?

    private var isBusy: Bool { model.busySections.contains(.snapshots) }

    var body: some View {
        LiveContent(setting: model.snapshots) { snapshots in
            if snapshots.isEmpty {
                Text("No snapshots yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(snapshots) { snapshot in
                SnapshotRow(snapshot: snapshot)
                    .contextMenu { actions(for: snapshot) }
                    .overlay(alignment: .trailing) {
                        Menu("Actions", systemImage: Symbol.more) { actions(for: snapshot) }
                            .labelStyle(.iconOnly)
                            .menuIndicator(.hidden)
                            .menuStyle(.button)
                            .buttonStyle(.borderless)
                            .fixedSize()
                            .disabled(isBusy)
                    }
            }
            HStack {
                if let message = model.lastSnapshotAction {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save Snapshot…") {
                    newName = Self.suggestedName()
                    isNaming = true
                }
                .disabled(isBusy)
            }
        }
        .alert("Save Snapshot", isPresented: $isNaming) {
            TextField("Name", text: $newName)
            Button("Save") { model.saveSnapshot(named: newName) }
                .disabled(model.snapshotNameError(newName) != nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.snapshotNameError(newName) ?? "Saves the device's current state. This can take a few seconds.")
        }
        .confirmationDialog(
            "Load “\(pendingLoad?.name ?? "")”?",
            isPresented: isPresenting($pendingLoad),
            presenting: pendingLoad
        ) { snapshot in
            Button("Load Snapshot") { model.loadSnapshot(snapshot) }
        } message: { _ in
            Text("The device's current state will be replaced. Unsaved changes are lost.")
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: isPresenting($pendingDelete),
            presenting: pendingDelete
        ) { snapshot in
            Button("Delete", role: .destructive) { model.deleteSnapshot(snapshot) }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    @ViewBuilder
    private func actions(for snapshot: DeviceSnapshot) -> some View {
        Button("Load…") { pendingLoad = snapshot }
            .disabled(!snapshot.isCompatible || isBusy)
        Button("Delete…", role: .destructive) { pendingDelete = snapshot }
            .disabled(isBusy)
    }

    private func isPresenting(_ item: Binding<DeviceSnapshot?>) -> Binding<Bool> {
        Binding {
            item.wrappedValue != nil
        } set: {
            if !$0 { item.wrappedValue = nil }
        }
    }

    private static func suggestedName() -> String {
        "snap_"
            + Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "T", with: "_")
            .replacingOccurrences(of: "Z", with: "")
    }
}

private struct SnapshotRow: View {
    let snapshot: DeviceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack(spacing: Spacing.xSmall) {
                Text(snapshot.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if snapshot.isLoaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Currently loaded")
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, Spacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(snapshot.isCompatible ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if let date = snapshot.createdAt {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        parts.append(snapshot.sizeBytes.formatted(.byteCount(style: .file)))
        if !snapshot.isCompatible {
            parts.append("Incompatible")
        }
        return parts.joined(separator: " · ")
    }
}
