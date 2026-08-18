import Foundation

public enum CLIParseError: Error, Equatable, CustomStringConvertible {
    case missingCommand
    case unknownCommand(String)
    case missingPath
    case multiplePaths
    case unknownOption(String)
    case help

    public var description: String {
        switch self {
        case .missingCommand:
            return "a command is required (diagnose or evidence)"
        case let .unknownCommand(command):
            return "unknown command: \(command)"
        case .missingPath:
            return "a target path is required"
        case .multiplePaths:
            return "only one target path may be provided"
        case let .unknownOption(option):
            return "unknown option: \(option)"
        case .help:
            return "help requested"
        }
    }
}

public struct CLIParser {
    public init() {}

    public func parse(_ arguments: [String]) throws -> CLIOptions {
        guard let commandName = arguments.first else {
            throw CLIParseError.missingCommand
        }
        if commandName == "--help" || commandName == "-h" {
            throw CLIParseError.help
        }

        let command: CLICommand
        switch commandName {
        case "diagnose":
            command = .diagnose
        case "evidence":
            command = .evidence
        default:
            throw CLIParseError.unknownCommand(commandName)
        }

        var path: String?
        var json = false
        var verbose = false
        var noColor = false

        for argument in arguments.dropFirst() {
            switch argument {
            case "--json":
                json = true
            case "--verbose":
                verbose = true
            case "--no-color":
                noColor = true
            case "--help", "-h":
                throw CLIParseError.help
            case let option where option.hasPrefix("-"):
                throw CLIParseError.unknownOption(option)
            default:
                guard path == nil else {
                    throw CLIParseError.multiplePaths
                }
                path = argument
            }
        }

        guard let path, !path.isEmpty else {
            throw CLIParseError.missingPath
        }

        return CLIOptions(
            command: command,
            path: path,
            json: json,
            verbose: verbose,
            noColor: noColor
        )
    }

    public static let usage = """
    Usage:
      launchdx diagnose <MyApp.app|MyApp.dmg|MyApp.pkg> [--json] [--verbose] [--no-color]
      launchdx evidence <MyApp.app|MyApp.dmg|MyApp.pkg> [--json] [--verbose] [--no-color]
    """
}
