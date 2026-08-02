import Foundation

public struct ReportRenderer {
    public init() {}

    public func render(_ report: DiagnosticReport, options: CLIOptions) throws -> String {
        if options.json {
            return try renderJSON(report)
        }
        return renderText(report, verbose: options.verbose, noColor: options.noColor, evidenceOnly: options.command == .evidence)
    }

    public func renderJSON(_ report: DiagnosticReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        guard let output = String(data: data, encoding: .utf8) else {
            throw RendererError.encodingFailed
        }
        return output + "\n"
    }

    public func renderText(
        _ report: DiagnosticReport,
        verbose: Bool = false,
        noColor: Bool = false,
        evidenceOnly: Bool = false
    ) -> String {
        var lines: [String] = []
        let status = report.launchStatus == .blocked ? "BLOCKED" : report.launchStatus == .clean ? "NO BLOCKER FOUND" : "INCONCLUSIVE"
        lines.append("Launch status: \(status)")
        lines.append("")
        lines.append("Target:")
        lines.append("  \(report.target.inputPath)")
        if let resolvedPath = report.target.resolvedPath, resolvedPath != report.target.inputPath {
            lines.append("  Resolved: \(resolvedPath)")
        }
        lines.append("")
        lines.append("Environment:")
        lines.append("  macOS: \(report.environment.operatingSystem)")
        lines.append("  Architecture: \(report.environment.hostArchitecture)")
        lines.append("  Apple Silicon: \(report.environment.appleSilicon ? "yes" : "no")")
        lines.append("")

        if let bundle = report.bundle {
            lines.append("Bundle:")
            lines.append("  Info.plist: \(bundle.infoPlistValid ? "valid" : bundle.infoPlistReadable ? "invalid" : "unavailable")")
            lines.append("  Bundle identifier: \(bundle.bundleIdentifier ?? "not present")")
            lines.append("  Executable: \(bundle.executableName ?? "not declared")")
            lines.append("  Executable path: \(bundle.executablePath ?? "not resolved")")
            lines.append("  Executable exists: \(bundle.executableExists ? "yes" : "no")")
            lines.append("  Executable readable: \(bundle.executableReadable ? "yes" : "no")")
            if let macho = bundle.macho {
                lines.append("  Mach-O: \(macho.isMachO ? macho.format.rawValue : "not recognized")")
                lines.append("  Architectures: \(macho.architectures.isEmpty ? "none detected" : macho.architectures.joined(separator: ", "))")
                lines.append("  Minimum macOS: \(macho.minimumOSVersion ?? "not present")")
                lines.append("  SDK: \(macho.sdkVersion ?? "not present")")
                lines.append("  LC_CODE_SIGNATURE: \(macho.hasCodeSignatureLoadCommand ? (macho.codeSignatureRangeValid ? "present and in bounds" : "present but invalid") : "absent")")
            }
            if let security = bundle.security {
                lines.append("  Signature: \(security.signature.state.rawValue)")
                lines.append("  Team ID: \(security.signature.teamID ?? "not present")")
                lines.append("  Hardened Runtime: \(security.signature.hardenedRuntime.map { $0 ? "enabled" : "disabled" } ?? "unavailable")")
                lines.append("  Stapled ticket: \(security.notarization.staple.rawValue)")
                lines.append("  Gatekeeper: \(security.gatekeeper.result.rawValue)")
                lines.append("  Quarantine: \(security.quarantine.present ? "present" : "absent")")
            }
            lines.append("")
        }

        if !evidenceOnly {
            lines.append("Findings:")
            for finding in report.findings {
                lines.append("  \(symbol(for: finding.status, noColor: noColor)) \(finding.title) [\(finding.id)]")
                lines.append("    \(finding.explanation)")
                lines.append("    Confidence: \(finding.confidence.rawValue)")
            }
            lines.append("")
            lines.append("Diagnosis:")
            lines.append("  \(report.diagnosis.summary)")
            lines.append("  Classification: \(report.diagnosis.classification.rawValue)")
            lines.append("  Confidence: \(report.diagnosis.confidence.rawValue)")
            if !report.diagnosis.triggerFindingIDs.isEmpty {
                lines.append("  Trigger: \(report.diagnosis.triggerFindingIDs.joined(separator: ", "))")
            }
            if !report.diagnosis.limitations.isEmpty {
                lines.append("  Limitations:")
                report.diagnosis.limitations.forEach { lines.append("    - \($0)") }
            }
            lines.append("")
        }

        lines.append("Evidence:")
        for item in report.evidence {
            lines.append("  [\(item.id)] \(item.source)")
            lines.append("    \(item.detail)")
        }

        if verbose && !report.findings.isEmpty {
            lines.append("")
            lines.append("Suggested actions:")
            for finding in report.findings {
                for action in finding.suggestedActions {
                    lines.append("  - \(action.title): \(action.detail)")
                }
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func symbol(for status: FindingStatus, noColor: Bool) -> String {
        switch status {
        case .passed:
            return "✅"
        case .failed:
            return "❌"
        case .warning:
            return "⚠️"
        case .skipped:
            return "➖"
        case .unavailable:
            return "?"
        case .inconclusive:
            return "❔"
        }
    }
}

private enum RendererError: Error {
    case encodingFailed
}
