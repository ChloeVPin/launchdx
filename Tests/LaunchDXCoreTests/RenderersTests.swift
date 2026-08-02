import XCTest
@testable import LaunchDXCore

final class RenderersTests: XCTestCase {
    func testJSONRendererProducesStableTopLevelFields() throws {
        let report = makeReport()
        let options = CLIOptions(command: .diagnose, path: "Valid.app", json: true)
        let output = try ReportRenderer().render(report, options: options)

        XCTAssertTrue(output.contains("\"schemaVersion\" : \"1.0\""))
        XCTAssertTrue(output.contains("\"launchStatus\" : \"inconclusive\""))
        XCTAssertTrue(output.hasSuffix("\n"))
    }

    func testTextRendererIncludesDiagnosisAndEvidence() throws {
        let report = makeReport()
        let options = CLIOptions(command: .diagnose, path: "Valid.app")
        let output = try ReportRenderer().render(report, options: options)

        XCTAssertTrue(output.contains("Launch status: INCONCLUSIVE"))
        XCTAssertTrue(output.contains("Diagnosis:"))
        XCTAssertTrue(output.contains("Evidence:"))
        XCTAssertTrue(output.contains("bundle.info-plist-valid"))
    }

    private func makeReport() -> DiagnosticReport {
        let evidence = Evidence(
            id: "bundle.info-plist-valid",
            kind: .infoPlist,
            source: "Valid.app/Contents/Info.plist",
            detail: "Info.plist is valid."
        )
        let finding = Finding(
            id: "bundle.structure-valid",
            status: .passed,
            severity: .information,
            confidence: .high,
            title: "App bundle structure is valid",
            explanation: "The bundle passed structural checks.",
            evidenceReferences: [evidence.id]
        )
        return DiagnosticReport(
            target: TargetInspection(
                inputPath: "Valid.app",
                resolvedPath: "Valid.app",
                kind: .applicationBundle,
                exists: true,
                isDirectory: true,
                isReadable: true
            ),
            inspectionStatus: .complete,
            launchStatus: .inconclusive,
            bundle: nil,
            findings: [finding],
            diagnosis: Diagnosis(
                classification: .inconclusive,
                summary: "No blocker.",
                confidence: .high
            ),
            evidence: [evidence]
        )
    }
}
