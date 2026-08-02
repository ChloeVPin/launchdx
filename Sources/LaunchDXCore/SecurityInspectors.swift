import Foundation

struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
    let launchError: String?
}

protocol CommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult
}

final class ReadOnlyCommandRunner: CommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval = 20) -> CommandResult {
        #if os(macOS)
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, stdout: "", stderr: "", launchError: error.localizedDescription)
        }

        let stdoutData = LockedData()
        let stderrData = LockedData()
        stdoutPipe.fileHandleForReading.readabilityHandler = { stdoutData.append($0.availableData) }
        stderrPipe.fileHandleForReading.readabilityHandler = { stderrData.append($0.availableData) }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            // terminate() is asynchronous. Reap the child before returning so a
            // timed-out diagnostic cannot leave a child process behind.
            process.waitUntilExit()
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        let stdout = stdoutData.data + stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrData.data + stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdoutText = String(data: stdout, encoding: .utf8) ?? ""
        let stderrText = String(data: stderr, encoding: .utf8) ?? ""

        if timedOut {
            return CommandResult(
                status: -1,
                stdout: stdoutText,
                stderr: [stderrText, "command timed out"].filter { !$0.isEmpty }.joined(separator: "\n"),
                launchError: "command timed out"
            )
        }
        return CommandResult(
            status: process.terminationStatus,
            stdout: stdoutText,
            stderr: stderrText,
            launchError: nil
        )
        #else
        return CommandResult(
            status: -1,
            stdout: "",
            stderr: "macOS-only command unavailable",
            launchError: "macOS-only command unavailable"
        )
        #endif
    }
}

private final class LockedData {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }
}

struct SignatureInspector {
    private let runner: CommandRunning
    private let frameworkInspector: SecurityFrameworkChecking

    init(
        runner: CommandRunning = ReadOnlyCommandRunner(),
        frameworkInspector: SecurityFrameworkChecking = SecurityFrameworkInspector()
    ) {
        self.runner = runner
        self.frameworkInspector = frameworkInspector
    }

