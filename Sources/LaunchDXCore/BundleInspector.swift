import Foundation

public final class BundleInspector {
    typealias SecurityInspectionProvider = (String) -> (SecurityInspection, [Evidence], [Finding])

    private let fileManager: FileManager
    private let performSecurityChecks: Bool
    private let securityInspectionProvider: SecurityInspectionProvider

    public init(fileManager: FileManager = .default, performSecurityChecks: Bool = true) {
        self.fileManager = fileManager
        self.performSecurityChecks = performSecurityChecks
        self.securityInspectionProvider = BundleInspector.defaultSecurityInspection
    }

    init(
        fileManager: FileManager = .default,
        performSecurityChecks: Bool = true,
        securityInspectionProvider: @escaping SecurityInspectionProvider
    ) {
        self.fileManager = fileManager
        self.performSecurityChecks = performSecurityChecks
        self.securityInspectionProvider = securityInspectionProvider
    }

    private static func defaultSecurityInspection(path: String) -> (SecurityInspection, [Evidence], [Finding]) {
        let signatureResult = SignatureInspector().inspect(path: path)
        let notarizationResult = NotarizationInspector().inspect(path: path)
        let gatekeeperResult = GatekeeperInspector().inspect(path: path)
        let quarantineResult = QuarantineInspector().inspect(path: path)
        let security = SecurityInspection(
            signature: signatureResult.0,
            notarization: notarizationResult.0,
            gatekeeper: gatekeeperResult.0,
            quarantine: quarantineResult.0
        )
        return (
            security,
            signatureResult.1 + notarizationResult.1 + gatekeeperResult.1 + quarantineResult.1,
            signatureResult.2 + notarizationResult.2 + gatekeeperResult.2 + quarantineResult.2
        )
    }

    public func inspect(pathString: String) -> DiagnosticReport {
        let inputURL = URL(fileURLWithPath: pathString).standardizedFileURL
        var directoryFlag = ObjCBool(false)
        let exists = fileManager.fileExists(atPath: inputURL.path, isDirectory: &directoryFlag)
        let isDirectory = directoryFlag.boolValue
        let readable = exists && fileManager.isReadableFile(atPath: inputURL.path)
        let resolvedURL = exists ? inputURL.resolvingSymlinksInPath() : nil

        let kind: ArtifactKind
        if !exists {
            kind = .missing
        } else if isDirectory && inputURL.pathExtension.lowercased() == "app" {
            kind = .applicationBundle
        } else if isDirectory {
            kind = .directory
        } else {
            kind = .file
        }

        let target = TargetInspection(
            inputPath: pathString,
            resolvedPath: resolvedURL?.path,
            kind: kind,
            exists: exists,
            isDirectory: isDirectory,
            isReadable: readable
        )

        guard exists else {
            let evidence = [Evidence(
                id: "target.missing",
                kind: .filesystem,
                source: inputURL.path,
                detail: "The target path does not exist."
            )]
            let finding = Finding(
                id: "target.missing",
                status: .unavailable,
                severity: .error,
                confidence: .confirmed,
                title: "Target was not found",
                explanation: "launchdx could not inspect the requested path because it does not exist.",
                evidenceReferences: ["target.missing"],
                suggestedActions: [SuggestedAction(
                    id: "target.check-path",
                    title: "Check the target path",
                    detail: "Provide the path to an existing .app bundle."
                )]
            )
            return DiagnosticReport(
                target: target,
                inspectionStatus: .targetMissing,
                launchStatus: .inconclusive,
                bundle: nil,
                findings: [finding],
                diagnosis: Diagnosis(
                    classification: .unavailableEvidence,
                    primaryFindingID: finding.id,
                    summary: "The target could not be inspected.",
                    confidence: .confirmed
                ),
                evidence: evidence
            )
        }

        guard readable else {
            let evidence = [Evidence(
                id: "target.unreadable",
                kind: .filesystem,
                source: inputURL.path,
                detail: "The target exists but is not readable by the current user."
            )]
            let finding = Finding(
                id: "target.unreadable",
                status: .unavailable,
                severity: .error,
                confidence: .confirmed,
                title: "Target is not readable",
                explanation: "launchdx could not inspect the target with the current permissions.",
                evidenceReferences: ["target.unreadable"],
                suggestedActions: [SuggestedAction(
                    id: "target.check-permissions",
                    title: "Check target permissions",
                    detail: "Make the target readable without changing Gatekeeper or other system security settings."
                )]
            )
            return DiagnosticReport(
                target: target,
                inspectionStatus: .permissionLimited,
                launchStatus: .inconclusive,
                bundle: nil,
                findings: [finding],
                diagnosis: Diagnosis(
                    classification: .unavailableEvidence,
                    primaryFindingID: finding.id,
                    summary: "The target could not be inspected with the current permissions.",
                    confidence: .confirmed
                ),
                evidence: evidence
            )
        }

        guard kind == .applicationBundle else {
            let evidence = [Evidence(
                id: "target.not-app",
                kind: .filesystem,
                source: inputURL.path,
                detail: "The target exists, but it is not an application bundle directory with a .app extension."
            )]
            let finding = Finding(
                id: "target.not-app",
                status: .failed,
                severity: .error,
                confidence: .confirmed,
                title: "Target is not an application bundle",
                explanation: "The MVP accepts .app bundle directories only.",
                evidenceReferences: ["target.not-app"],
                suggestedActions: [SuggestedAction(
                    id: "target.choose-app",
                    title: "Choose an application bundle",
                    detail: "Pass a path ending in .app that points to a directory."
                )]
            )
            return DiagnosticReport(
                target: target,
                inspectionStatus: .invalidTarget,
                launchStatus: .inconclusive,
                bundle: nil,
                findings: [finding],
                diagnosis: Diagnosis(
                    classification: .unavailableEvidence,
                    primaryFindingID: finding.id,
                    summary: "The target is outside the .app-only MVP scope.",
                    confidence: .confirmed
                ),
                evidence: evidence
            )
        }

        return inspectApplicationBundle(at: resolvedURL ?? inputURL, target: target)
    }

