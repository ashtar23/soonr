import Foundation
import Testing

@testable import Soonr

/// The keys here are a contract with `apps/api`, and a rename on either side
/// would otherwise show up only as a push that opens nothing.
struct OpenedPushNotificationTests {
    @Test
    func aPushOpensTheGameItNames() {
        let opened = OpenedPushNotifications.parse(
            userInfo: [
                "destinationTitleId": "rawg:662318",
                "notificationId": "notification-record:1",
            ],
            title: "Marvel's Wolverine"
        )

        #expect(
            opened?.destination
                == TitleDestination(
                    id: "rawg:662318",
                    name: "Marvel's Wolverine"
                ))
        #expect(opened?.notificationID == "notification-record:1")
    }

    @Test(
        arguments: [
            ["notificationId": "notification-1"],
            ["destinationTitleId": "rawg:1"],
            ["destinationTitleId": "", "notificationId": "notification-1"],
            [:],
        ] as [[String: String]])
    func aPushMissingWhatItPointsAtOpensNothing(payload: [String: String]) {
        let userInfo = payload.reduce(into: [AnyHashable: Any]()) { result, pair in
            result[pair.key] = pair.value
        }

        #expect(OpenedPushNotifications.parse(userInfo: userInfo, title: "Soonr") == nil)
    }

    /// Anything but a string here is a payload we did not send.
    @Test
    func aPayloadOfTheWrongShapeOpensNothing() {
        let opened = OpenedPushNotifications.parse(
            userInfo: ["destinationTitleId": 662_318, "notificationId": "notification-1"],
            title: "Soonr"
        )

        #expect(opened == nil)
    }
}
