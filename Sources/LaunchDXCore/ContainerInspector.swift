import Foundation

struct ContainerUnpackResult {
    let inspection: ContainerInspection
    let nestedAppPath: String?
    let evidence: [Evidence]
    let findings: [Finding]
    let cleanup: () -> Void
}

final class ContainerInspector {
    private let fileManager: FileManager
    private let runner: CommandRunning

    init(fileManager: FileManager = .default, runner: CommandRunning = ReadOnlyCommandRunner()) {
        self.fileManager = fileManager
        self.runner = runner
    }

    func unpack(path: String, kind: ArtifactKind) -> ContainerUnpackResult {
        #if os(macOS)
        switch kind {
        case .diskImage:
            return unpackDiskImage(path: path)
        case .installerPackage:
            return unpackInstallerPackage(path: path)
        default:
            return unavailable(
                path: path,
                kind: kind,
                method: "none",
                detail: "The target is not a disk image or installer package."
            )
        }
        #else
        return unavailable(
            path: path,
            kind: kind,
            method: kind == .diskImage ? "hdiutil-attach" : "pkgutil-expand",
            detail: "Disk image and installer package inspection require macOS."
        )
        #endif
    }

    #if os(macOS)
    private func unpackDiskImage(path: String) -> ContainerUnpackResult {
        let workRoot = fileManager.temporaryDirectory
            .appendingPathComponent("launchdx-dmg-\(UUID().uuidString)", isDirectory: true)
        let mountPoint = workRoot.appendingPathComponent("volume", isDirectory: true)
        do {
            try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        } catch {
            return unavailable(
                path: path,
                kind: .diskImage,
                method: "hdiutil-attach",
                detail: "Could not create a temporary mount point: \(error.localizedDescription)"
            )
        }

        let attach = runner.run(
            "/usr/bin/hdiutil",
            arguments: [
                "attach",
                "-readonly",
                "-nobrowse",
                "-noverify",
                "-owners",
                "off",
                "-mountpoint",
                mountPoint.path,
                path
            ],
            timeout: 60
        )
        if attach.launchError != nil || attach.status != 0 {
            try? fileManager.removeItem(at: workRoot)
            let detail = commandDetail(attach).isEmpty
                ? "hdiutil attach failed."
                : commandDetail(attach)
            let status: FindingStatus = attach.launchError != nil ? .unavailable : .failed
            return ContainerUnpackResult(
                inspection: ContainerInspection(
                    kind: .diskImage,
                    unpackMethod: "hdiutil-attach",
                    nestedApplicationPath: nil,
                    available: false,
                    detail: detail
                ),
                nestedAppPath: nil,
                evidence: [Evidence(
                    id: "container.unavailable",
                    kind: .container,
                    source: path,
                    detail: detail
                )],
                findings: [Finding(
                    id: "container.unavailable",
                    status: status,
                    severity: .error,
                    confidence: .low,
                    title: "Disk image could not be mounted",
                    explanation: "launchdx mounts disk images read-only with hdiutil and does not modify the original file. \(detail)",
                    evidenceReferences: ["container.unavailable"]
                )],
                cleanup: {}
            )
        }

        let cleanup: () -> Void = { [fileManager] in
            _ = ReadOnlyCommandRunner().run(
                "/usr/bin/hdiutil",
                arguments: ["detach", mountPoint.path, "-quiet", "-force"],
                timeout: 30
            )
            try? fileManager.removeItem(at: workRoot)
        }

        return finishUnpack(
            path: path,
            kind: .diskImage,
            method: "hdiutil-attach",
            searchRoot: mountPoint,
            successEvidenceID: "container.mounted",
            successTitle: "Disk image mounted read-only",
            successDetail: "Mounted \(path) at \(mountPoint.path) without modifying the original image.",
            cleanup: cleanup
        )
    }

