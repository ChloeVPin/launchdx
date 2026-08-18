import Foundation

enum DiagnosisComposer {
    static func compose(
        findings: [Finding],
        securityInspection: SecurityInspection?,
        permissionLimited: Bool,
        extraLimitations: [String] = []
    ) -> (inspectionStatus: InspectionStatus, launchStatus: LaunchStatus, diagnosis: Diagnosis) {
        let hasBlocker = findings.contains { $0.severity == .blocker && $0.status == .failed }
        let primary = findings.first { $0.severity == .blocker && $0.status == .failed } ?? findings.first
        let signatureBlocker = findings.first { $0.id.hasPrefix("signature.") && $0.severity == .blocker && $0.status == .failed }
        let gatekeeperRejected = findings.contains { $0.id == "gatekeeper.assessment" && $0.status == .failed }
        let quarantinePresent = findings.contains { $0.id == "quarantine.present" || $0.id == "container.quarantine" }
        var triggerIDs: [String] = []
        if findings.contains(where: { $0.id == "quarantine.present" }) {
            triggerIDs.append("quarantine.present")
        }
        if findings.contains(where: { $0.id == "container.quarantine" }) {
            triggerIDs.append("container.quarantine")
        }
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
        var limitations: [String] = {
            #if os(macOS)
            return ["Nested code is scanned from common bundle locations; unified logs, TCC, sandbox, and App Translocation are not inspected yet."]
            #else
            return ["Apple security checks require macOS and were not available in this build."]
            #endif
        }()
        limitations.append(contentsOf: extraLimitations)

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
        return (inspectionStatus, launchStatus, diagnosis)
    }
}
