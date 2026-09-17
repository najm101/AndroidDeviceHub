import DesignSystem
import SwiftUI

/// Asks for a device name and runs `commit`, showing errors inline.
struct NameDeviceSheet: View {
    let title: String
    let actionTitle: String
    let commit: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var error: String?
    @State private var isWorking = false

    init(title: String, actionTitle: String, initialName: String, commit: @escaping (String) async throws -> Void) {
        self.title = title
        self.actionTitle = actionTitle
        self.commit = commit
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            Text(title)
                .font(.title3.bold())
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(actionTitle, action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || isWorking)
            }
        }
        .padding(Spacing.xLarge)
        .frame(width: 380)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmedName.isEmpty else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await commit(trimmedName)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
