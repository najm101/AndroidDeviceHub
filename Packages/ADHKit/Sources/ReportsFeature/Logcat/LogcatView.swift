import AppKit
import DesignSystem
import DeviceDomain
public import SwiftUI

/// The Logcat window: live device log with level, text and app filters.
public struct LogcatView: View {
    @Bindable private var model: LogcatModel
    @State private var selection: Set<LogEntry.ID> = []

    public init(model: LogcatModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            switch model.state {
            case let .waiting(reason), let .failed(reason):
                HStack(spacing: Spacing.small) {
                    ProgressView().controlSize(.small)
                    Text(reason)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.callout)
                .padding(Spacing.medium)
            case .idle, .streaming:
                EmptyView()
            }
            ScrollViewReader { proxy in
                Table(model.visibleEntries, selection: $selection) {
                    TableColumn("Time") { entry in
                        Text(
                            entry.date,
                            format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second().secondFraction(
                                .fractional(3))
                        )
                        .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 96, max: 110)
                    TableColumn("PID") { entry in
                        Text(verbatim: "\(entry.pid)")
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 40, ideal: 50, max: 64)
                    TableColumn("") { entry in
                        Text(entry.level.letter)
                            .fontWeight(.semibold)
                            .foregroundStyle(Self.color(for: entry.level))
                    }
                    .width(16)
                    TableColumn("Tag") { entry in
                        Text(entry.tag)
                            .lineLimit(1)
                    }
                    .width(min: 80, ideal: 140, max: 260)
                    TableColumn("Message") { entry in
                        Text(entry.message)
                            .lineLimit(2)
                            .help(entry.message)
                            .foregroundStyle(entry.level >= .warning ? Self.color(for: entry.level) : .primary)
                    }
                    .width(min: 240)
                }
                .font(.system(.callout, design: .monospaced))
                .contextMenu(forSelectionType: LogEntry.ID.self) { ids in
                    Button("Copy") { copy(ids) }
                }
                .onCopyCommand {
                    [NSItemProvider(object: model.text(for: selection) as NSString)]
                }
                .onChange(of: model.visibleEntries.last?.id) { _, last in
                    if model.followsTail, !model.isPaused, let last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .navigationTitle("Logcat — \(model.deviceName)")
        .navigationSubtitle("\(model.visibleEntries.count) of \(model.totalCount) entries")
        .searchable(text: $model.searchText, prompt: "Filter messages and tags")
        .toolbar { toolbar }
        .task { await model.run() }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem {
            Picker("App", selection: $model.packageFilter) {
                Text("All Apps").tag(String?.none)
                if !model.packages.isEmpty {
                    Divider()
                    ForEach(model.packages) { app in
                        Text(app.packageName).tag(Optional(app.packageName))
                    }
                }
            }
            .help("Show only messages from one installed app")
        }
        ToolbarItem {
            Picker("Level", selection: $model.minimumLevel) {
                ForEach(LogLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .help("Minimum level")
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Toggle(isOn: $model.followsTail) {
                Label("Follow", systemImage: "arrow.down.to.line")
            }
            .help("Keep the newest messages in view")
            Button(model.isPaused ? "Resume" : "Pause", systemImage: model.isPaused ? "play.fill" : "pause.fill") {
                model.togglePause()
            }
            .help(model.isPaused ? "Resume" : "Pause")
            Button("Clear", systemImage: "trash", action: model.clear)
                .help("Clear the window (the device log is kept)")
        }
    }

    private func copy(_ ids: Set<LogEntry.ID>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.text(for: ids), forType: .string)
    }

    static func color(for level: LogLevel) -> Color {
        switch level {
        case .verbose, .debug: .secondary
        case .info: .green
        case .warning: .orange
        case .error, .fatal: .red
        }
    }
}
