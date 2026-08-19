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

    func testVersionFlag() {
        XCTAssertThrowsError(try parser.parse(["--version"])) { error in
            XCTAssertEqual(error as? CLIParseError, .version)
        }
        XCTAssertThrowsError(try parser.parse(["-V"])) { error in
            XCTAssertEqual(error as? CLIParseError, .version)
        }
    }

    func testHelpFlag() {
        XCTAssertThrowsError(try parser.parse(["--help"])) { error in
            XCTAssertEqual(error as? CLIParseError, .help)
        }
        XCTAssertThrowsError(try parser.parse(["diagnose", "--help"])) { error in
            XCTAssertEqual(error as? CLIParseError, .help)
        }
    }

    func testMultiplePathsFail() {
        XCTAssertThrowsError(try parser.parse(["diagnose", "A.app", "B.app"])) { error in
            XCTAssertEqual(error as? CLIParseError, .multiplePaths)
        }
    }

    func testDiskImageAndPackagePathsParse() throws {
        let dmg = try parser.parse(["diagnose", "MyApp.dmg", "--json"])
        XCTAssertEqual(dmg.path, "MyApp.dmg")
        XCTAssertTrue(dmg.json)
        let pkg = try parser.parse(["evidence", "MyApp.pkg"])
        XCTAssertEqual(pkg.command, .evidence)
        XCTAssertEqual(pkg.path, "MyApp.pkg")
    }
}
