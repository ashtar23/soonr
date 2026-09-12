import SwiftUI

struct FailureView: View {
    let title: String
    let reason: FailureReason
    var retry: (() async -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(reason.message)
        } actions: {
            if let retry, reason.isRetryable {
                Button("Try Again", systemImage: "arrow.clockwise") {
                    Task {
                        await retry()
                    }
                }
            }
        }
    }

    private var icon: String {
        switch reason {
        case .offline, .timedOut:
            "wifi.exclamationmark"
        case .unauthorized:
            "person.crop.circle.badge.exclamationmark"
        case .server, .unknown, .unreadable:
            "exclamationmark.triangle"
        }
    }
}

#Preview("Offline") {
    FailureView(title: "Watchlist unavailable", reason: .offline, retry: {})
}

#Preview("Session expired") {
    FailureView(title: "Watchlist unavailable", reason: .unauthorized, retry: {})
}

#Preview("Server") {
    FailureView(
        title: "Details unavailable",
        reason: .server(message: "Database unavailable."),
        retry: {}
    )
}
