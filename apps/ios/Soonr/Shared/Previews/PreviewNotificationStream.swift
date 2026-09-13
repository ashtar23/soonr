#if DEBUG

    /// Connects to nothing and never yields, so previews render the screens
    /// rather than a connection.
    struct PreviewNotificationStream: NotificationStreaming {
        func notificationEvents() -> AsyncStream<NotificationStreamEvent> {
            AsyncStream { _ in }
        }
    }

#endif
