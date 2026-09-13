import Foundation

/// Reads the `aps-environment` the app was actually signed with.
///
/// A development-signed build carries `development` and its tokens are only
/// deliverable through the APNs sandbox; a distributed one carries
/// `production`. Nothing else in the bundle says which, and the build
/// configuration is not a reliable stand-in.
enum ProvisioningProfile {
    static func apsEnvironment(
        bundle: Bundle = .main
    ) -> PushEnvironment? {
        guard
            let url = bundle.url(
                forResource: "embedded",
                withExtension: "mobileprovision"
            ),
            let contents = try? Data(contentsOf: url)
        else {
            // The Simulator installs no profile. Its tokens are sandbox ones.
            return nil
        }

        return apsEnvironment(inProfile: contents)
    }

    /// The profile is CMS-signed, with a plist in the middle of it. Parsing the
    /// signature to reach that plist would need Security framework work for a
    /// value that is plainly readable, so this finds the plist by its own
    /// boundaries instead.
    static func apsEnvironment(inProfile contents: Data) -> PushEnvironment? {
        guard let plist = embeddedPlist(in: contents),
            let profile = try? PropertyListSerialization.propertyList(
                from: plist,
                format: nil
            ) as? [String: Any],
            let entitlements = profile["Entitlements"] as? [String: Any],
            let environment = entitlements["aps-environment"] as? String
        else {
            return nil
        }

        return environment == "production" ? .production : .sandbox
    }

    private static func embeddedPlist(in contents: Data) -> Data? {
        guard let start = contents.range(of: Data("<?xml".utf8)),
            let end = contents.range(
                of: Data("</plist>".utf8),
                options: .backwards
            )
        else {
            return nil
        }

        return contents[start.lowerBound..<end.upperBound]
    }
}
