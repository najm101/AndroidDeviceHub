public import GRPCCore
public import GRPCNIOTransportHTTP2

/// A connection to one running emulator's gRPC endpoint.
///
/// Every call carries `authorization: Bearer <token>` from the emulator's discovery file.
public final class EmulatorClient: Sendable {
    public typealias Transport = HTTP2ClientTransport.Posix
    public typealias Controller = Android_Emulation_Control_EmulatorController.Client<Transport>
    public typealias Snapshots = Android_Emulation_Control_SnapshotService.Client<Transport>

    public let controller: Controller
    public let snapshots: Snapshots
    private let client: GRPCClient<Transport>

    /// Raw frames can be large when shared memory isn't available.
    public static let largeMessageOptions: CallOptions = {
        var options = CallOptions.defaults
        options.maxResponseMessageBytes = 64 * 1024 * 1024
        return options
    }()

    public init(port: Int, token: String?) throws {
        let transport = try HTTP2ClientTransport.Posix(
            target: .ipv4(address: "127.0.0.1", port: port),
            transportSecurity: .plaintext,
            config: .defaults { config in
                config.http2.maxFrameSize = 1 << 20
            }
        )
        let interceptors: [any ClientInterceptor] = token.map { [BearerTokenInterceptor(token: $0)] } ?? []
        let client = GRPCClient(transport: transport, interceptors: interceptors)
        self.client = client
        controller = Controller(wrapping: client)
        snapshots = Snapshots(wrapping: client)
        Task.detached {
            try? await client.runConnections()
        }
    }

    public func close() {
        client.beginGracefulShutdown()
    }

    deinit {
        client.beginGracefulShutdown()
    }
}

struct BearerTokenInterceptor: ClientInterceptor {
    let token: String

    func intercept<Input: Sendable, Output: Sendable>(
        request: StreamingClientRequest<Input>,
        context: ClientContext,
        next: (StreamingClientRequest<Input>, ClientContext) async throws -> StreamingClientResponse<Output>
    ) async throws -> StreamingClientResponse<Output> {
        var request = request
        request.metadata.replaceOrAddString("Bearer \(token)", forKey: "authorization")
        return try await next(request, context)
    }
}
