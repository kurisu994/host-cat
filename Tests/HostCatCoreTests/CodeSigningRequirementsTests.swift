import XCTest
@testable import HostCatCore

final class CodeSigningRequirementsTests: XCTestCase {
    func testAppRequirementIncludesAnchorIdentifierAndTeamID() {
        let requirement = HostCatCodeSigningRequirements.appRequirement(teamIdentifier: "ABCDE12345")

        XCTAssertEqual(
            requirement,
            "anchor apple generic and identifier \"com.hostcat.app\" and certificate leaf[subject.OU] = \"ABCDE12345\""
        )
    }

    func testHelperRequirementIncludesAnchorIdentifierAndTeamID() {
        let requirement = HostCatCodeSigningRequirements.helperRequirement(teamIdentifier: "ABCDE12345")

        XCTAssertEqual(
            requirement,
            "anchor apple generic and identifier \"com.hostcat.helper\" and certificate leaf[subject.OU] = \"ABCDE12345\""
        )
    }
}
