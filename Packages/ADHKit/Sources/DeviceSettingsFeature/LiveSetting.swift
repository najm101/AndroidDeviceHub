import Foundation
import Observation

/// One device value shown in the inspector: read when its section opens, written as soon as it changes.
@MainActor
@Observable
final class LiveSetting<Value: Equatable & Sendable> {
    /// The last value read from, or accepted by, the device.
    private(set) var value: Value?
    private(set) var isLoading = false

    @ObservationIgnored private let read: @MainActor () async throws -> Value
    @ObservationIgnored private let write: @MainActor (Value) async throws -> Void
    @ObservationIgnored private let report: (any Error) -> Void

    init(
        read: @escaping @MainActor () async throws -> Value,
        write: @escaping @MainActor (Value) async throws -> Void,
        report: @escaping (any Error) -> Void
    ) {
        self.read = read
        self.write = write
        self.report = report
    }

    func load() async {
        isLoading = value == nil
        defer { isLoading = false }
        do {
            value = try await read()
        } catch is CancellationError {
        } catch {
            report(error)
        }
    }

    /// Shows the new value right away and restores the old one if the device rejects it.
    func apply(_ newValue: Value) async {
        guard newValue != value else { return }
        let previous = value
        value = newValue
        do {
            try await write(newValue)
        } catch {
            value = previous
            report(error)
        }
    }
}
