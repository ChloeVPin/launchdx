import Foundation
import XCTest
#if os(macOS)
import Darwin
#endif
@testable import LaunchDXCore

final class BundleInspectorTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testValidBundlePassesStructureChecks() throws {
        let app = try makeApp(
            name: "Valid.app",
            plist: [
                "CFBundleIdentifier": "dev.launchdx.valid",
                "CFBundleExecutable": "Valid"
            ],
            executable: "Valid"
        )

        let report = BundleInspector(performSecurityChecks: false).inspect(pathString: app.path)

        XCTAssertEqual(report.inspectionStatus, .complete)
        XCTAssertEqual(report.launchStatus, .inconclusive)
        XCTAssertEqual(report.bundle?.bundleIdentifier, "dev.launchdx.valid")
        XCTAssertEqual(report.bundle?.executableName, "Valid")
        XCTAssertTrue(report.bundle?.executableExists == true)
        XCTAssertTrue(report.bundle?.executableIsRegularFile == true)
        XCTAssertEqual(report.findings.map(\.id), ["macho.arm64-supported"])
        XCTAssertEqual(report.bundle?.macho?.architectures, ["arm64"])
        XCTAssertEqual(report.exitCode, .ok)
        XCTAssertEqual(report.diagnosis.classification, .inconclusive)
    }

    func testInconclusiveSignatureMakesReportUnavailable() throws {
        let app = try makeApp(
            name: "InconclusiveSignature.app",
            plist: [
                "CFBundleIdentifier": "dev.launchdx.inconclusive",
                "CFBundleExecutable": "InconclusiveSignature"
            ],
            executable: "InconclusiveSignature"
        )
        let security = SecurityInspection(
            signature: SignatureInspection(state: .inconclusive),
            notarization: NotarizationInspection(staple: .valid),
            gatekeeper: GatekeeperInspection(result: .accepted),
            quarantine: QuarantineInspection(present: false)
        )
        let finding = Finding(
            id: "signature.unavailable",
            status: .inconclusive,
            severity: .error,
            confidence: .low,
            title: "Code signature evidence is inconclusive",
            explanation: "The signing sources did not agree or did not provide enough evidence."
        )
        let report = BundleInspector(
            securityInspectionProvider: { _ in (security, [], [finding]) }
        ).inspect(pathString: app.path)

        XCTAssertEqual(report.inspectionStatus, .securityUnavailable)
        XCTAssertEqual(report.launchStatus, .inconclusive)
        XCTAssertEqual(report.exitCode, .unavailable)
        XCTAssertNotEqual(report.diagnosis.classification, .clean)
    }

    func testMissingTargetUsesNoInputExitCode() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Missing.app")

        let report = BundleInspector().inspect(pathString: path.path)

        XCTAssertEqual(report.inspectionStatus, .targetMissing)
        XCTAssertEqual(report.diagnosis.classification, .unavailableEvidence)
        XCTAssertEqual(report.exitCode, .noInput)
    }

    func testContentsPathMustBeDirectory() throws {
        let app = try makeEmptyApp(name: "ContentsFile.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.removeItem(at: contents)
        try Data("not a directory".utf8).write(to: contents)

        let report = BundleInspector(performSecurityChecks: false).inspect(pathString: app.path)

        XCTAssertEqual(report.findings.first?.id, "bundle.contents-not-directory")
        XCTAssertEqual(report.exitCode, .blocked)
    }

    func testMissingInfoPlistIsAConfirmedBlocker() throws {
        let app = try makeEmptyApp(name: "BrokenBundle.app")
        let report = BundleInspector(performSecurityChecks: false).inspect(pathString: app.path)

        XCTAssertEqual(report.launchStatus, .blocked)
        XCTAssertEqual(report.findings.first?.id, "bundle.info-plist-missing")
        XCTAssertEqual(report.diagnosis.classification, .confirmedBlocker)
        XCTAssertEqual(report.exitCode, .blocked)
    }

    func testMalformedInfoPlistIsAConfirmedBlocker() throws {
        let app = try makeEmptyApp(name: "Malformed.app")
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        try Data("not a plist".utf8).write(to: infoURL)

        let report = BundleInspector(performSecurityChecks: false).inspect(pathString: app.path)

        XCTAssertEqual(report.findings.first?.id, "bundle.info-plist-invalid")
        XCTAssertEqual(report.exitCode, .blocked)
    }

    func testMissingBundleIdentifierIsAConfirmedBlocker() throws {
        let app = try makeApp(
            name: "MissingIdentifier.app",
            plist: ["CFBundleExecutable": "MissingIdentifier"],
            executable: "MissingIdentifier"
        )

        let report = BundleInspector(performSecurityChecks: false).inspect(pathString: app.path)

        XCTAssertEqual(report.findings.first?.id, "bundle.identifier-missing")
        XCTAssertEqual(report.exitCode, .blocked)
    }

    func testDirectoryAtExecutablePathIsAConfirmedBlocker() throws {
        let app = try makeApp(
            name: "DirectoryExecutable.app",
            plist: [
                "CFBundleIdentifier": "dev.launchdx.directory",
                "CFBundleExecutable": "DirectoryExecutable"
            ],
            executable: nil
        )
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents/MacOS/DirectoryExecutable"),
            withIntermediateDirectories: true
        )

        let report = BundleInspector(performSecurityChecks: false).inspect(pathString: app.path)

        XCTAssertEqual(report.findings.first?.id, "bundle.executable-not-regular-file")
        XCTAssertEqual(report.bundle?.executableIsRegularFile, false)
        XCTAssertEqual(report.exitCode, .blocked)
    }

    func testUnreadableExecutableIsPermissionLimited() throws {
        let app = try makeApp(
            name: "UnreadableExecutable.app",
            plist: [
                "CFBundleIdentifier": "dev.launchdx.unreadable",
                "CFBundleExecutable": "UnreadableExecutable"
            ],
            executable: "UnreadableExecutable"
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: app.appendingPathComponent("Contents/MacOS/UnreadableExecutable").path
        )

        let report = BundleInspector(performSecurityChecks: false).inspect(pathString: app.path)

        #if os(macOS)
        if geteuid() == 0 {
            throw XCTSkip("Permission behavior is not observable when tests run as root.")
        }
        #endif
        XCTAssertEqual(report.findings.first?.id, "bundle.executable-unreadable")
        XCTAssertEqual(report.findings.first?.status, .unavailable)
        XCTAssertEqual(report.inspectionStatus, .permissionLimited)
        XCTAssertEqual(report.exitCode, .noPermission)
    }

    func testUnreadableMachOReadIsPermissionLimited() throws {
        let app = try makeApp(
            name: "UnreadableMachO.app",
            plist: [
                "CFBundleIdentifier": "dev.launchdx.unreadable-macho",
                "CFBundleExecutable": "UnreadableMachO"
            ],
            executable: "UnreadableMachO"
        )
        let executableURL = app.appendingPathComponent("Contents/MacOS/UnreadableMachO")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: executableURL.path)

        let report = BundleInspector(performSecurityChecks: false).inspect(pathString: app.path)

        #if os(macOS)
        if geteuid() == 0 {
            throw XCTSkip("Permission behavior is not observable when tests run as root.")
        }
        #endif
        XCTAssertEqual(report.findings.first?.id, "bundle.executable-unreadable")
        XCTAssertEqual(report.inspectionStatus, .permissionLimited)
        XCTAssertEqual(report.exitCode, .noPermission)
    }

    func testMissingExecutableIsAConfirmedBlocker() throws {
        let app = try makeApp(
            name: "MissingExecutable.app",
            plist: [
                "CFBundleIdentifier": "dev.launchdx.missing",
                "CFBundleExecutable": "Missing"
            ],
            executable: nil
        )

        let report = BundleInspector(performSecurityChecks: false).inspect(pathString: app.path)

        XCTAssertEqual(report.findings.first?.id, "bundle.executable-missing")
        XCTAssertEqual(report.diagnosis.primaryFindingID, "bundle.executable-missing")
        XCTAssertEqual(report.exitCode, .blocked)
    }

    private func makeEmptyApp(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("launchdx-\(UUID().uuidString)", isDirectory: true)
        let app = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(root)
        return app
    }

    private func makeApp(
        name: String,
        plist: [String: String],
        executable: String?
    ) throws -> URL {
        let app = try makeEmptyApp(name: name)
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: app.appendingPathComponent("Contents/Info.plist"))

        if let executable {
            let macOSDirectory = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
            try FileManager.default.createDirectory(at: macOSDirectory, withIntermediateDirectories: true)
            try minimalArm64MachO().write(to: macOSDirectory.appendingPathComponent(executable))
        }
        return app
    }

    private func minimalArm64MachO() -> Data {
        Data([
            0xcf, 0xfa, 0xed, 0xfe,
            0x0c, 0x00, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x00,
            0x02, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00
        ])
    }
}