    func inspect(path: String) -> (SignatureInspection, [Evidence], [Finding]) {
        #if os(macOS)
        let framework = frameworkInspector.inspect(path: path)
        let verification = runner.run(
            "/usr/bin/codesign",
            arguments: ["--verify", "--strict", "--verbose=4", path],
            timeout: 20
        )
        let details = runner.run(
            "/usr/bin/codesign",
            arguments: ["-dvvv", path],
            timeout: 20
        )
        let entitlements = runner.run(
            "/usr/bin/codesign",
            arguments: ["-d", "--entitlements", ":-", path],
            timeout: 20
        )

        let verificationDetail = combinedOutput(verification)
        let descriptor = combinedOutput(details)
        let hostTeamID = field("TeamIdentifier", from: descriptor)
        let nested = NestedCodeValidator(runner: runner).inspect(path: path, hostTeamID: hostTeamID)
        let unsigned = verificationDetail.localizedCaseInsensitiveContains("not signed") ||
            verificationDetail.localizedCaseInsensitiveContains("code object is not signed")
        let adHoc = descriptor.localizedCaseInsensitiveContains("Signature=adhoc")

        // A strict failure is authoritative. A successful API call must not
        // mask a failed strict codesign result; the API is a second source of
        // evidence, not an OR-condition that can turn a failure into a pass.
        let state: SignatureState
        if unsigned {
            state = .unsigned
        } else if framework.valid == false {
            state = .invalid
        } else if verification.launchError == nil && verification.status != 0 {
            state = verificationDetail.isEmpty ? .inconclusive : .invalid
        } else if framework.valid == true || (verification.launchError == nil && verification.status == 0) {
            state = adHoc ? .adHoc : .valid
        } else {
            state = .unavailable
        }

        let flags = field("flags", from: descriptor)?.lowercased()
        let hardenedRuntime: Bool? = flags.map { $0.contains("runtime") }
        let signature = SignatureInspection(
            state: state,
            identity: field("Authority", from: descriptor),
            teamID: framework.teamID ?? hostTeamID,
            identifier: framework.identifier ?? field("Identifier", from: descriptor),
            hardenedRuntime: hardenedRuntime,
            entitlements: parseEntitlements(entitlements.stdout.isEmpty ? entitlements.stderr : entitlements.stdout),
            nested: nested.inspection,
            apiValidation: "SecStaticCodeCheckValidity + codesign --verify --strict --verbose=4",
            rawVerification: verificationDetail
        )

        var evidence = [
            Evidence(
                id: "signature.security-framework",
                kind: .security,
                source: path,
                detail: framework.detail
            ),
            Evidence(
                id: "signature.verification",
                kind: .security,
                source: path,
                detail: verificationDetail.isEmpty ? "codesign returned no verification details." : verificationDetail
            ),
            Evidence(
                id: "signature.metadata",
                kind: .security,
                source: path,
                detail: descriptor.isEmpty ? "codesign returned no signing metadata." : descriptor
            )
        ]
        evidence.append(contentsOf: nested.evidence)

        var findings: [Finding] = []
        switch signature.state {
        case .valid:
            findings.append(Finding(
                id: "signature.valid",
                status: .passed,
                severity: .information,
                confidence: .confirmed,
                title: "Code signature is valid",
                explanation: "The application passed strict code-signature validation.",
                evidenceReferences: ["signature.verification", "signature.security-framework"]
            ))
        case .adHoc:
            findings.append(Finding(
                id: "signature.ad-hoc",
                status: .warning,
                severity: .warning,
                confidence: .confirmed,
                title: "Application uses an ad hoc signature",
                explanation: "The app is signed without a Developer ID identity. It may launch locally, but it is not suitable for normal outside-the-App-Store distribution and may be rejected by Gatekeeper.",
                evidenceReferences: ["signature.metadata"],
                suggestedActions: [SuggestedAction(
                    id: "signature.developer-id",
                    title: "Sign with Developer ID",
                    detail: "Sign the completed app with a Developer ID Application identity before notarization."
                )]
            ))
        case .unsigned:
            findings.append(Finding(
                id: "signature.unsigned",
                status: .failed,
                severity: .blocker,
                confidence: .confirmed,
                title: "Application is unsigned",
                explanation: "The main application code has no code signature.",
                evidenceReferences: ["signature.verification"],
                suggestedActions: [SuggestedAction(
                    id: "signature.sign",
                    title: "Sign the completed app",
                    detail: "Sign the final app bundle after all nested code and resources are present."
                )]
            ))
        case .invalid:
            findings.append(Finding(
                id: "signature.invalid",
                status: .failed,
                severity: .blocker,
                confidence: .confirmed,
                title: "Code signature is invalid",
                explanation: "Strict signature validation rejected the application. This can indicate modified sealed resources, missing nested signatures, or an invalid signing envelope.",
                evidenceReferences: ["signature.verification", "signature.security-framework"],
                suggestedActions: [SuggestedAction(
                    id: "signature.resign",
                    title: "Re-sign the final bundle",
                    detail: "Rebuild the final app, sign nested code explicitly, then sign the app again."
                )]
            ))
        case .unavailable, .inconclusive:
            findings.append(Finding(
                id: "signature.unavailable",
                status: .unavailable,
                severity: .error,
                confidence: .low,
                title: "Code signature could not be inspected",
                explanation: "The available macOS signing evidence was not sufficient to determine the signature state.",
                evidenceReferences: ["signature.verification", "signature.security-framework"]
            ))
        }

        findings += nestedFindings(nested.inspection, evidence: nested.evidence)
        if let hardenedRuntime {
            findings.append(Finding(
                id: "signature.hardened-runtime",
                status: hardenedRuntime ? .passed : .warning,
                severity: hardenedRuntime ? .information : .warning,
                confidence: .high,
                title: hardenedRuntime ? "Hardened Runtime is enabled" : "Hardened Runtime is not enabled",
                explanation: hardenedRuntime
                    ? "The signing flags include the Hardened Runtime option."
                    : "The signing metadata does not show the Hardened Runtime option.",
                evidenceReferences: ["signature.metadata"],
                suggestedActions: hardenedRuntime ? [] : [SuggestedAction(
                    id: "signature.enable-runtime",
                    title: "Enable Hardened Runtime",
                    detail: "Enable Hardened Runtime in the target signing settings before notarization."
                )]
            ))
        }
        return (signature, evidence, findings)
        #else
        let signature = SignatureInspection(state: .unavailable)
        let evidence = [Evidence(
            id: "signature.unavailable",
            kind: .security,
            source: path,
            detail: "Security.framework and codesign inspection require macOS."
        )]
        return (
            signature,
            evidence,
            [Finding(
                id: "signature.unavailable",
                status: .unavailable,
                severity: .error,
                confidence: .low,
                title: "Code signature inspection unavailable",
                explanation: "This build is running outside macOS, so Apple code-signing evidence is unavailable.",
                evidenceReferences: ["signature.unavailable"]
            )]
        )
        #endif
    }

