import Foundation
import Foundations
import Testing

struct ProcessEnvironmentTests {
    let env = ProcessEnvironment(values: ["A": "  ", "B": "/x"], homeDirectory: URL(filePath: "/Users/me"))

    @Test func treatsBlankValuesAsUnset() {
        #expect(env["A"] == nil)
        #expect(env["B"] == "/x")
        #expect(env["C"] == nil)
    }

    @Test func expandsTilde() {
        #expect(
            env.url(forPath: "~/Library/Android/sdk").path(percentEncoded: false) == "/Users/me/Library/Android/sdk/")
        #expect(env.url(forPath: "/abs").path(percentEncoded: false) == "/abs/")
    }
}

struct KeyValueStoreTests {
    @Test func storesValues() {
        let store = InMemoryKeyValueStore()
        store.set("x", forKey: "s")
        store.set(true, forKey: "b")
        store.set(3, forKey: "i")
        #expect(store.string(forKey: "s") == "x")
        #expect(store.bool(forKey: "b"))
        #expect(store.integer(forKey: "i") == 3)
        store.set(nil as String?, forKey: "s")
        #expect(store.string(forKey: "s") == nil)
    }
}

struct ProcessRunnerTests {
    @Test func reportsFailureExitCodes() async throws {
        try await ProcessRunner.run(URL(filePath: "/usr/bin/true"), arguments: [])
        await #expect(throws: ProcessRunner.Failure.self) {
            try await ProcessRunner.run(URL(filePath: "/usr/bin/false"), arguments: [])
        }
    }

    @Test func launchReportsExit() async throws {
        let exit = await withCheckedContinuation { continuation in
            do {
                try ProcessRunner.launch(URL(filePath: "/bin/sh"), arguments: ["-c", "exit 7"]) {
                    continuation.resume(returning: $0)
                }
            } catch {
                continuation.resume(returning: -1)
            }
        }
        #expect(exit == 7)
    }

    @Test func freePortIsUsable() throws {
        let port = try PortAllocator.freeLoopbackPort()
        #expect(port > 1024)
    }

    @Test func currentProcessIsAlive() {
        #expect(ProcessStatus.isAlive(getpid()))
        #expect(!ProcessStatus.isAlive(0))
    }
}
