import XCTest
@testable import GymCore

final class ProvisioningProfileTests: XCTestCase {
    private func profileData(entitlements: String) -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Name</key><string>GymTracker profile</string>
            <key>TeamName</key><string>Personal Team</string>
            <key>ExpirationDate</key><date>2026-11-20T10:00:00Z</date>
            <key>Entitlements</key>
            <dict>
                <key>application-identifier</key><string>ABCDE12345.com.example.gym</string>
                \(entitlements)
            </dict>
        </dict>
        </plist>
        """
        // Bytes binarios alrededor, como en la envoltura CMS real.
        return Data([0x30, 0x82, 0x0F, 0x00]) + Data(xml.utf8) + Data([0xA0, 0x82, 0x00])
    }

    func testDetectsHealthKitEntitlement() throws {
        let profile = try ProvisioningProfile.parse(profileData(entitlements: """
            <key>com.apple.developer.healthkit</key><true/>
            <key>com.apple.developer.healthkit.access</key><array/>
            """))
        XCTAssertTrue(profile.grantsHealthKit)
        XCTAssertEqual(profile.name, "GymTracker profile")
        XCTAssertEqual(profile.teamName, "Personal Team")
        XCTAssertEqual(profile.appIdentifier, "ABCDE12345.com.example.gym")
        XCTAssertEqual(profile.expirationDate, Date(timeIntervalSince1970: 1_795_168_800))
        XCTAssertEqual(profile.entitlementKeys, [
            "application-identifier",
            "com.apple.developer.healthkit",
            "com.apple.developer.healthkit.access",
        ])
    }

    func testProfileWithoutHealthKit() throws {
        let profile = try ProvisioningProfile.parse(profileData(entitlements: """
            <key>get-task-allow</key><true/>
            """))
        XCTAssertFalse(profile.grantsHealthKit)
        XCTAssertEqual(profile.entitlementKeys, ["application-identifier", "get-task-allow"])
    }

    func testHealthKitSetToFalseIsNotGranted() throws {
        let profile = try ProvisioningProfile.parse(profileData(entitlements: """
            <key>com.apple.developer.healthkit</key><false/>
            """))
        XCTAssertFalse(profile.grantsHealthKit)
    }

    func testRejectsDataWithoutPlist() {
        XCTAssertThrowsError(try ProvisioningProfile.parse(Data([0x30, 0x82, 0x01]))) { error in
            XCTAssertEqual(error as? ProvisioningProfile.ParseError, .plistNotFound)
        }
    }

    func testRejectsBrokenPlist() {
        let data = Data("<?xml version=\"1.0\"?><plist><dict><key>Name</plist>".utf8)
        XCTAssertThrowsError(try ProvisioningProfile.parse(data)) { error in
            XCTAssertEqual(error as? ProvisioningProfile.ParseError, .invalidPlist)
        }
    }
}
