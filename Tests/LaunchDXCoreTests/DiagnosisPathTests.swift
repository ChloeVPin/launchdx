import Foundation
import XCTest
@testable import LaunchDXCore

final class DiagnosisPathTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testCleanAppDiagnosisHasNoBlocker() throws {
        let app = try makeApp(name: "Clean.app", executable: "Clean")
        let security = SecurityInspection(
            signature: SignatureInspection(state: .valid, identity: "Developer ID Application: Example", teamID: "TEAM123"),
            notarization: NotarizationInspection(staple: .valid),
            gatekeeper: GatekeeperInspection(result: .accepted),
            quarantine: QuarantineInspection(present: false)
        )
        let findings = [
            Finding(id: "signature.valid", status: .passed, severity: .information, confidence: .confirmed, title: "Code signature is valid", explanation: "The application passed strict code-signature validation."),
            Finding(id: "notarization.staple", status: .passed, severity: .information, confidence: .high, title: "Stapled notarization ticket is valid", explanation: "Ticket valid."),
            Finding(id: "gatekeeper.assessment", status: .passed, severity: .information, confidence: .confirmed, title: "Gatekeeper accepted the app", explanation: "accepted"),
            Finding(id: "quarantine.absent", status: .passed, severity: .information, confidence: .high, title: "Quarantine metadata is absent", explanation: "No quarantine.")
        ]
        let inspector = BundleInspector(securityInspectionProvider: { _ in (security, [], findings) })
        let report = DiagnosticPipeline(bundleInspector: inspector).diagnose(path: app.path)

