import Darwin
import Foundation
import LaunchDXCore

let parser = CLIParser()

 do {
    let options = try parser.parse(Array(CommandLine.arguments.dropFirst()))
    let report = DiagnosticPipeline().diagnose(path: options.path)
    let output = try ReportRenderer().render(report, options: options)
    FileHandle.standardOutput.write(Data(output.utf8))
    exit(report.exitCode.rawValue)
} catch CLIParseError.help {
    FileHandle.standardOutput.write(Data((CLIParser.usage + "\n").utf8))
    exit(LaunchDXExitCode.ok.rawValue)
} catch let error as CLIParseError {
    let message = "launchdx: \(error.description)\n\n\(CLIParser.usage)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(LaunchDXExitCode.usage.rawValue)
} catch {
    let message = "launchdx: internal error: \(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(LaunchDXExitCode.software.rawValue)
}
