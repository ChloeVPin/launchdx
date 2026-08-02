import Foundation
import XCTest
@testable import LaunchDXCore

final class SchemaValidationTests: XCTestCase {
    func testEveryReportCanBeDecodedAsTheStableReportShape() throws {
        let report = BundleInspector(performSecurityChecks: false).inspect(pathString: missingPath().path)
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(DiagnosticReport.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, "1.0")
        XCTAssertEqual(decoded, report)
        XCTAssertNotNil(decoded.diagnosis.summary)
    }

    func testReportEncodingIncludesAllSchemaRequiredTopLevelFields() throws {
        let report = BundleInspector(performSecurityChecks: false).inspect(pathString: missingPath().path)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
        let required = [
            "schemaVersion", "toolVersion", "target", "environment",
            "inspectionStatus", "launchStatus", "findings", "diagnosis", "evidence"
        ]
        for key in required {
            XCTAssertNotNil(object[key], "missing emitted field: \(key)")
        }
    }

    func testValidatorRejectsAnUnknownTopLevelProperty() throws {
        let report = BundleInspector(performSecurityChecks: false).inspect(pathString: missingPath().path)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
        object["unexpected"] = true
        let data = try JSONSerialization.data(withJSONObject: object)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("launchdx-invalid-\(UUID().uuidString).json")
        try data.write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let script = repositoryRoot()
            .appendingPathComponent("Scripts/validate-report.py")
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw XCTSkip("repository validator is only available from the package root")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, temporary.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertNotEqual(process.terminationStatus, 0)
    }

    private func missingPath() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("launchdx-schema-\(UUID().uuidString)").appendingPathComponent("Missing.app")
    }

    private func repositoryRoot() -> URL {
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<4 {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