    private func inspectApplicationBundle(at bundleURL: URL, target: TargetInspection) -> DiagnosticReport {
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        var evidence: [Evidence] = []
        var findings: [Finding] = []

        var infoPlistReadable = false
        var infoPlistValid = false
        var bundleIdentifier: String?
        var executableName: String?
        var executableURL: URL?
        var executableExists = false
        var executableIsRegularFile = false
        var executableReadable = false
        var machoInspection: MachOInspection?
        var securityInspection: SecurityInspection?
        var permissionLimited = false
        var contentsDirectoryFlag = ObjCBool(false)
        let contentsExists = fileManager.fileExists(
            atPath: contentsURL.path,
            isDirectory: &contentsDirectoryFlag
        )
        var infoDirectoryFlag = ObjCBool(false)
        let infoExists = fileManager.fileExists(
            atPath: infoURL.path,
            isDirectory: &infoDirectoryFlag
        )

        if !contentsExists {
            evidence.append(Evidence(
                id: "bundle.contents-missing",
                kind: .filesystem,
                source: contentsURL.path,
                detail: "The app does not contain a Contents directory."
            ))
            findings.append(Finding(
                id: "bundle.contents-missing",
                status: .failed,
                severity: .blocker,
                confidence: .confirmed,
                title: "App bundle structure is invalid",
                explanation: "The application bundle is missing its Contents directory.",
                evidenceReferences: ["bundle.contents-missing"],
                suggestedActions: [SuggestedAction(
                    id: "bundle.rebuild",
                    title: "Rebuild the application bundle",
                    detail: "Produce a complete .app bundle before signing or distributing it."
                )]
            ))
        } else if !contentsDirectoryFlag.boolValue {
            evidence.append(Evidence(
                id: "bundle.contents-not-directory",
                kind: .filesystem,
                source: contentsURL.path,
                detail: "Contents exists but is not a directory."
            ))
            findings.append(Finding(
                id: "bundle.contents-not-directory",
                status: .failed,
                severity: .blocker,
                confidence: .confirmed,
                title: "App bundle structure is invalid",
                explanation: "The app's Contents path is not a directory.",
                evidenceReferences: ["bundle.contents-not-directory"],
                suggestedActions: [SuggestedAction(
                    id: "bundle.restore-contents-directory",
                    title: "Restore the Contents directory",
                    detail: "Rebuild the app with Contents as a directory containing the bundle files."
                )]
            ))
        } else if !infoExists {
            evidence.append(Evidence(
                id: "bundle.info-plist-missing",
                kind: .filesystem,
                source: infoURL.path,
                detail: "Contents/Info.plist is missing."
            ))
            findings.append(Finding(
                id: "bundle.info-plist-missing",
                status: .failed,
                severity: .blocker,
                confidence: .confirmed,
                title: "Info.plist is missing",
                explanation: "The app bundle does not contain Contents/Info.plist.",
                evidenceReferences: ["bundle.info-plist-missing"],
                suggestedActions: [SuggestedAction(
                    id: "bundle.restore-info-plist",
                    title: "Restore Info.plist",
                    detail: "Build the app with a readable Contents/Info.plist before distribution."
                )]
            ))
        } else if infoDirectoryFlag.boolValue {
            evidence.append(Evidence(
                id: "bundle.info-plist-not-regular-file",
                kind: .filesystem,
                source: infoURL.path,
                detail: "Contents/Info.plist exists but is a directory."
            ))
            findings.append(Finding(
                id: "bundle.info-plist-not-regular-file",
                status: .failed,
                severity: .blocker,
                confidence: .confirmed,
                title: "Info.plist is not a regular file",
                explanation: "The app's Info.plist path is a directory rather than a property-list file.",
                evidenceReferences: ["bundle.info-plist-not-regular-file"],
                suggestedActions: [SuggestedAction(
                    id: "bundle.restore-info-plist-file",
                    title: "Restore Info.plist as a file",
                    detail: "Replace the directory with a valid Contents/Info.plist file."
                )]
            ))
        } else if !fileManager.isReadableFile(atPath: infoURL.path) {
            permissionLimited = true
            evidence.append(Evidence(
                id: "bundle.info-plist-unreadable",
                kind: .filesystem,
                source: infoURL.path,
                detail: "Contents/Info.plist exists but is not readable by the current user."
            ))
            findings.append(Finding(
                id: "bundle.info-plist-unreadable",
                status: .unavailable,
                severity: .error,
                confidence: .confirmed,
                title: "Info.plist is not readable",
                explanation: "launchdx could not inspect the bundle metadata with the current permissions.",
                evidenceReferences: ["bundle.info-plist-unreadable"],
                suggestedActions: [SuggestedAction(
                    id: "bundle.check-permissions",
                    title: "Check file permissions",
                    detail: "Make Contents/Info.plist readable without changing system security settings."
                )]
            ))
        } else {
            do {
                let data: Data
                do {
                    data = try Data(contentsOf: infoURL)
                } catch {
                    throw BundleInspectionError.infoPlistRead(error.localizedDescription)
                }
                infoPlistReadable = true
                guard let propertyList = try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as? [String: Any] else {
                    throw BundleInspectionError.invalidPropertyListRoot
                }

                infoPlistValid = true
                bundleIdentifier = propertyList["CFBundleIdentifier"] as? String
                executableName = propertyList["CFBundleExecutable"] as? String
                evidence.append(Evidence(
                    id: "bundle.info-plist-valid",
                    kind: .infoPlist,
                    source: infoURL.path,
                    detail: "Info.plist is readable and contains a property-list dictionary."
                ))

                if let bundleIdentifier, !bundleIdentifier.isEmpty {
                    evidence.append(Evidence(
                        id: "bundle.identifier",
                        kind: .infoPlist,
                        source: infoURL.path,
                        detail: "CFBundleIdentifier = \(bundleIdentifier)"
                    ))
                } else {
                    evidence.append(Evidence(
                        id: "bundle.identifier-missing",
                        kind: .infoPlist,
                        source: infoURL.path,
                        detail: "CFBundleIdentifier is missing or empty."
                    ))
                    findings.append(Finding(
                        id: "bundle.identifier-missing",
                        status: .failed,
                        severity: .blocker,
                        confidence: .confirmed,
                        title: "Bundle identifier is missing",
                        explanation: "Info.plist does not contain a non-empty CFBundleIdentifier.",
                        evidenceReferences: ["bundle.identifier-missing"],
                        suggestedActions: [SuggestedAction(
                            id: "bundle.set-identifier",
                            title: "Set CFBundleIdentifier",
                            detail: "Set a stable, non-empty bundle identifier before signing and distributing the app."
                        )]
                    ))
                }

                if let executableName, !executableName.isEmpty {
                    if executableName.contains("/") || executableName.hasPrefix("/") {
                        evidence.append(Evidence(
                            id: "bundle.executable-invalid-name",
                            kind: .infoPlist,
                            source: infoURL.path,
                            detail: "CFBundleExecutable must be a bundle-relative filename, not a path: \(executableName)"
                        ))
                        findings.append(Finding(
                            id: "bundle.executable-invalid-name",
                            status: .failed,
                            severity: .blocker,
                            confidence: .confirmed,
                            title: "CFBundleExecutable is invalid",
                            explanation: "CFBundleExecutable must identify the app executable by name, not by a path.",
                            evidenceReferences: ["bundle.executable-invalid-name"],
                            suggestedActions: [SuggestedAction(
                                id: "bundle.fix-executable-name",
                                title: "Fix CFBundleExecutable",
                                detail: "Set CFBundleExecutable to the filename inside Contents/MacOS."
                            )]
                        ))
                    } else {
                        executableURL = contentsURL
                            .appendingPathComponent("MacOS", isDirectory: true)
                            .appendingPathComponent(executableName)
                    }
                } else {
                    evidence.append(Evidence(
                        id: "bundle.executable-missing-metadata",
                        kind: .infoPlist,
                        source: infoURL.path,
                        detail: "CFBundleExecutable is missing or empty."
                    ))
                    findings.append(Finding(
                        id: "bundle.executable-missing-metadata",
                        status: .failed,
                        severity: .blocker,
                        confidence: .confirmed,
                        title: "CFBundleExecutable is missing",
                        explanation: "Info.plist does not identify the executable that macOS should launch.",
                        evidenceReferences: ["bundle.executable-missing-metadata"],
                        suggestedActions: [SuggestedAction(
                            id: "bundle.set-executable-name",
                            title: "Set CFBundleExecutable",
                            detail: "Set CFBundleExecutable to the filename of the main executable."
                        )]
                    ))
                }
            } catch let error as BundleInspectionError {
                switch error {
                case let .infoPlistRead(detail):
                    permissionLimited = true
                    evidence.append(Evidence(
                        id: "bundle.info-plist-unreadable",
                        kind: .filesystem,
                        source: infoURL.path,
                        detail: "Contents/Info.plist could not be read: \(detail)"
                    ))
                    findings.append(Finding(
                        id: "bundle.info-plist-unreadable",
                        status: .unavailable,
                        severity: .error,
                        confidence: .confirmed,
                        title: "Info.plist is not readable",
                        explanation: "launchdx could not read the bundle metadata with the current permissions or filesystem state.",
                        evidenceReferences: ["bundle.info-plist-unreadable"],
                        suggestedActions: [SuggestedAction(
                            id: "bundle.check-permissions",
                            title: "Check file permissions",
                            detail: "Make Contents/Info.plist readable without changing system security settings."
                        )]
                    ))
                case .invalidPropertyListRoot:
                    appendInvalidInfoPlistFinding(
                        to: &findings,
                        evidence: &evidence,
                        infoURL: infoURL,
                        detail: "the property-list root is not a dictionary"
                    )
                }
            } catch {
                appendInvalidInfoPlistFinding(
                    to: &findings,
                    evidence: &evidence,
                    infoURL: infoURL,
                    detail: error.localizedDescription
                )
            }
        }

        if let executableURL {
            var executableDirectoryFlag = ObjCBool(false)
            executableExists = fileManager.fileExists(
                atPath: executableURL.path,
                isDirectory: &executableDirectoryFlag
            )
            executableIsRegularFile = executableExists && !executableDirectoryFlag.boolValue
            executableReadable = executableIsRegularFile && fileManager.isReadableFile(atPath: executableURL.path)
            let executableEvidenceID: String
            if !executableExists {
                executableEvidenceID = "bundle.executable-missing"
            } else if !executableIsRegularFile {
                executableEvidenceID = "bundle.executable-not-regular-file"
            } else {
                executableEvidenceID = "bundle.executable-present"
            }
            evidence.append(Evidence(
                id: executableEvidenceID,
                kind: .filesystem,
                source: executableURL.path,
                detail: !executableExists
                    ? "The main executable declared by CFBundleExecutable does not exist."
                    : executableIsRegularFile
                        ? "The main executable exists at the path declared by CFBundleExecutable."
                        : "CFBundleExecutable points to a directory instead of a regular file."
            ))

            if !executableExists {
                findings.append(Finding(
                    id: "bundle.executable-missing",
                    status: .failed,
                    severity: .blocker,
                    confidence: .confirmed,
                    title: "Main executable is missing",
                    explanation: "CFBundleExecutable points to a file that is not present in Contents/MacOS.",
                    evidenceReferences: ["bundle.executable-missing"],
                    suggestedActions: [SuggestedAction(
                        id: "bundle.restore-executable",
                        title: "Restore the main executable",
                        detail: "Rebuild or restore the executable before signing and distributing the app."
                    )]
                ))
            } else if !executableIsRegularFile {
                findings.append(Finding(
                    id: "bundle.executable-not-regular-file",
                    status: .failed,
                    severity: .blocker,
                    confidence: .confirmed,
                    title: "Main executable is not a regular file",
                    explanation: "CFBundleExecutable points to a directory or another non-file object.",
                    evidenceReferences: ["bundle.executable-not-regular-file"],
                    suggestedActions: [SuggestedAction(
                        id: "bundle.restore-regular-executable",
                        title: "Restore a regular executable file",
                        detail: "Place the app's executable file in Contents/MacOS at the declared path."
                    )]
                ))
            } else if !executableReadable {
                permissionLimited = true
                findings.append(Finding(
                    id: "bundle.executable-unreadable",
                    status: .unavailable,
                    severity: .error,
                    confidence: .confirmed,
                    title: "Main executable is not readable",
                    explanation: "The main executable exists, but launchdx cannot read it with the current permissions.",
                    evidenceReferences: ["bundle.executable-present"],
                    suggestedActions: [SuggestedAction(
                        id: "bundle.check-executable-permissions",
                        title: "Check executable permissions",
                        detail: "Make the executable readable before signing or launching the app."
                    )]
                ))
            } else {
                let macho = MachOInspector().inspect(path: executableURL.path)
                machoInspection = macho
                evidence.append(Evidence(
                    id: macho.isReadable ? "macho.inspection" : "macho.unreadable",
                    kind: .macho,
                    source: executableURL.path,
                    detail: machoEvidenceDetail(macho)
                ))

                if !macho.isReadable {
                    permissionLimited = true
                    findings.append(Finding(
                        id: "macho.unreadable",
                        status: .unavailable,
                        severity: .error,
                        confidence: .confirmed,
                        title: "Main executable could not be read",
                        explanation: macho.error ?? "launchdx could not read the executable with the current permissions or filesystem state.",
                        evidenceReferences: ["macho.unreadable"],
                        suggestedActions: [SuggestedAction(
                            id: "macho.check-permissions",
                            title: "Check executable permissions",
                            detail: "Make the executable readable without changing system security settings."
                        )]
                    ))
                } else if macho.isMalformed {
                    findings.append(Finding(
                        id: "macho.malformed",
                        status: .failed,
                        severity: .blocker,
                        confidence: .confirmed,
                        title: "Main executable is malformed",
                        explanation: macho.error ?? "The main executable contains malformed Mach-O metadata.",
                        evidenceReferences: ["macho.inspection"],
                        suggestedActions: [SuggestedAction(
                            id: "macho.rebuild-executable",
                            title: "Rebuild the executable",
                            detail: "Build a valid Mach-O executable for the target macOS architectures, then replace the malformed binary."
                        )]
                    ))
                } else if !macho.isMachO {
                    findings.append(Finding(
                        id: "macho.not-mach-o",
                        status: .failed,
                        severity: .blocker,
                        confidence: .confirmed,
                        title: "Main executable is not a Mach-O binary",
                        explanation: "The file declared by CFBundleExecutable does not contain a recognized Mach-O header.",
                        evidenceReferences: ["macho.inspection"],
                        suggestedActions: [SuggestedAction(
                            id: "macho.build-executable",
                            title: "Build a Mach-O executable",
                            detail: "Replace the placeholder or incompatible file with the app's actual macOS executable."
                        )]
                    ))
                } else if !macho.supportsArm64 {
                    findings.append(Finding(
                        id: "macho.arm64-missing",
                        status: .warning,
                        severity: .warning,
                        confidence: .high,
                        title: "Main executable does not contain arm64",
                        explanation: macho.supportsX86_64
                            ? "The executable is x86_64-only. It may run through Rosetta 2, but launchdx has not verified Rosetta availability."
                            : "The executable does not contain an arm64 slice required for native Apple Silicon execution.",
                        evidenceReferences: ["macho.inspection"],
                        suggestedActions: [SuggestedAction(
                            id: "macho.add-arm64",
                            title: "Build an arm64 or universal executable",
                            detail: "Add an arm64 slice to support native execution on Apple Silicon Macs."
                        )]
                    ))
                } else {
                    findings.append(Finding(
                        id: "macho.arm64-supported",
                        status: .passed,
                        severity: .information,
                        confidence: .confirmed,
                        title: "Main executable supports arm64",
                        explanation: "The main executable contains an arm64 Mach-O slice.",
                        evidenceReferences: ["macho.inspection"]
                    ))
                }

                if macho.hasCodeSignatureLoadCommand && !macho.codeSignatureRangeValid {
                    findings.append(Finding(
                        id: "macho.code-signature-range-invalid",
                        status: .failed,
                        severity: .blocker,
                        confidence: .confirmed,
                        title: "Code-signature load command is invalid",
                        explanation: "The executable declares code-signature data outside its file bounds.",
                        evidenceReferences: ["macho.inspection"],
                        suggestedActions: [SuggestedAction(
                            id: "macho.rebuild-signature-data",
                            title: "Rebuild the executable signature data",
                            detail: "Produce the final executable first, then sign the exact file without truncating its code-signature data."
                        )]
                    ))
                }
            }
        }

        let hasStructuralBlocker = findings.contains { $0.severity == .blocker && $0.status == .failed }
        if performSecurityChecks && infoPlistValid && executableExists && executableIsRegularFile && executableReadable && !hasStructuralBlocker {
            let securityResult = securityInspectionProvider(bundleURL.path)
            securityInspection = securityResult.0
            evidence.append(contentsOf: securityResult.1)
            findings.append(contentsOf: securityResult.2)
        }

        if findings.isEmpty {
            let evidenceIDs = evidence.map(\.id)
            findings.append(Finding(
                id: "bundle.structure-valid",
                status: .passed,
                severity: .information,
                confidence: .high,
                title: "App bundle structure is valid",
                explanation: "The .app directory, Info.plist, CFBundleExecutable, and declared executable path passed milestone-one checks.",
                evidenceReferences: evidenceIDs
            ))
        }

        let bundle = BundleInspection(
            bundlePath: bundleURL.path,
            infoPlistPath: infoURL.path,
            infoPlistReadable: infoPlistReadable,
            infoPlistValid: infoPlistValid,
            bundleIdentifier: bundleIdentifier,
            executableName: executableName,
            executablePath: executableURL?.path,
            executableExists: executableExists,
            executableIsRegularFile: executableIsRegularFile,
            executableReadable: executableReadable,
            macho: machoInspection,
            security: securityInspection
        )

        let hasBlocker = findings.contains { $0.severity == .blocker && $0.status == .failed }
        let primary = findings.first { $0.severity == .blocker && $0.status == .failed } ?? findings.first
        let signatureBlocker = findings.first { $0.id.hasPrefix("signature.") && $0.severity == .blocker && $0.status == .failed }
        let gatekeeperRejected = findings.contains { $0.id == "gatekeeper.assessment" && $0.status == .failed }
        let quarantinePresent = findings.contains { $0.id == "quarantine.present" }
        let triggerIDs = quarantinePresent ? ["quarantine.present"] : []
        let securityUnavailable = securityInspection.map {
            $0.signature.state == .unavailable ||
            $0.signature.state == .inconclusive ||
            $0.notarization.staple == .unavailable ||
            $0.gatekeeper.result == .unavailable ||
            findings.contains { $0.id == "quarantine.unavailable" || $0.id == "signature.nested-unavailable" }
        } ?? false
        let completeSecurityInspection = securityInspection != nil && !securityUnavailable && !findings.contains { finding in
            finding.status == .inconclusive &&
            (finding.id.hasPrefix("quarantine.") || finding.id.hasPrefix("gatekeeper.") || finding.id.hasPrefix("notarization."))
        }
        let summary: String
        if let signatureBlocker, gatekeeperRejected, quarantinePresent {
            summary = "Gatekeeper rejected the quarantined app, and the primary cause is the invalid or missing code signature: \(signatureBlocker.explanation) Quarantine triggered the assessment; it is not itself the defect."
        } else if hasBlocker, let primary {
            summary = primary.explanation
        } else if completeSecurityInspection {
            summary = "No confirmed launch blocker was found."
        } else if let primary {
            summary = primary.explanation
        } else {
            summary = "No confirmed blocker was found, but the full launch diagnosis is incomplete."
        }
        let limitations: [String] = {
            #if os(macOS)
            return ["Nested code is scanned from common bundle locations; unified logs, TCC, sandbox, and App Translocation are not inspected yet."]
            #else
            return ["Apple security checks require macOS and were not available in this build."]
            #endif
        }()
        let diagnosis = Diagnosis(
            classification: hasBlocker ? .confirmedBlocker : completeSecurityInspection ? .clean : .inconclusive,
            primaryFindingID: signatureBlocker?.id ?? primary?.id,
            triggerFindingIDs: triggerIDs,
            summary: summary,
            confidence: hasBlocker ? .confirmed : .high,
            limitations: limitations
        )

        let inspectionStatus: InspectionStatus = permissionLimited ? .permissionLimited : securityUnavailable ? .securityUnavailable : .complete
        let launchStatus: LaunchStatus = hasBlocker ? .blocked : completeSecurityInspection ? .clean : .inconclusive
        return DiagnosticReport(
            target: target,
            inspectionStatus: inspectionStatus,
            launchStatus: launchStatus,
            bundle: bundle,
            findings: findings,
            diagnosis: diagnosis,
            evidence: evidence
        )
    }
}