    private func unpackInstallerPackage(path: String) -> ContainerUnpackResult {
        let workRoot = fileManager.temporaryDirectory
            .appendingPathComponent("launchdx-pkg-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: workRoot, withIntermediateDirectories: true)
        } catch {
            return unavailable(
                path: path,
                kind: .installerPackage,
                method: "pkgutil-expand",
                detail: "Could not create a temporary expand directory: \(error.localizedDescription)"
            )
        }

        let expandFull = runner.run(
            "/usr/sbin/pkgutil",
            arguments: ["--expand-full", path, workRoot.appendingPathComponent("expanded").path],
            timeout: 60
        )
        let searchRoot = workRoot.appendingPathComponent("expanded", isDirectory: true)
        var method = "pkgutil-expand-full"
        var expandDetail = commandDetail(expandFull)

        if expandFull.launchError != nil || expandFull.status != 0 {
            let expand = runner.run(
                "/usr/sbin/pkgutil",
                arguments: ["--expand", path, searchRoot.path],
                timeout: 60
            )
            method = "pkgutil-expand"
            expandDetail = commandDetail(expand)
            if expand.launchError != nil || expand.status != 0 {
                try? fileManager.removeItem(at: workRoot)
                let detail = expandDetail.isEmpty ? "pkgutil expand failed." : expandDetail
                return ContainerUnpackResult(
                    inspection: ContainerInspection(
                        kind: .installerPackage,
                        unpackMethod: method,
                        nestedApplicationPath: nil,
                        available: false,
                        detail: detail
                    ),
                    nestedAppPath: nil,
                    evidence: [Evidence(
                        id: "container.unavailable",
                        kind: .container,
                        source: path,
                        detail: detail
                    )],
                    findings: [Finding(
                        id: "container.unavailable",
                        status: expand.launchError != nil ? .unavailable : .failed,
                        severity: .error,
                        confidence: .low,
                        title: "Installer package could not be expanded",
                        explanation: "launchdx expands installer packages into a temporary directory and does not modify the original file. \(detail)",
                        evidenceReferences: ["container.unavailable"]
                    )],
                    cleanup: {}
                )
            }
            extractPayloads(in: searchRoot)
        }

        let cleanup: () -> Void = { [fileManager] in
            try? fileManager.removeItem(at: workRoot)
        }

        return finishUnpack(
            path: path,
            kind: .installerPackage,
            method: method,
            searchRoot: searchRoot,
            successEvidenceID: "container.expanded",
            successTitle: "Installer package expanded",
            successDetail: "Expanded \(path) into a temporary directory without modifying the original package. \(expandDetail)".trimmingCharacters(in: .whitespaces),
            cleanup: cleanup
        )
    }

    private func extractPayloads(in root: URL) {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let item as URL in enumerator {
            guard item.lastPathComponent == "Payload" else { continue }
            let dest = item.deletingLastPathComponent().appendingPathComponent("PayloadExtracted", isDirectory: true)
            try? fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
            let extracted = runner.run(
                "/usr/bin/ditto",
                arguments: ["-x", item.path, dest.path],
                timeout: 60
            )
            if extracted.status != 0 || extracted.launchError != nil {
                _ = runner.run(
                    "/bin/sh",
                    arguments: [
                        "-c",
                        "gzip -dc \"$1\" | (cd \"$2\" && cpio -id --quiet)" ,
                        "launchdx-payload",
                        item.path,
                        dest.path
                    ],
                    timeout: 60
                )
            }
        }
    }