        XCTAssertEqual(report.inspectionStatus, .complete)
        XCTAssertEqual(report.launchStatus, .clean)
        XCTAssertEqual(report.diagnosis.classification, .clean)
        XCTAssertEqual(report.exitCode, .ok)
        XCTAssertFalse(report.findings.contains { $0.severity == .blocker && $0.status == .failed })
        XCTAssertEqual(report.diagnosis.triggerFindingIDs, [])
        XCTAssertEqual(report.target.kind, .applicationBundle)
    }

    func testUnsignedAppIsAConfirmedBlockerOnTheShippedPath() throws {
        let app = try makeApp(name: "Unsigned.app", executable: "Unsigned")
        let report = DiagnosticPipeline().diagnose(path: app.path)

        #if os(macOS)
        XCTAssertEqual(report.launchStatus, .blocked)
        XCTAssertEqual(report.diagnosis.classification, .confirmedBlocker)
        XCTAssertEqual(report.exitCode, .blocked)
        let ids = report.findings.map(\.id)
        XCTAssertTrue(
            ids.contains("signature.unsigned") || ids.contains("signature.invalid"),
            "expected unsigned or invalid signature finding, got \(ids)"
        )
        if let primary = report.diagnosis.primaryFindingID {
            XCTAssertTrue(primary.hasPrefix("signature."), "primary finding should be the signature defect, got \(primary)")
        }
        #else
        XCTAssertEqual(report.launchStatus, .inconclusive)
        XCTAssertTrue(report.findings.contains { $0.id == "signature.unavailable" })
        #endif
    }

    func testQuarantineIsATriggerNotTheRootCause() throws {
        let app = try makeApp(name: "Quarantined.app", executable: "Quarantined")
        let security = SecurityInspection(
            signature: SignatureInspection(state: .invalid),
            notarization: NotarizationInspection(staple: .absent),
            gatekeeper: GatekeeperInspection(result: .rejected, detail: "rejected"),
            quarantine: QuarantineInspection(present: true, rawValue: "0083;00000000;Safari;00000000-0000-0000-0000-000000000001")
        )
        let findings = [
            Finding(
                id: "signature.invalid",
                status: .failed,
                severity: .blocker,
                confidence: .confirmed,
                title: "Code signature is invalid",
                explanation: "Strict signature validation rejected the application."
            ),
            Finding(
                id: "gatekeeper.assessment",
                status: .failed,
                severity: .blocker,
                confidence: .confirmed,
                title: "Gatekeeper rejected the app",
                explanation: "rejected"
            ),
            Finding(
                id: "quarantine.present",
                status: .warning,
                severity: .warning,
                confidence: .confirmed,
                title: "Quarantine metadata is present",
                explanation: "Quarantine is a trigger, not necessarily the defect."
            )
        ]
        let inspector = BundleInspector(securityInspectionProvider: { _ in (security, [], findings) })
        let report = DiagnosticPipeline(bundleInspector: inspector).diagnose(path: app.path)

        XCTAssertEqual(report.launchStatus, .blocked)
        XCTAssertEqual(report.diagnosis.classification, .confirmedBlocker)
        XCTAssertEqual(report.diagnosis.primaryFindingID, "signature.invalid")
        XCTAssertEqual(report.diagnosis.triggerFindingIDs, ["quarantine.present"])
        XCTAssertTrue(report.diagnosis.summary.contains("Quarantine triggered"))
        XCTAssertFalse(report.diagnosis.primaryFindingID == "quarantine.present")
        XCTAssertEqual(report.exitCode, .blocked)
    }

    func testDiskImageReusesAppDiagnosis() throws {
        #if os(macOS)
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/hdiutil") else {
            throw XCTSkip("hdiutil is not available")
        }
        let app = try makeApp(name: "Contained.app", executable: "Contained")
        let dmg = try makeDiskImage(containing: app, name: "Contained.dmg")
        let report = DiagnosticPipeline().diagnose(path: dmg.path)

        XCTAssertEqual(report.target.kind, .diskImage)
        XCTAssertEqual(report.target.inputPath, dmg.path)
        XCTAssertNotNil(report.container)
        XCTAssertEqual(report.container?.kind, .diskImage)
        XCTAssertEqual(report.container?.unpackMethod, "hdiutil-attach")
        XCTAssertEqual(report.container?.available, true)
        XCTAssertTrue(report.findings.contains { $0.id == "container.mounted" })
        XCTAssertTrue(report.findings.contains { $0.id == "container.app-found" })
        XCTAssertNotNil(report.container?.nestedApplicationPath)
        XCTAssertTrue(report.container?.nestedApplicationPath?.hasSuffix("Contained.app") == true)
        XCTAssertEqual(report.bundle?.bundleIdentifier, "dev.launchdx.contained")
        XCTAssertEqual(report.launchStatus, .blocked)
        XCTAssertEqual(report.exitCode, .blocked)
        let ids = report.findings.map(\.id)
        XCTAssertTrue(
            ids.contains("signature.unsigned") || ids.contains("signature.invalid"),
            "container diagnosis must reuse the nested app signature result, got \(ids)"
        )
        XCTAssertTrue(report.diagnosis.limitations.contains { $0.contains("mounted read-only") })
        #else
        throw XCTSkip("disk image fixtures require macOS")
        #endif
    }

    func testUnsupportedFileStillUsesStableNotAppFinding() throws {
        let root = try makeRoot()
        let file = root.appendingPathComponent("notes.txt")
        try Data("not an app".utf8).write(to: file)
        let report = DiagnosticPipeline().diagnose(path: file.path)
        XCTAssertEqual(report.target.kind, .file)
        XCTAssertEqual(report.findings.first?.id, "target.not-app")
        XCTAssertEqual(report.exitCode, .dataError)
    }

    #if os(macOS)
    private func makeDiskImage(containing app: URL, name: String) throws -> URL {
        let root = try makeRoot()
        let src = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: app, to: src.appendingPathComponent(app.lastPathComponent))
        let dmg = root.appendingPathComponent(name)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "create",
            "-volname", "LaunchDXFixture",
            "-srcfolder", src.path,
            "-ov",
            "-format", "UDZO",
            dmg.path
        ]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: dmg.path) else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw XCTSkip("hdiutil create failed: \(message)")
        }
        return dmg
    }
    #endif

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("launchdx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        temporaryDirectories.append(root)
        return root
    }

    private func makeApp(name: String, executable: String) throws -> URL {
        let app = try makeRoot().appendingPathComponent(name, isDirectory: true)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let identifier = "dev.launchdx.\(executable.lowercased())"
        let plist: [String: String] = [
            "CFBundleIdentifier": identifier,
            "CFBundleExecutable": executable
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try minimalArm64MachO().write(to: macOS.appendingPathComponent(executable))
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
