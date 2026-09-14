import Foundation

/// One connection's worth of socket, behind a protocol so the reconnect and
/// handshake logic above it can be tested without a server.
protocol WebSocketChannel: Sendable {
    func send(_ text: String) async throws
    /// Suspends until the next message arrives, and throws when the connection
    /// ends — which is how the reader learns to reconnect.
    func receive() async throws -> String
    func cancel()
}

protocol WebSocketConnecting: Sendable {
    func connect(to url: URL) -> any WebSocketChannel
}

struct URLSessionWebSocketConnector: WebSocketConnecting {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(to url: URL) -> any WebSocketChannel {
        let task = session.webSocketTask(with: url)
        task.resume()
        return URLSessionWebSocketChannel(task: task)
    }
}

/// `URLSessionWebSocketTask` is a reference type Foundation does not mark
/// `Sendable`; it is documented as safe to use from any thread, which is what
/// this wrapper asserts and confines.
private final class URLSessionWebSocketChannel: WebSocketChannel, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    deinit {
        task.cancel(with: .goingAway, reason: nil)
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String {
        switch try await task.receive() {
        case let .string(text):
            return text
        case let .data(data):
            // The server only ever sends text; a binary frame is still readable
            // as one rather than being a reason to drop the connection.
            guard let text = String(data: data, encoding: .utf8) else {
                throw APIError.invalidPayload
            }

            return text
        @unknown default:
            throw APIError.invalidPayload
        }
    }

    func cancel() {
        task.cancel(with: .goingAway, reason: nil)
    }
}