    private func finishUnpack(
        path: String,
        kind: ArtifactKind,
        method: String,
        searchRoot: URL,
        successEvidenceID: String,
        successTitle: String,
        successDetail: String,
        cleanup: @escaping () -> Void
    ) -> ContainerUnpackResult {
        let apps = findApplicationBundles(in: searchRoot)
        var evidence = [
            Evidence(
                id: successEvidenceID,
                kind: .container,
                source: path,
                detail: successDetail
            )
        ]
        var findings = [
            Finding(
                id: successEvidenceID,
                status: .passed,
                severity: .information,
                confidence: .confirmed,
                title: successTitle,
                explanation: successDetail,
                evidenceReferences: [successEvidenceID]
            )
        ]

        guard let chosen = chooseApplication(from: apps) else {
            evidence.append(Evidence(
                id: "container.no-app",
                kind: .container,
                source: searchRoot.path,
                detail: "No application bundle with a .app extension was found after unpacking the container."
            ))
            findings.append(Finding(
                id: "container.no-app",
                status: .failed,
                severity: .error,
                confidence: .confirmed,
                title: "Container does not contain an application",
                explanation: "The disk image or installer package was opened read-only, but launchdx could not find a nested .app bundle to diagnose.",
                evidenceReferences: ["container.no-app"],
                suggestedActions: [SuggestedAction(
                    id: "container.choose-app",
                    title: "Point launchdx at the application",
                    detail: "If the product is not an application bundle, this container is outside launchdx scope. If the app is elsewhere, pass that .app path directly."
                )]
            ))
            return ContainerUnpackResult(
                inspection: ContainerInspection(
                    kind: kind,
                    unpackMethod: method,
                    nestedApplicationPath: nil,
                    available: true,
                    detail: "Unpacked, but no nested application bundle was found."
                ),
                nestedAppPath: nil,
                evidence: evidence,
                findings: findings,
                cleanup: cleanup
            )
        }

        if apps.count > 1 {
            let listed = apps.map(\.path).joined(separator: ", ")
            evidence.append(Evidence(
                id: "container.multiple-apps",
                kind: .container,
                source: searchRoot.path,
                detail: "Found \(apps.count) application bundles: \(listed). Using \(chosen.path)."
            ))
            findings.append(Finding(
                id: "container.multiple-apps",
                status: .warning,
                severity: .warning,
                confidence: .high,
                title: "Container contains more than one application",
                explanation: "launchdx diagnosed \(chosen.lastPathComponent) as the primary nested application. Other bundles were recorded as evidence and were not separately diagnosed.",
                evidenceReferences: ["container.multiple-apps"]
            ))
        }

        evidence.append(Evidence(
            id: "container.app-found",
            kind: .container,
            source: chosen.path,
            detail: "Nested application bundle: \(chosen.path)"
        ))
        findings.append(Finding(
            id: "container.app-found",
            status: .passed,
            severity: .information,
            confidence: .confirmed,
            title: "Nested application found",
            explanation: "The container was opened read-only and the nested application will be diagnosed with the same .app checks.",
            evidenceReferences: ["container.app-found"]
        ))

        return ContainerUnpackResult(
            inspection: ContainerInspection(
                kind: kind,
                unpackMethod: method,
                nestedApplicationPath: chosen.path,
                available: true,
                detail: successDetail
            ),
            nestedAppPath: chosen.path,
            evidence: evidence,
            findings: findings,
            cleanup: cleanup
        )
    }

    private func findApplicationBundles(in root: URL) -> [URL] {
        var found: [URL] = []
        func consider(_ url: URL) {
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  url.pathExtension.lowercased() == "app"
            else { return }
            let standardized = url.standardizedFileURL.path
            if !found.contains(where: { $0.standardizedFileURL.path == standardized }) {
                found.append(url)
            }
        }

        if let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                consider(child)
            }
            let applications = root.appendingPathComponent("Applications", isDirectory: true)
            if let appChildren = try? fileManager.contentsOfDirectory(
                at: applications,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for child in appChildren.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    consider(child)
                }
            }
        }

        if found.isEmpty, let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            var depthNotes: [URL] = []
            for case let item as URL in enumerator {
                let relative = item.path.replacingOccurrences(of: root.path, with: "")
                let depth = relative.split(separator: "/").count
                if relative.contains("/Contents/") || depth > 4 {
                    enumerator.skipDescendants()
                    continue
                }
                if item.pathExtension.lowercased() == "app" {
                    depthNotes.append(item)
                    enumerator.skipDescendants()
                }
            }
            depthNotes.sorted { lhs, rhs in
                if lhs.pathComponents.count != rhs.pathComponents.count {
                    return lhs.pathComponents.count < rhs.pathComponents.count
                }
                return lhs.lastPathComponent < rhs.lastPathComponent
            }.forEach(consider)
        }

        return found.sorted { lhs, rhs in
            if lhs.pathComponents.count != rhs.pathComponents.count {
                return lhs.pathComponents.count < rhs.pathComponents.count
            }
            return lhs.lastPathComponent < rhs.lastPathComponent
        }
    }

    private func chooseApplication(from apps: [URL]) -> URL? {
        apps.first
    }
    #endif

    private func unavailable(path: String, kind: ArtifactKind, method: String, detail: String) -> ContainerUnpackResult {
        ContainerUnpackResult(
            inspection: ContainerInspection(
                kind: kind,
                unpackMethod: method,
                nestedApplicationPath: nil,
                available: false,
                detail: detail
            ),
            nestedAppPath: nil,
            evidence: [Evidence(
                id: "container.unavailable",
                kind: .container,
                source: path,
                detail: detail
            )],
            findings: [Finding(
                id: "container.unavailable",
                status: .unavailable,
                severity: .error,
                confidence: .low,
                title: "Container inspection unavailable",
                explanation: detail,
                evidenceReferences: ["container.unavailable"]
            )],
            cleanup: {}
        )
    }

    private func commandDetail(_ result: CommandResult) -> String {
        [result.launchError, result.stderr, result.stdout]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
