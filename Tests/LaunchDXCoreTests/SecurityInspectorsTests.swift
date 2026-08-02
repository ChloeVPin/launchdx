import Foundation
import XCTest
@testable import LaunchDXCore

final class SecurityInspectorsTests: XCTestCase {
    func testNonMacOSFallbacksAreUnavailableOrPortable() {
        let signature = SignatureInspector().inspect(path: "/tmp/example.app")
        let staple = NotarizationInspector().inspect(path: "/tmp/example.app")
        let gatekeeper = GatekeeperInspector().inspect(path: "/tmp/example.app")
        let quarantine = QuarantineInspector().inspect(path: "/tmp/example.app")

        #if os(macOS)
        XCTAssertNotNil(signature.0)
        XCTAssertNotNil(staple.0)
        XCTAssertNotNil(gatekeeper.0)
        XCTAssertNotNil(quarantine.0)
        #else
        XCTAssertEqual(signature.0.state, .unavailable)
        XCTAssertEqual(staple.0.staple, .unavailable)
        XCTAssertEqual(gatekeeper.0.result, .unavailable)
        XCTAssertFalse(quarantine.0.present)
        XCTAssertTrue(signature.1.contains { $0.id == "signature.unavailable" })
        #endif
    }

    func testJSONValuePreservesNestedEntitlementShapes() throws {
        let value = JSONValue.object([
            "enabled": .boolean(true),
            "groups": .array([.string("group.example")]),
            "count": .number(2)
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testQuarantineInspectionModelUsesDateAndRawValue() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let inspection = QuarantineInspection(
            present: true,
            flags: 0x0083,
            timestamp: date,
            agent: "com.apple.Safari",
            eventIdentifier: "event-id",
            rawValue: "0083;6553f100;com.apple.Safari;event-id"
        )
        XCTAssertEqual(inspection.flags, 0x0083)
        XCTAssertEqual(inspection.timestamp, date)
        XCTAssertEqual(inspection.agent, "com.apple.Safari")
    }

    #if os(macOS)
    func testMalformedQuarantineIsInconclusiveNotAbsent() {
        let runner = StubCommandRunner(results: [
            "/usr/bin/xattr": CommandResult(status: 0, stdout: "0083;not-a-timestamp;Safari", stderr: "", launchError: nil)
        ])
        let result = QuarantineInspector(runner: runner).inspect(path: "/tmp/example.app")

        XCTAssertTrue(result.0.present)
        XCTAssertEqual(result.2.first?.id, "quarantine.malformed")
        XCTAssertEqual(result.2.first?.status, .inconclusive)
    }

    func testGatekeeperEmptyFailureIsInconclusiveNotRejected() {
        let runner = StubCommandRunner(results: [
            "/usr/sbin/spctl --assess --type execute --verbose=4 --ignore-cache /tmp/example.app": CommandResult(status: 1, stdout: "", stderr: "", launchError: nil)
        ])
        let result = GatekeeperInspector(runner: runner).inspect(path: "/tmp/example.app")

        XCTAssertEqual(result.0.result, .inconclusive)
        XCTAssertEqual(result.2.first?.status, .inconclusive)
        XCTAssertNotEqual(result.2.first?.id, "gatekeeper.rejected")
    }

    func testStaplerCurrentMissingTicketWordingIsAbsent() {
        let runner = StubCommandRunner(results: [
            "/usr/bin/xcrun stapler validate /tmp/example.app": CommandResult(
                status: 1,
                stdout: "Processing: /tmp/example.app\\nexample.app does not have a ticket stapled to it.\\n",
                stderr: "",
                launchError: nil
            )
        ])
        let result = NotarizationInspector(runner: runner).inspect(path: "/tmp/example.app")

        XCTAssertEqual(result.0.staple, .absent)
        XCTAssertEqual(result.2.first?.status, .warning)
        XCTAssertTrue(result.2.first?.title.contains("No stapled") == true)
    }

    func testStrictSignatureFailureCannotBeOverriddenByAnotherSource() {
        let runner = StubCommandRunner(results: [
            "/usr/bin/codesign --verify --strict --verbose=4 /tmp/example.app": CommandResult(status: 1, stdout: "", stderr: "code object is invalid", launchError: nil),
            "/usr/bin/codesign -dvvv /tmp/example.app": CommandResult(status: 0, stdout: "", stderr: "Identifier=dev.example\nTeamIdentifier=TEAM123", launchError: nil),
            "/usr/bin/codesign -d --entitlements :- /tmp/example.app": CommandResult(status: 0, stdout: "", stderr: "", launchError: nil)
        ])
        let framework = StubSecurityFrameworkChecker(result: SecurityFrameworkResult(
            available: true,
            valid: true,
            identifier: "dev.example",
            teamID: "TEAM123",
            detail: "fake Security.framework accepted the code"
        ))
        let result = SignatureInspector(runner: runner, frameworkInspector: framework).inspect(path: "/tmp/example.app")

        XCTAssertEqual(result.0.state, .invalid)
        XCTAssertTrue(result.2.contains { $0.id == "signature.invalid" })
    }

    func testEmptyStrictFailureDoesNotBecomeValid() {
        let runner = StubCommandRunner(results: [
            "/usr/bin/codesign --verify --strict --verbose=4 /tmp/example.app": CommandResult(status: 1, stdout: "", stderr: "", launchError: nil),
            "/usr/bin/codesign -dvvv /tmp/example.app": CommandResult(status: 0, stdout: "", stderr: "Identifier=dev.example", launchError: nil),
            "/usr/bin/codesign -d --entitlements :- /tmp/example.app": CommandResult(status: 0, stdout: "", stderr: "", launchError: nil)
        ])
        let framework = StubSecurityFrameworkChecker(result: SecurityFrameworkResult(
            available: true,
            valid: true,
            identifier: "dev.example",
            teamID: nil,
            detail: "fake Security.framework accepted the code"
        ))
        let result = SignatureInspector(runner: runner, frameworkInspector: framework).inspect(path: "/tmp/example.app")

        XCTAssertEqual(result.0.state, .inconclusive)
        XCTAssertFalse(result.2.contains { $0.id == "signature.valid" })
    }

    func testUnavailableSecurityFrameworkAndToolDoesNotBecomeInvalid() {
        let runner = StubCommandRunner(results: [
            "/usr/bin/codesign --verify --strict --verbose=4 /tmp/example.app": CommandResult(status: -1, stdout: "", stderr: "", launchError: "tool unavailable"),
            "/usr/bin/codesign -dvvv /tmp/example.app": CommandResult(status: -1, stdout: "", stderr: "", launchError: "tool unavailable"),
            "/usr/bin/codesign -d --entitlements :- /tmp/example.app": CommandResult(status: -1, stdout: "", stderr: "", launchError: "tool unavailable")
        ])
        let framework = StubSecurityFrameworkChecker(result: SecurityFrameworkResult(
            available: true,
            valid: nil,
            identifier: nil,
            teamID: nil,
            detail: "fake Security.framework could not inspect the code"
        ))
        let result = SignatureInspector(runner: runner, frameworkInspector: framework).inspect(path: "/tmp/example.app")

        XCTAssertEqual(result.0.state, .unavailable)
        XCTAssertTrue(result.2.contains { $0.id == "signature.unavailable" })
        XCTAssertFalse(result.2.contains { $0.severity == .blocker })
    }

    private struct StubSecurityFrameworkChecker: SecurityFrameworkChecking {
        let result: SecurityFrameworkResult
        func inspect(path: String) -> SecurityFrameworkResult { result }
    }

    private final class StubCommandRunner: CommandRunning {
        private let results: [String: CommandResult]

        init(results: [String: CommandResult]) {
            self.results = results
        }

        func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult {
            let key = ([executable] + arguments).joined(separator: " ")
            return results[key] ?? CommandResult(status: 0, stdout: "", stderr: "", launchError: nil)
        }
    }
    #endif
}
