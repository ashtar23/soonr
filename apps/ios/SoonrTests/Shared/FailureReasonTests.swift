import Foundation
import Testing

@testable import Soonr

struct FailureReasonTests {
    @Test(arguments: [
        (URLError.Code.notConnectedToInternet, FailureReason.offline),
        (.networkConnectionLost, .offline),
        (.dataNotAllowed, .offline),
        (.timedOut, .timedOut),
        (.cannotConnectToHost, .timedOut),
    ])
    func transportErrorsBecomeConnectionReasons(code: URLError.Code, expected: FailureReason) {
        #expect(FailureReason(URLError(code)) == expected)
    }

    @Test
    func aRejectedSessionIsUnauthorized() {
        #expect(FailureReason(APIError.unauthorized) == .unauthorized)
    }

    @Test
    func aServerFailureKeepsItsMessage() {
        let error = APIError.requestFailed(statusCode: 500, message: "Database unavailable.")

        #expect(FailureReason(error) == .server(message: "Database unavailable."))
    }

    @Test(arguments: [APIError.invalidPayload, .invalidResponse, .invalidRequest])
    func unusableResponsesAreUnreadable(error: APIError) {
        #expect(FailureReason(error) == .unreadable)
    }

    /// Retrying a rejected session repeats the same failure; every other
    /// reason can plausibly succeed on a second attempt.
    @Test
    func onlyARejectedSessionIsNotWorthRetrying() {
        #expect(FailureReason.unauthorized.isRetryable == false)
        #expect(FailureReason.offline.isRetryable)
        #expect(FailureReason.timedOut.isRetryable)
        #expect(FailureReason.unreadable.isRetryable)
        #expect(FailureReason.server(message: "Boom").isRetryable)
    }

    @Test
    func anUnrecognisedErrorKeepsItsDescription() {
        #expect(FailureReason(SampleError.broken) == .unknown(message: "Something broke."))
    }
}

private enum SampleError: Error, LocalizedError {
    case broken

    var errorDescription: String? {
        "Something broke."
    }
}