    private func combinedOutput(_ result: CommandResult) -> String {
        [result.stderr, result.stdout].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func field(_ name: String, from text: String) -> String? {
        text.split(separator: "\n").first { $0.hasPrefix("\(name)=") }
            .map { String($0.dropFirst(name.count + 1)) }
    }

    private func parseEntitlements(_ text: String) -> [String: JSONValue] {
        guard let start = text.range(of: "<plist"),
              let end = text.range(of: "</plist>", range: start.lowerBound..<text.endIndex)
        else { return [:] }
        let plistText = String(text[start.lowerBound..<end.upperBound])
        guard let data = plistText.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any]
        else { return [:] }
        return dictionary.mapValues(JSONValue.init(propertyList:))
    }

    private func nestedFindings(_ inspection: NestedCodeInspection, evidence: [Evidence]) -> [Finding] {
        let refs = evidence.map(\.id)
        var findings: [Finding] = []
        if !inspection.invalidPaths.isEmpty {
            findings.append(Finding(
                id: "signature.nested-invalid",
                status: .failed,
                severity: .blocker,
                confidence: .confirmed,
                title: "Nested code signature is invalid",
                explanation: "At least one nested code object failed strict signature validation.",
                evidenceReferences: refs,
                suggestedActions: [SuggestedAction(
                    id: "signature.fix-nested",
                    title: "Sign nested code before the host app",
                    detail: "Sign every nested code object, then sign the containing app last."
                )]
            ))
        }
        if !inspection.unsignedPaths.isEmpty {
            findings.append(Finding(
                id: "signature.nested-unsigned",
                status: .failed,
                severity: .blocker,
                confidence: .confirmed,
                title: "Nested code is unsigned",
                explanation: "At least one nested code object has no signature.",
                evidenceReferences: refs,
                suggestedActions: [SuggestedAction(
                    id: "signature.sign-nested",
                    title: "Sign all nested code",
                    detail: "Sign frameworks, helpers, plug-ins, and XPC services before signing the host app."
                )]
            ))
        }
        if !inspection.unavailablePaths.isEmpty {
            findings.append(Finding(
                id: "signature.nested-unavailable",
                status: .unavailable,
                severity: .error,
                confidence: .low,
                title: "Some nested code could not be inspected",
                explanation: "launchdx could not obtain signing evidence for every discovered nested code object.",
                evidenceReferences: refs
            ))
        }
        if !inspection.mismatchedTeamIDPaths.isEmpty {
            findings.append(Finding(
                id: "signature.team-id-mismatch",
                status: .failed,
                severity: .blocker,
                confidence: .high,
                title: "Nested code Team IDs are inconsistent",
                explanation: "Nested code does not consistently use the host application's signing team.",
                evidenceReferences: refs,
                suggestedActions: [SuggestedAction(
                    id: "signature.align-team-id",
                    title: "Align signing Team IDs",
                    detail: "Use the intended Team ID consistently for host and nested code."
                )]
            ))
        }
        return findings
    }
}

