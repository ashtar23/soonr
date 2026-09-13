import Foundation
import Testing

@testable import Soonr

/// The value decides which APNs host the server sends to, and getting it
/// wrong reads as a dead device: APNs answers `BadDeviceToken` and delivery
/// deletes the token.
struct ProvisioningProfileTests {
    @Test(arguments: [
        ("development", PushEnvironment.sandbox),
        ("production", PushEnvironment.production),
    ])
    func theSignedEntitlementDecidesTheEnvironment(
        entitlement: String,
        expected: PushEnvironment
    ) {
        let profile = signedProfile(apsEnvironment: entitlement)

        #expect(ProvisioningProfile.apsEnvironment(inProfile: profile) == expected)
    }

    /// A profile without the capability says nothing about push.
    @Test
    func aProfileWithoutTheEntitlementDecidesNothing() {
        let profile = signedProfile(apsEnvironment: nil)

        #expect(ProvisioningProfile.apsEnvironment(inProfile: profile) == nil)
    }

    @Test
    func somethingThatIsNotAProfileDecidesNothing() {
        let contents = Data("not a provisioning profile".utf8)

        #expect(ProvisioningProfile.apsEnvironment(inProfile: contents) == nil)
    }

    /// The real file wraps its plist in CMS signature bytes, which is why the
    /// plist is found by its own boundaries rather than by parsing.
    private func signedProfile(apsEnvironment: String?) -> Data {
        let entitlements =
            apsEnvironment.map {
                """
                        <key>aps-environment</key>
                        <string>\($0)</string>
                """
            } ?? ""

        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0">
            <dict>
                <key>Name</key>
                <string>Soonr Development</string>
                <key>Entitlements</key>
                <dict>
                    <key>application-identifier</key>
                    <string>ZP5VQ274FF.com.ashtar23.soonr.native</string>
            \(entitlements)
                </dict>
            </dict>
            </plist>
            """

        var contents = Data([0x30, 0x82, 0x0A, 0x0B])
        contents.append(Data(plist.utf8))
        contents.append(Data([0x00, 0x01, 0x02, 0x03]))
        return contents
    }
}
