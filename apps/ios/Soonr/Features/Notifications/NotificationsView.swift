import SwiftUI

struct NotificationsView: View {
    var body: some View {
        NavigationStack {
            PlaceholderScreen(
                icon: "bell",
                title: "No notifications yet",
                description: "Release changes and reminders for watched games will appear here."
            )
            .navigationTitle("Notifications")
        }
    }
}

#Preview {
    NotificationsView()
}