private struct NestedCodeResult {
    let inspection: NestedCodeInspection
    let evidence: [Evidence]
}

private struct NestedCodeValidator {
    let runner: CommandRunning

    func inspect(path: String, hostTeamID: String?) -> NestedCodeResult {
        let paths = discoverNestedCodePaths(path: path)
        var invalid: [String] = []
        var unsigned: [String] = []
        var unavailable: [String] = []
        var teamRecords: [(path: String, teamID: String)] = []
        var evidence: [Evidence] = []
        let checkedPaths = Array(paths.prefix(512))
        let lock = NSLock()
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .utility)
        let slots = DispatchSemaphore(value: 4)

        for nestedPath in checkedPaths {
            group.enter()
            queue.async {
                slots.wait()
                defer {
                    slots.signal()
                    group.leave()
                }

                let result = runner.run(
                    "/usr/bin/codesign",
                    arguments: ["--verify", "--strict", "--verbose=2", nestedPath],
                    timeout: 20
                )
                let detail = [result.stderr, result.stdout].filter { !$0.isEmpty }.joined(separator: "\n")
                let metadata: CommandResult?
                if result.launchError == nil && result.status == 0 {
                    metadata = runner.run(
                        "/usr/bin/codesign",
                        arguments: ["-dvv", nestedPath],
                        timeout: 20
                    )
                } else {
                    metadata = nil
                }
                let metadataText = metadata.map { [$0.stderr, $0.stdout].filter { !$0.isEmpty }.joined(separator: "\n") } ?? ""

                lock.lock()
                evidence.append(Evidence(
                    id: "nested.\(stableID(nestedPath))",
                    kind: .security,
                    source: nestedPath,
                    detail: detail.isEmpty ? "No codesign output." : detail
                ))
                if result.launchError != nil || metadata?.launchError != nil {
                    unavailable.append(nestedPath)
                } else if result.status != 0 {
                    if detail.localizedCaseInsensitiveContains("not signed") ||
                        detail.localizedCaseInsensitiveContains("code object is not signed") {
                        unsigned.append(nestedPath)
                    } else {
                        invalid.append(nestedPath)
                    }
                }
                if let team = field("TeamIdentifier", from: metadataText) {
                    teamRecords.append((nestedPath, team))
                }
                lock.unlock()
            }
        }
        group.wait()

