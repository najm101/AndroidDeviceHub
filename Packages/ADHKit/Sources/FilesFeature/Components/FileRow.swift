import DesignSystem
import DeviceDomain
import SwiftUI

struct FileRow: View {
    let file: RemoteFile

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: icon)
                .foregroundStyle(file.isFolderLike ? Color.accentColor : Color.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch file.kind {
        case .directory: Symbol.folder
        case .symbolicLink: Symbol.symlink
        case .file, .other: Symbol.file
        }
    }

    private var detail: String {
        let date = file.modified.formatted(date: .abbreviated, time: .shortened)
        switch file.kind {
        case .file: return "\(file.size.formatted(.byteCount(style: .file))) · \(date)"
        case .symbolicLink: return "Link · \(date)"
        case .directory, .other: return date
        }
    }
}
