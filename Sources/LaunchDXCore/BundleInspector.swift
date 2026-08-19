import Foundation

public final class BundleInspector {
    typealias SecurityInspectionProvider = (String) -> (SecurityInspection, [Evidence], [Finding])

    private let fileManager: FileManager
    private let performSecurityChecks: Bool
    private let securityInspectionProvider: SecurityInspectionProvider
    private let containerInspector: ContainerInspector

    public init(fileManager: FileManager = .default, performSecurityChecks: Bool = true) {
        self.fileManager = fileManager
        self.performSecurityChecks = performSecurityChecks
        self.securityInspectionProvider = BundleInspector.defaultSecurityInspection
        self.containerInspector = ContainerInspector(fileManager: fileManager)
    }

    init(
        fileManager: FileManager = .default,
        performSecurityChecks: Bool = true,
        securityInspectionProvider: @escaping SecurityInspectionProvider,
        containerInspector: ContainerInspector = ContainerInspector()
    ) {
        self.fileManager = fileManager
        self.performSecurityChecks = performSecurityChecks
        self.securityInspectionProvider = securityInspectionProvider
        self.containerInspector = containerInspector
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

        let extensionName = inputURL.pathExtension.lowercased()
        let kind: ArtifactKind
        if !exists {
            kind = .missing
        } else if isDirectory && extensionName == "app" {
            kind = .applicationBundle
        } else if !isDirectory && extensionName == "dmg" {
            kind = .diskImage
        } else if !isDirectory && extensionName == "pkg" {
            kind = .installerPackage
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
                    detail: "Provide the path to an existing .app bundle, .dmg, or .pkg."
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

        if kind == .diskImage || kind == .installerPackage {
            return inspectContainer(at: resolvedURL ?? inputURL, target: target, kind: kind)
        }

        guard kind == .applicationBundle else {
            let evidence = [Evidence(
                id: "target.not-app",
                kind: .filesystem,
                source: inputURL.path,
                detail: "The target exists, but it is not an application bundle, disk image, or installer package."
            )]
            let finding = Finding(
                id: "target.not-app",
                status: .failed,
                severity: .error,
                confidence: .confirmed,
                title: "Target is not a supported application artifact",
                explanation: "launchdx accepts .app bundle directories, .dmg disk images, and .pkg installer packages.",
                evidenceReferences: ["target.not-app"],
                suggestedActions: [SuggestedAction(
                    id: "target.choose-app",
                    title: "Choose an application artifact",
                    detail: "Pass a path ending in .app, .dmg, or .pkg."
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
                    summary: "The target is outside the supported .app, .dmg, and .pkg scope.",
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

        let composed = DiagnosisComposer.compose(
            findings: findings,
            securityInspection: securityInspection,
            permissionLimited: permissionLimited
        )
        return DiagnosticReport(
            target: target,
            inspectionStatus: composed.inspectionStatus,
            launchStatus: composed.launchStatus,
            bundle: bundle,
            findings: findings,
            diagnosis: composed.diagnosis,
            evidence: evidence
        )
    }

    private func inspectContainer(at containerURL: URL, target: TargetInspection, kind: ArtifactKind) -> DiagnosticReport {
        let unpacked = containerInspector.unpack(path: containerURL.path, kind: kind)
        defer { unpacked.cleanup() }

        var containerFindings = unpacked.findings
        var containerEvidence = unpacked.evidence
        let containerQuarantine = QuarantineInspector().inspect(path: containerURL.path)
        if containerQuarantine.0.present {
            let alreadyPresent = containerFindings.contains { $0.id == "quarantine.present" }
            if !alreadyPresent {
                let finding = Finding(
                    id: "container.quarantine",
                    status: .warning,
                    severity: .warning,
                    confidence: .confirmed,
                    title: "Download container is quarantined",
                    explanation: "The disk image or installer package carries com.apple.quarantine. That is a trigger for Gatekeeper assessment of the nested application, not by itself the defect.",
                    evidenceReferences: ["container.quarantine"]
                )
                containerFindings.append(finding)
                containerEvidence.append(Evidence(
                    id: "container.quarantine",
                    kind: .quarantine,
                    source: containerURL.path,
                    detail: containerQuarantine.0.rawValue.map { "com.apple.quarantine = \($0)" } ?? "com.apple.quarantine is present on the container."
                ))
            }
        } else {
            containerEvidence.append(contentsOf: containerQuarantine.1)
        }

        guard let nestedAppPath = unpacked.nestedAppPath else {
            let inspectionStatus: InspectionStatus
            if !unpacked.inspection.available {
                inspectionStatus = unpacked.findings.contains(where: { $0.status == .unavailable })
                    ? .securityUnavailable
                    : .invalidTarget
            } else {
                inspectionStatus = .invalidTarget
            }
            let composed = DiagnosisComposer.compose(
                findings: containerFindings,
                securityInspection: nil,
                permissionLimited: false,
                extraLimitations: [containerLimitation(kind: kind)]
            )
            return DiagnosticReport(
                target: target,
                inspectionStatus: inspectionStatus,
                launchStatus: .inconclusive,
                bundle: nil,
                container: unpacked.inspection,
                findings: containerFindings,
                diagnosis: Diagnosis(
                    classification: .unavailableEvidence,
                    primaryFindingID: containerFindings.first?.id,
                    triggerFindingIDs: composed.diagnosis.triggerFindingIDs,
                    summary: containerFindings.first?.explanation ?? "The container could not be diagnosed.",
                    confidence: .confirmed,
                    limitations: composed.diagnosis.limitations
                ),
                evidence: containerEvidence
            )
        }

        let nestedReport = inspect(pathString: nestedAppPath)
        return mergeContainer(
            originalTarget: target,
            container: unpacked.inspection,
            containerFindings: containerFindings,
            containerEvidence: containerEvidence,
            nested: nestedReport,
            kind: kind
        )
    }

    private func mergeContainer(
        originalTarget: TargetInspection,
        container: ContainerInspection,
        containerFindings: [Finding],
        containerEvidence: [Evidence],
        nested: DiagnosticReport,
        kind: ArtifactKind
    ) -> DiagnosticReport {
        var findings = containerFindings
        var seen = Set(findings.map(\.id))
        for finding in nested.findings where !seen.contains(finding.id) {
            findings.append(finding)
            seen.insert(finding.id)
        }
        let evidence = containerEvidence + nested.evidence
        let composed = DiagnosisComposer.compose(
            findings: findings,
            securityInspection: nested.bundle?.security,
            permissionLimited: nested.inspectionStatus == .permissionLimited,
            extraLimitations: [containerLimitation(kind: kind)]
        )
        let rewrittenTarget = TargetInspection(
            inputPath: originalTarget.inputPath,
            resolvedPath: container.nestedApplicationPath ?? originalTarget.resolvedPath,
            kind: originalTarget.kind,
            exists: originalTarget.exists,
            isDirectory: originalTarget.isDirectory,
            isReadable: originalTarget.isReadable
        )
        return DiagnosticReport(
            target: rewrittenTarget,
            inspectionStatus: composed.inspectionStatus,
            launchStatus: composed.launchStatus,
            bundle: nested.bundle,
            container: container,
            findings: findings,
            diagnosis: composed.diagnosis,
            evidence: evidence
        )
    }

    private func containerLimitation(kind: ArtifactKind) -> String {
        switch kind {
        case .diskImage:
            return "The disk image was mounted read-only in a temporary mount point and was not modified."
        case .installerPackage:
            return "The installer package was expanded into a temporary directory and was not modified."
        default:
            return "The distribution container was opened read-only and was not modified."
        }
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
