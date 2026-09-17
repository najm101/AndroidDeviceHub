import DesignSystem
import DeviceDomain
import SwiftUI

struct ProfilesPage: View {
    let model: DeviceInfoModel

    @State private var newUserKind: NewUserKind?
    @State private var newUserName = ""
    @State private var pendingRemoval: DeviceUser?

    enum NewUserKind: Identifiable {
        case user, workProfile

        var id: Self { self }
        var title: String { self == .user ? "New User" : "New Work Profile" }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                if let users = model.users {
                    ForEach(users.users) { user in
                        UserRow(user: user, isCurrent: user.id == users.currentUserID)
                            .contextMenu { actions(for: user, current: users.currentUserID) }
                    }
                }
            }
            .listStyle(.inset)
            .overlay {
                if model.isLoadingUsers { ProgressView() }
            }

            HStack {
                Menu("Add", systemImage: Symbol.add) {
                    Button("New User…") { begin(.user) }
                        .disabled(model.users?.canAddUsers != true)
                    if model.users?.supportsWorkProfiles == true {
                        Button("New Work Profile…") { begin(.workProfile) }
                            .disabled(model.users?.canAddUsers != true)
                    }
                }
                .fixedSize()
                .disabled(model.isChangingUsers)
                if let users = model.users, !users.canAddUsers {
                    Text("This device allows \(users.maximumUsers) \(users.maximumUsers == 1 ? "user" : "users").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isChangingUsers {
                    ProgressView().controlSize(.small)
                }
                RefreshButton { await model.loadUsers() }
            }
            .controlSize(.small)
            .padding(Spacing.medium)
        }
        .task { await model.loadUsers() }
        .alert(newUserKind?.title ?? "", isPresented: .isPresenting($newUserKind), presenting: newUserKind) { kind in
            TextField("Name", text: $newUserName)
            Button("Create") {
                switch kind {
                case .user: model.createUser(named: newUserName)
                case .workProfile: model.createWorkProfile(named: newUserName)
                }
            }
            .disabled(newUserName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: { kind in
            Text(
                kind == .user ? "Creates a new user on the device." : "Creates a managed profile for the current user.")
        }
        .confirmationDialog(
            "Remove “\(pendingRemoval?.name ?? "")”?",
            isPresented: .isPresenting($pendingRemoval),
            presenting: pendingRemoval
        ) { user in
            Button("Remove", role: .destructive) { model.removeUser(user) }
        } message: { _ in
            Text("The user's apps and data are deleted from the device.")
        }
    }

    private func begin(_ kind: NewUserKind) {
        newUserName = kind == .user ? "New user" : "Work"
        newUserKind = kind
    }

    @ViewBuilder
    private func actions(for user: DeviceUser, current: Int) -> some View {
        Button("Switch to \(user.name)") { model.switchToUser(user) }
            .disabled(user.id == current || user.isProfile)
        Button("Remove…", role: .destructive) { pendingRemoval = user }
            .disabled(!model.canRemove(user))
    }
}

private struct UserRow: View {
    let user: DeviceUser
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: user.isProfile ? Symbol.workProfile : Symbol.user)
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(user.name)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Current user")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = ["ID \(user.id)"]
        if user.isProfile { parts.append("Work profile") }
        if user.isRunning { parts.append("Running") }
        return parts.joined(separator: " · ")
    }
}
