import SwiftUI

struct PlaceholderScreen<Actions: View>: View {
    let icon: String
    let title: String
    let description: String
    @ViewBuilder let actions: Actions

    init(
        icon: String,
        title: String,
        description: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.actions = actions()
    }

    var body: some View {
        ScrollView {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                Text(description)
            } actions: {
                actions
            }
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center)
        }
    }
}

extension PlaceholderScreen where Actions == EmptyView {
    init(icon: String, title: String, description: String) {
        self.init(icon: icon, title: title, description: description) {
            EmptyView()
        }
    }
}
