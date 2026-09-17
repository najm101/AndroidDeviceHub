import AppKit
import DesignSystem
import DeviceDomain
public import SwiftUI
import UniformTypeIdentifiers

/// Inspector ▸ Reports: crashes and ANRs, the Logcat window and bug reports.
public struct ReportsInspectorView: View {
    @Bindable private var model: ReportsModel
    @State private var exportItem: ExportItem?

    public init(model: ReportsModel) {
        self.model = model
    }

    public var body: some View {
        if let reason = model.availability.reason {
            UnavailableHint("Reports", systemImage: Symbol.reports, reason: reason)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            diagnostics
            Divider()
            if let error = model.errorMessage {
                ErrorBanner(error) { model.errorMessage = nil }
                    .padding(Spacing.medium)
            }
            crashHeader
            crashList
        }
        .task { await model.load() }
        .sheet(item: $model.selectedReport) { report in
            CrashReportDetail(report: report) {
                exportItem = ExportItem(text: report.text, fileName: ReportsModel.exportFileName(for: report))
            }
        }
        .fileExporter(
            isPresented: .isPresenting($exportItem),
            item: exportItem?.text,
            contentTypes: [.plainText],
            defaultFilename: exportItem?.fileName
        ) { result in
            if case let .failure(error) = result {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack {
                Button("Logcat", systemImage: Symbol.logcat, action: model.openLogcat)
                    .help("Open the live device log in a window")
                Spacer()
                Button("Bug Report", systemImage: Symbol.bugReport, action: model.startBugReport)
                    .disabled(isBugReportRunning)
                    .help("Collect a full bug report zip from the device")
            }
            switch model.bugReport {
            case .idle:
                EmptyView()
            case let .running(progress):
                TransferRow(
                    "Collecting bug report…", fraction: progress,
                    detail: "This usually takes a minute or two.", onCancel: model.cancelBugReport)
            case let .finished(url):
                HStack {
                    Image(systemName: Symbol.success)
                        .foregroundStyle(.green)
                    Text("Saved \(url.lastPathComponent)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Show in Finder", action: model.revealBugReport)
                        .buttonStyle(.borderless)
                    Button("Dismiss", systemImage: "xmark", action: model.dismissBugReport)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
                .font(.callout)
            }
        }
        .controlSize(.small)
        .padding(Spacing.medium)
    }

    private var isBugReportRunning: Bool {
        if case .running = model.bugReport { return true }
        return false
    }

    private var crashHeader: some View {
        HStack {
            Text("Crashes and ANRs")
                .font(.headline)
            Spacer()
            Menu("More", systemImage: Symbol.more) {
                Button("Export All…") {
                    exportItem = ExportItem(
                        text: model.exportText(for: model.visibleReports),
                        fileName: ReportsModel.exportFileName(for: nil))
                }
                .disabled(model.visibleReports.isEmpty)
                Divider()
                Button("Clear", action: model.clear)
                    .disabled(model.visibleReports.isEmpty)
                if model.hiddenCount > 0 {
                    Button("Show \(model.hiddenCount) Cleared", action: model.showAll)
                }
            }
            .labelStyle(.iconOnly)
            .menuIndicator(.hidden)
            .fixedSize()
            Button("Refresh", systemImage: Symbol.refresh) {
                Task { await model.load() }
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.small)
    }

    private var crashList: some View {
        List(model.visibleReports) { report in
            Button {
                model.selectedReport = report
            } label: {
                CrashRow(report: report)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.inset)
        .overlay {
            if model.isLoading {
                ProgressView()
            } else if model.visibleReports.isEmpty {
                ContentUnavailableView(
                    "No Crashes", systemImage: Symbol.success,
                    description: Text("App crashes and “not responding” reports appear here."))
            }
        }
    }
}

struct ExportItem: Identifiable {
    let id = UUID()
    var text: String
    var fileName: String
}

private struct CrashRow: View {
    let report: CrashReport

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            Image(systemName: report.kind == .appNotResponding ? Symbol.hang : Symbol.crash)
                .foregroundStyle(report.kind == .appNotResponding ? .orange : .red)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(report.process ?? report.kind.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(report.date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(report.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct CrashReportDetail: View {
    let report: CrashReport
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(report.process ?? report.kind.title)
                    .font(.title3.weight(.semibold))
                Text(
                    "\(report.kind.title) · \(report.date.formatted(date: .abbreviated, time: .standard)) · \(report.tag)"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(Spacing.large)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                Text(report.text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(Spacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.text, forType: .string)
                }
                Button("Export…", action: onExport)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Spacing.large)
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 420, idealHeight: 560)
    }
}
