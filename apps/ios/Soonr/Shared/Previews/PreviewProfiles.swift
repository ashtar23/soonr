import Foundation

#if DEBUG

    /// Keeps whatever it is told, so previews can show a profile being edited
    /// without a server to edit it on.
    actor PreviewProfiles: ProfileEditing {
        private var stored: UserProfile

        init(_ profile: UserProfile = .preview) {
            stored = profile
        }

        func profile(userID _: String) async throws -> ProfileOverview {
            ProfileOverview(profile: stored, counts: .preview)
        }

        func updateProfile(_ edit: ProfileEdit) async throws -> UserProfile {
            stored = UserProfile(
                userID: stored.userID,
                username: edit.username.isEmpty ? nil : edit.username,
                displayName: edit.displayName.isEmpty ? nil : edit.displayName,
                avatarURL: stored.avatarURL,
                bio: edit.bio.isEmpty ? nil : edit.bio,
                watchlistVisibility: edit.watchlistVisibility
            )
            return stored
        }
    }

    extension ProfileCounts {
        static let preview = ProfileCounts(friends: 5, followers: 12, following: 8)
    }

    extension UserProfile {
        static let preview = UserProfile(
            userID: "preview-user",
            username: "reader",
            displayName: "A Reader",
            avatarURL: nil,
            bio: "Tracking more games than I will ever play.",
            watchlistVisibility: .friends
        )

        /// The state the endpoint exists for: an account signup never asked a
        /// username of.
        static let previewUnnamed = UserProfile(
            userID: "preview-user",
            username: nil,
            displayName: nil,
            avatarURL: nil,
            bio: nil,
            watchlistVisibility: .friends
        )
    }

#endif