private func machoEvidenceDetail(_ macho: MachOInspection) -> String {
    if !macho.isMachO {
        return macho.error ?? "The executable is not a recognized Mach-O binary."
    }
    let architectures = macho.architectures.joined(separator: ", ")
    let format = macho.format.rawValue
    var detail = "Recognized \(format) Mach-O with architectures: \(architectures)."
    if let minimumOSVersion = macho.minimumOSVersion {
        detail += " Minimum macOS version: \(minimumOSVersion)."
    }
    if let sdkVersion = macho.sdkVersion {
        detail += " SDK version: \(sdkVersion)."
    }
    detail += macho.hasCodeSignatureLoadCommand
        ? " LC_CODE_SIGNATURE is present."
        : " LC_CODE_SIGNATURE is absent."
    return detail
}

private enum BundleInspectionError: LocalizedError {
    case invalidPropertyListRoot
    case infoPlistRead(String)

    var errorDescription: String? {
        switch self {
        case .invalidPropertyListRoot:
            return "the property-list root is not a dictionary"
        case let .infoPlistRead(detail):
            return detail
        }
    }
}

private func appendInvalidInfoPlistFinding(
    to findings: inout [Finding],
    evidence: inout [Evidence],
    infoURL: URL,
    detail: String
) {
    evidence.append(Evidence(
        id: "bundle.info-plist-invalid",
        kind: .infoPlist,
        source: infoURL.path,
        detail: "Info.plist could not be parsed as a property-list dictionary: \(detail)"
    ))
    findings.append(Finding(
        id: "bundle.info-plist-invalid",
        status: .failed,
        severity: .blocker,
        confidence: .confirmed,
        title: "Info.plist is invalid",
        explanation: "The app metadata could not be parsed as a valid property-list dictionary.",
        evidenceReferences: ["bundle.info-plist-invalid"],
        suggestedActions: [SuggestedAction(
            id: "bundle.rebuild-info-plist",
            title: "Regenerate Info.plist",
            detail: "Rebuild the app so Contents/Info.plist is a valid property-list dictionary."
        )]
    ))
}
