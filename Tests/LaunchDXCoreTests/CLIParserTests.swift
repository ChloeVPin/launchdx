import XCTest
@testable import LaunchDXCore

final class CLIParserTests: XCTestCase {
    private let parser = CLIParser()

    func testDiagnoseOptionsParse() throws {
        let options = try parser.parse([
            "diagnose",
            "MyApp.app",
            "--json",
            "--verbose",
            "--no-color"
        ])

        XCTAssertEqual(options.command, .diagnose)
        XCTAssertEqual(options.path, "MyApp.app")
        XCTAssertTrue(options.json)
        XCTAssertTrue(options.verbose)
        XCTAssertTrue(options.noColor)
    }

    func testEvidenceCommandParses() throws {
        let options = try parser.parse(["evidence", "MyApp.app"])
        XCTAssertEqual(options.command, .evidence)
        XCTAssertEqual(options.path, "MyApp.app")
    }

    func testMissingCommandFails() {
        XCTAssertThrowsError(try parser.parse([])) { error in
            XCTAssertEqual(error as? CLIParseError, .missingCommand)
        }
    }

    func testMissingPathFails() {
        XCTAssertThrowsError(try parser.parse(["diagnose"])) { error in
            XCTAssertEqual(error as? CLIParseError, .missingPath)
        }
    }

    func testUnknownOptionFails() {
        XCTAssertThrowsError(try parser.parse(["diagnose", "MyApp.app", "--wat"])) { error in
            XCTAssertEqual(error as? CLIParseError, .unknownOption("--wat"))
        }
    }
}
