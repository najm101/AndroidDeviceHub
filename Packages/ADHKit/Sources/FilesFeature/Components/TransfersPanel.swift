import DesignSystem
import DeviceDomain
import SwiftUI

/// Upload and download progress, and the last finished download, under the file list.
struct TransfersPanel: View {
    let model: FilesModel

    var body: some View {
        if !model.transfers.isEmpty || model.lastDownload != nil {
            VStack(alignment: .leading, spacing: Spacing.small) {
                ForEach(model.transfers) { transfer in
                    TransferRow(
                        "\(transfer.direction == .upload ? "Uploading" : "Downloading") \(transfer.name)",
                        fraction: transfer.progress?.fraction,
                        detail: transfer.progress.map(Self.detail),
                        onCancel: { model.cancel(transfer) }
                    )
                }
                if let url = model.lastDownload, model.transfers.isEmpty {
                    HStack {
                        Image(systemName: Symbol.success)
                            .foregroundStyle(.green)
                        Text("Downloaded \(url.lastPathComponent)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Show in Finder", action: model.revealLastDownload)
                            .buttonStyle(.borderless)
                        Button("Dismiss", systemImage: "xmark", action: model.dismissLastDownload)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                    .font(.callout)
                }
            }
            .padding(Spacing.medium)
            .background(.bar)
        }
    }

    private static func detail(_ progress: TransferProgress) -> String {
        let done = progress.completed.formatted(.byteCount(style: .file))
        let total = progress.total.formatted(.byteCount(style: .file))
        return "\(done) of \(total)"
    }
}