        let sortedTeams = Array(Set(teamRecords.map(\.teamID))).sorted()
        let mismatched = hostTeamID.map { host in
            teamRecords.filter { $0.teamID != host }.map(\.path)
        } ?? []
        return NestedCodeResult(
            inspection: NestedCodeInspection(
                pathsChecked: checkedPaths,
                invalidPaths: invalid.sorted(),
                unsignedPaths: unsigned.sorted(),
                unavailablePaths: unavailable.sorted(),
                teamIDs: sortedTeams,
                mismatchedTeamIDPaths: mismatched.sorted()
            ),
            evidence: evidence.sorted { $0.id < $1.id }
        )
    }

    private func discoverNestedCodePaths(path: String) -> [String] {
        let fileManager = FileManager.default
        let bundleURL = URL(fileURLWithPath: path)
        let roots = [
            "Contents/Frameworks",
            "Contents/Helpers",
            "Contents/PlugIns",
            "Contents/XPCServices",
            "Contents/Library/LoginItems"
        ]
        var discovered = Set<String>()

        func add(_ url: URL) {
            discovered.insert(url.standardizedFileURL.resolvingSymlinksInPath().path)
        }

        for root in roots {
            let rootURL = bundleURL.appendingPathComponent(root, isDirectory: true)
            guard fileManager.fileExists(atPath: rootURL.path),
                  let enumerator = fileManager.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                  )
            else { continue }

            for case let item as URL in enumerator {
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                let isRegularFile = values?.isRegularFile == true
                let extensionName = item.pathExtension.lowercased()
                let isCodeContainer = ["framework", "appex", "xpc", "app", "plugin", "bundle", "qlgenerator", "component", "saver"].contains(extensionName)

                if isCodeContainer {
                    let hasMachOExecutable = addNestedExecutable(in: item, add: add)
                    if hasMachOExecutable || extensionName != "bundle" {
                        add(item)
                    }
                } else if isRegularFile && item.pathExtension.isEmpty && MachOInspector().inspect(path: item.path).isMachO {
                    // This catches extensionless helper executables without
                    // treating ordinary resource files as nested code.
                    add(item)
                }
            }
        }
        return discovered.sorted()
    }

    private func addNestedExecutable(in container: URL, add: (URL) -> Void) -> Bool {
        let candidates = [
            container.appendingPathComponent("Contents/Info.plist"),
            container.appendingPathComponent("Info.plist")
        ]
        for infoURL in candidates {
            guard let data = try? Data(contentsOf: infoURL),
                  let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
                  let executable = plist["CFBundleExecutable"] as? String,
                  !executable.isEmpty,
                  !executable.contains("/")
            else { continue }
            let base = infoURL.path.contains("/Contents/")
                ? infoURL.deletingLastPathComponent().appendingPathComponent("MacOS")
                : container
            let executableURL = base.appendingPathComponent(executable)
            if addMachOIfPresent(executableURL, add: add) {
                return true
            }
        }

        if container.pathExtension.lowercased() == "framework" {
            let name = container.deletingPathExtension().lastPathComponent
            if addMachOIfPresent(container.appendingPathComponent(name), add: add) {
                return true
            }

            let versionsURL = container.appendingPathComponent("Versions", isDirectory: true)
            let currentURL = versionsURL.appendingPathComponent("Current", isDirectory: true).appendingPathComponent(name)
            if addMachOIfPresent(currentURL, add: add) {
                return true
            }
            if let versionDirectories = try? FileManager.default.contentsOfDirectory(
                at: versionsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for versionDirectory in versionDirectories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let values = try? versionDirectory.resourceValues(forKeys: [.isDirectoryKey])
                    guard values?.isDirectory == true,
                          versionDirectory.lastPathComponent != "Current"
                    else { continue }
                    if addMachOIfPresent(versionDirectory.appendingPathComponent(name), add: add) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func addMachOIfPresent(_ url: URL, add: (URL) -> Void) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              MachOInspector().inspect(path: url.path).isMachO
        else { return false }
        add(url)
        return true
    }

    private func field(_ name: String, from text: String) -> String? {
        text.split(separator: "\n").first { $0.hasPrefix("\(name)=") }
            .map { String($0.dropFirst(name.count + 1)) }
    }

    private func stableID(_ path: String) -> String {
        path.utf8.reduce(into: UInt64(0)) { value, byte in
            value = (value &* 31) &+ UInt64(byte)
        }.description
    }
}

struct NotarizationInspector {
    private let runner: CommandRunning

    init(runner: CommandRunning = ReadOnlyCommandRunner()) {
        self.runner = runner
    }

    func inspect(path: String) -> (NotarizationInspection, [Evidence], [Finding]) {
        #if os(macOS)
        let result = runner.run("/usr/bin/xcrun", arguments: ["stapler", "validate", path], timeout: 20)
        let detail = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        let status: StapleStatus
        if result.launchError != nil {
            status = .unavailable
        } else if result.status == 0 {
            status = .valid
        } else if detail.localizedCaseInsensitiveContains("no ticket") ||
                    detail.localizedCaseInsensitiveContains("does not have a ticket") ||
                    detail.localizedCaseInsensitiveContains("not found") {
            status = .absent
        } else if detail.isEmpty {
            status = .inconclusive
        } else {
            status = .invalid
        }
        let inspection = NotarizationInspection(staple: status, detail: detail)
        let findingStatus: FindingStatus = status == .valid ? .passed : status == .unavailable ? .unavailable : status == .inconclusive ? .inconclusive : .warning
        let finding = Finding(
            id: "notarization.staple",
            status: findingStatus,
            severity: status == .invalid || status == .unavailable ? .error : .warning,
            confidence: status == .unavailable || status == .inconclusive ? .low : .high,
            title: status == .valid ? "Stapled notarization ticket is valid" : status == .absent ? "No stapled notarization ticket found" : status == .unavailable ? "Notarization inspection unavailable" : status == .inconclusive ? "Notarization result is inconclusive" : "Stapled notarization ticket is invalid",
            explanation: detail.isEmpty ? "stapler returned no details." : detail,
            evidenceReferences: ["notarization.staple"],
            suggestedActions: status == .valid ? [] : [SuggestedAction(
                id: "notarization.staple",
                title: "Staple the notarization ticket",
                detail: "After notarization succeeds, staple the exact distributed app artifact and validate it again."
            )]
        )
        return (inspection, [Evidence(id: "notarization.staple", kind: .notarization, source: path, detail: detail)], [finding])
        #else
        let inspection = NotarizationInspection(staple: .unavailable, detail: "stapler validation requires macOS.")
        return (
            inspection,
            [Evidence(id: "notarization.unavailable", kind: .notarization, source: path, detail: "Notarization ticket validation requires macOS.")],
            [Finding(id: "notarization.unavailable", status: .unavailable, severity: .error, confidence: .low, title: "Notarization inspection unavailable", explanation: "This build is running outside macOS.", evidenceReferences: ["notarization.unavailable"])]
        )
        #endif
    }
}

struct GatekeeperInspector {
    private let runner: CommandRunning

    init(runner: CommandRunning = ReadOnlyCommandRunner()) {
        self.runner = runner
    }

    func inspect(path: String) -> (GatekeeperInspection, [Evidence], [Finding]) {
        #if os(macOS)
        let result = runner.run("/usr/sbin/spctl", arguments: ["--assess", "--type", "execute", "--verbose=4", "--ignore-cache", path], timeout: 30)
        let detail = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        let status: AssessmentResult
        if result.launchError != nil {
            status = .unavailable
        } else if result.status == 0 {
            status = .accepted
        } else if detail.localizedCaseInsensitiveContains("rejected") {
            status = .rejected
        } else {
            status = .inconclusive
        }
        let inspection = GatekeeperInspection(result: status, detail: detail)
        let findingStatus: FindingStatus = status == .accepted ? .passed : status == .rejected ? .failed : status == .unavailable ? .unavailable : .inconclusive
        let finding = Finding(
            id: "gatekeeper.assessment",
            status: findingStatus,
            severity: status == .accepted ? .information : status == .unavailable || status == .inconclusive ? .error : .blocker,
            confidence: status == .accepted || status == .rejected ? .confirmed : .low,
            title: status == .accepted ? "Gatekeeper accepted the app" : status == .rejected ? "Gatekeeper rejected the app" : status == .unavailable ? "Gatekeeper assessment unavailable" : "Gatekeeper assessment is inconclusive",
            explanation: detail.isEmpty ? "spctl returned no details." : detail,
            evidenceReferences: ["gatekeeper.assessment"],
            suggestedActions: status == .accepted ? [] : [SuggestedAction(
                id: "gatekeeper.inspect-signature",
                title: "Inspect signature and notarization evidence",
                detail: "Resolve the underlying signature, notarization, or policy issue; do not disable Gatekeeper as a default fix."
            )]
        )
        return (inspection, [Evidence(id: "gatekeeper.assessment", kind: .gatekeeper, source: path, detail: detail)], [finding])
        #else
        let inspection = GatekeeperInspection(result: .unavailable, detail: "Gatekeeper assessment requires macOS.")
        return (
            inspection,
            [Evidence(id: "gatekeeper.unavailable", kind: .gatekeeper, source: path, detail: "Gatekeeper assessment requires macOS.")],
            [Finding(id: "gatekeeper.unavailable", status: .unavailable, severity: .error, confidence: .low, title: "Gatekeeper inspection unavailable", explanation: "This build is running outside macOS.", evidenceReferences: ["gatekeeper.unavailable"])]
        )
        #endif
    }
}

struct QuarantineInspector {
    private let runner: CommandRunning

    init(runner: CommandRunning = ReadOnlyCommandRunner()) {
        self.runner = runner
    }

    func inspect(path: String) -> (QuarantineInspection, [Evidence], [Finding]) {
        #if os(macOS)
        let result = runner.run("/usr/bin/xattr", arguments: ["-p", "com.apple.quarantine", path], timeout: 20)
        let detail = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        guard result.status == 0 else {
            if result.launchError != nil {
                return (
                    QuarantineInspection(present: false),
                    [Evidence(id: "quarantine.unavailable", kind: .quarantine, source: path, detail: detail)],
                    [Finding(id: "quarantine.unavailable", status: .unavailable, severity: .error, confidence: .low, title: "Quarantine inspection unavailable", explanation: "The quarantine attribute could not be inspected.", evidenceReferences: ["quarantine.unavailable"])]
                )
            }
            if detail.localizedCaseInsensitiveContains("no such xattr") || detail.localizedCaseInsensitiveContains("attribute not found") {
                return (
                    QuarantineInspection(present: false),
                    [Evidence(id: "quarantine.absent", kind: .quarantine, source: path, detail: "No com.apple.quarantine extended attribute was found.")],
                    [Finding(id: "quarantine.absent", status: .passed, severity: .information, confidence: .high, title: "Quarantine metadata is absent", explanation: "The target does not currently expose com.apple.quarantine.", evidenceReferences: ["quarantine.absent"])]
                )
            }
            return (
                QuarantineInspection(present: false),
                [Evidence(id: "quarantine.unavailable", kind: .quarantine, source: path, detail: detail.isEmpty ? "xattr did not return a result." : detail)],
                [Finding(id: "quarantine.unavailable", status: .unavailable, severity: .error, confidence: .low, title: "Quarantine inspection unavailable", explanation: "xattr failed for a reason other than a confirmed absent attribute.", evidenceReferences: ["quarantine.unavailable"])]
            )
        }

        let raw = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = raw.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        let flags = parts.first.flatMap { UInt32($0, radix: 16) }
        let timestamp = parts.dropFirst().first.flatMap { UInt64($0, radix: 16) }.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let agent = parts.count > 2 ? parts[2] : nil
        let eventIdentifier = parts.count > 3 ? parts[3] : nil
        let wellFormed = parts.count == 4 && flags != nil && timestamp != nil && agent != nil && eventIdentifier != nil && UUID(uuidString: eventIdentifier ?? "") != nil
        let inspection = QuarantineInspection(present: true, flags: flags, timestamp: timestamp, agent: agent, eventIdentifier: eventIdentifier, rawValue: raw)
        let evidence = Evidence(id: "quarantine.present", kind: .quarantine, source: path, detail: "com.apple.quarantine = \(raw)")
        if !wellFormed {
            return (
                inspection,
                [evidence],
                [Finding(id: "quarantine.malformed", status: .inconclusive, severity: .warning, confidence: .low, title: "Quarantine metadata is malformed", explanation: "The com.apple.quarantine attribute exists, but its value does not match the expected four-field format. launchdx cannot safely infer the original download context.", evidenceReferences: [evidence.id])]
            )
        }
        return (
            inspection,
            [evidence],
            [Finding(id: "quarantine.present", status: .warning, severity: .warning, confidence: .confirmed, title: "Quarantine metadata is present", explanation: "The app was marked as coming from an external download source, so macOS may apply additional Gatekeeper checks. Quarantine is a trigger, not necessarily the defect.", evidenceReferences: [evidence.id])]
        )
        #else
        return (
            QuarantineInspection(present: false),
            [Evidence(id: "quarantine.unavailable", kind: .quarantine, source: path, detail: "Quarantine extended-attribute inspection requires macOS.")],
            [Finding(id: "quarantine.unavailable", status: .unavailable, severity: .error, confidence: .low, title: "Quarantine inspection unavailable", explanation: "This build is running outside macOS.", evidenceReferences: ["quarantine.unavailable"])]
        )
        #endif
    }
}
