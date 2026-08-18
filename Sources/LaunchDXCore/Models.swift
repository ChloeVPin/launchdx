import Foundation

public enum FindingStatus: String, Codable, CaseIterable {
    case passed
    case failed
    case warning
    case skipped
    case unavailable
    case inconclusive
}

public enum Severity: String, Codable, CaseIterable {
    case blocker
    case error
    case warning
    case information
}

public enum Confidence: String, Codable, CaseIterable {
    case confirmed
    case high
    case medium
    case low
}

public enum DiagnosisClassification: String, Codable, CaseIterable {
    case clean
    case confirmedBlocker = "confirmed_blocker"
    case likelyBlocker = "likely_blocker"
    case warning
    case unrelatedIssue = "unrelated_issue"
    case unavailableEvidence = "unavailable_evidence"
    case postLaunchProblem = "post_launch_problem"
    case inconclusive
}

public enum LaunchStatus: String, Codable {
    case clean
    case blocked
    case inconclusive
}

public enum InspectionStatus: String, Codable {
    case complete
    case targetMissing = "target_missing"
    case invalidTarget = "invalid_target"
    case permissionLimited = "permission_limited"
    case securityUnavailable = "security_unavailable"
}

public enum ArtifactKind: String, Codable {
    case applicationBundle = "application_bundle"
    case diskImage = "disk_image"
    case installerPackage = "installer_package"
    case directory
    case file
    case missing
    case unknown
}

public enum EvidenceKind: String, Codable {
    case filesystem
    case infoPlist = "info_plist"
    case macho
    case security
    case notarization
    case gatekeeper
    case quarantine
    case container
    case process
    case inference
}

public struct Evidence: Codable, Equatable, Identifiable {
    public let id: String
    public let kind: EvidenceKind
    public let source: String
    public let detail: String
    public let observed: Bool

    public init(
        id: String,
        kind: EvidenceKind,
        source: String,
        detail: String,
        observed: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.detail = detail
        self.observed = observed
    }
}

public struct SuggestedAction: Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let safeToAutomate: Bool

    public init(
        id: String,
        title: String,
        detail: String,
        safeToAutomate: Bool = false
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.safeToAutomate = safeToAutomate
    }
}

public struct Finding: Codable, Equatable, Identifiable {
    public let id: String
    public let status: FindingStatus
    public let severity: Severity
    public let confidence: Confidence
    public let title: String
    public let explanation: String
    public let evidenceReferences: [String]
    public let suggestedActions: [SuggestedAction]

    public init(
        id: String,
        status: FindingStatus,
        severity: Severity,
        confidence: Confidence,
        title: String,
        explanation: String,
        evidenceReferences: [String] = [],
        suggestedActions: [SuggestedAction] = []
    ) {
        self.id = id
        self.status = status
        self.severity = severity
        self.confidence = confidence
        self.title = title
        self.explanation = explanation
        self.evidenceReferences = evidenceReferences
        self.suggestedActions = suggestedActions
    }
}

public struct Diagnosis: Codable, Equatable {
    public let classification: DiagnosisClassification
    public let primaryFindingID: String?
    public let triggerFindingIDs: [String]
    public let summary: String
    public let confidence: Confidence
    public let limitations: [String]

    public init(
        classification: DiagnosisClassification,
        primaryFindingID: String? = nil,
        triggerFindingIDs: [String] = [],
        summary: String,
        confidence: Confidence,
        limitations: [String] = []
    ) {
        self.classification = classification
        self.primaryFindingID = primaryFindingID
        self.triggerFindingIDs = triggerFindingIDs
        self.summary = summary
        self.confidence = confidence
        self.limitations = limitations
    }
}

public struct TargetInspection: Codable, Equatable {
    public let inputPath: String
    public let resolvedPath: String?
    public let kind: ArtifactKind
    public let exists: Bool
    public let isDirectory: Bool
    public let isReadable: Bool

    public init(
        inputPath: String,
        resolvedPath: String?,
        kind: ArtifactKind,
        exists: Bool,
        isDirectory: Bool,
        isReadable: Bool
    ) {
        self.inputPath = inputPath
        self.resolvedPath = resolvedPath
        self.kind = kind
        self.exists = exists
        self.isDirectory = isDirectory
        self.isReadable = isReadable
    }
}

public enum MachOFormat: String, Codable {
    case thin
    case universal
    case unknown
}

public struct MachOSliceInspection: Codable, Equatable {
    public let architecture: String
    public let cpuType: UInt32
    public let is64Bit: Bool?
    public let minimumOSVersion: String?
    public let sdkVersion: String?
    public let hasCodeSignatureLoadCommand: Bool
    public let codeSignatureRangeValid: Bool
    public let isMalformed: Bool
    public let error: String?

    public init(
        architecture: String,
        cpuType: UInt32,
        is64Bit: Bool?,
        minimumOSVersion: String?,
        sdkVersion: String?,
        hasCodeSignatureLoadCommand: Bool,
        codeSignatureRangeValid: Bool,
        isMalformed: Bool,
        error: String?
    ) {
        self.architecture = architecture
        self.cpuType = cpuType
        self.is64Bit = is64Bit
        self.minimumOSVersion = minimumOSVersion
        self.sdkVersion = sdkVersion
        self.hasCodeSignatureLoadCommand = hasCodeSignatureLoadCommand
        self.codeSignatureRangeValid = codeSignatureRangeValid
        self.isMalformed = isMalformed
        self.error = error
    }
}

public struct MachOInspection: Codable, Equatable {
    public let path: String
    public let format: MachOFormat
    public let isReadable: Bool
    public let isMachO: Bool
    public let isMalformed: Bool
    public let architectures: [String]
    public let supportsArm64: Bool
    public let supportsX86_64: Bool
    public let minimumOSVersion: String?
    public let sdkVersion: String?
    public let hasCodeSignatureLoadCommand: Bool
    public let codeSignatureRangeValid: Bool
    public let slices: [MachOSliceInspection]
    public let error: String?

    public init(
        path: String,
        format: MachOFormat,
        isReadable: Bool = true,
        isMachO: Bool,
        isMalformed: Bool,
        architectures: [String],
        supportsArm64: Bool,
        supportsX86_64: Bool,
        minimumOSVersion: String?,
        sdkVersion: String?,
        hasCodeSignatureLoadCommand: Bool,
        codeSignatureRangeValid: Bool,
        slices: [MachOSliceInspection],
        error: String?
    ) {
        self.path = path
        self.format = format
        self.isReadable = isReadable
        self.isMachO = isMachO
        self.isMalformed = isMalformed
        self.architectures = architectures
        self.supportsArm64 = supportsArm64
        self.supportsX86_64 = supportsX86_64
        self.minimumOSVersion = minimumOSVersion
        self.sdkVersion = sdkVersion
        self.hasCodeSignatureLoadCommand = hasCodeSignatureLoadCommand
        self.codeSignatureRangeValid = codeSignatureRangeValid
        self.slices = slices
        self.error = error
    }
}

public enum SignatureState: String, Codable {
    case valid
    case invalid
    case unsigned
    case adHoc = "ad_hoc"
    case unavailable
    case inconclusive
}

public enum AssessmentResult: String, Codable {
    case accepted
    case rejected
    case unavailable
    case inconclusive
}

public enum StapleStatus: String, Codable {
    case valid
    case absent
    case invalid
    case unavailable
    case inconclusive
}

public struct NestedCodeInspection: Codable, Equatable {
    public let pathsChecked: [String]
    public let invalidPaths: [String]
    public let unsignedPaths: [String]
    public let unavailablePaths: [String]
    public let teamIDs: [String]
    public let mismatchedTeamIDPaths: [String]

    public init(
        pathsChecked: [String] = [],
        invalidPaths: [String] = [],
        unsignedPaths: [String] = [],
        unavailablePaths: [String] = [],
        teamIDs: [String] = [],
        mismatchedTeamIDPaths: [String] = []
    ) {
        self.pathsChecked = pathsChecked
        self.invalidPaths = invalidPaths
        self.unsignedPaths = unsignedPaths
        self.unavailablePaths = unavailablePaths
        self.teamIDs = teamIDs
        self.mismatchedTeamIDPaths = mismatchedTeamIDPaths
    }
}

public struct SignatureInspection: Codable, Equatable {
    public let state: SignatureState
    public let identity: String?
    public let teamID: String?
    public let identifier: String?
    public let hardenedRuntime: Bool?
    public let entitlements: [String: JSONValue]
    public let nested: NestedCodeInspection
    public let apiValidation: String?
    public let rawVerification: String?

    public init(
        state: SignatureState,
        identity: String? = nil,
        teamID: String? = nil,
        identifier: String? = nil,
        hardenedRuntime: Bool? = nil,
        entitlements: [String: JSONValue] = [:],
        nested: NestedCodeInspection = NestedCodeInspection(),
        apiValidation: String? = nil,
        rawVerification: String? = nil
    ) {
        self.state = state
        self.identity = identity
        self.teamID = teamID
        self.identifier = identifier
        self.hardenedRuntime = hardenedRuntime
        self.entitlements = entitlements
        self.nested = nested
        self.apiValidation = apiValidation
        self.rawVerification = rawVerification
    }
}

public enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public init(propertyList value: Any) {
        switch value {
        case let value as String: self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() { self = .boolean(value.boolValue) }
            else { self = .number(value.doubleValue) }
        case let value as [String: Any]: self = .object(value.mapValues(JSONValue.init(propertyList:)))
        case let value as [Any]: self = .array(value.map(JSONValue.init(propertyList:)))
        default: self = .null
        }
    }
}

public struct NotarizationInspection: Codable, Equatable {
    public let staple: StapleStatus
    public let detail: String?

    public init(staple: StapleStatus, detail: String? = nil) {
        self.staple = staple
        self.detail = detail
    }
}

public struct GatekeeperInspection: Codable, Equatable {
    public let result: AssessmentResult
    public let detail: String?

    public init(result: AssessmentResult, detail: String? = nil) {
        self.result = result
        self.detail = detail
    }
}

public struct QuarantineInspection: Codable, Equatable {
    public let present: Bool
    public let flags: UInt32?
    public let timestamp: Date?
    public let agent: String?
    public let eventIdentifier: String?
    public let rawValue: String?

    public init(
        present: Bool,
        flags: UInt32? = nil,
        timestamp: Date? = nil,
        agent: String? = nil,
        eventIdentifier: String? = nil,
        rawValue: String? = nil
    ) {
        self.present = present
        self.flags = flags
        self.timestamp = timestamp
        self.agent = agent
        self.eventIdentifier = eventIdentifier
        self.rawValue = rawValue
    }
}

public struct SecurityInspection: Codable, Equatable {
    public let signature: SignatureInspection
    public let notarization: NotarizationInspection
    public let gatekeeper: GatekeeperInspection
    public let quarantine: QuarantineInspection

    public init(
        signature: SignatureInspection,
        notarization: NotarizationInspection,
        gatekeeper: GatekeeperInspection,
        quarantine: QuarantineInspection
    ) {
        self.signature = signature
        self.notarization = notarization
        self.gatekeeper = gatekeeper
        self.quarantine = quarantine
    }
}

public struct ContainerInspection: Codable, Equatable {
    public let kind: ArtifactKind
    public let unpackMethod: String
    public let nestedApplicationPath: String?
    public let available: Bool
    public let detail: String?

    public init(
        kind: ArtifactKind,
        unpackMethod: String,
        nestedApplicationPath: String? = nil,
        available: Bool,
        detail: String? = nil
    ) {
        self.kind = kind
        self.unpackMethod = unpackMethod
        self.nestedApplicationPath = nestedApplicationPath
        self.available = available
        self.detail = detail
    }
}

public struct BundleInspection: Codable, Equatable {
    public let bundlePath: String
    public let infoPlistPath: String
    public let infoPlistReadable: Bool
    public let infoPlistValid: Bool
    public let bundleIdentifier: String?
    public let executableName: String?
    public let executablePath: String?
    public let executableExists: Bool
    public let executableIsRegularFile: Bool
    public let executableReadable: Bool
    public let macho: MachOInspection?
    public let security: SecurityInspection?

    public init(
        bundlePath: String,
        infoPlistPath: String,
        infoPlistReadable: Bool,
        infoPlistValid: Bool,
        bundleIdentifier: String?,
        executableName: String?,
        executablePath: String?,
        executableExists: Bool,
        executableIsRegularFile: Bool,
        executableReadable: Bool,
        macho: MachOInspection? = nil,
        security: SecurityInspection? = nil
    ) {
        self.bundlePath = bundlePath
        self.infoPlistPath = infoPlistPath
        self.infoPlistReadable = infoPlistReadable
        self.infoPlistValid = infoPlistValid
        self.bundleIdentifier = bundleIdentifier
        self.executableName = executableName
        self.executablePath = executablePath
        self.executableExists = executableExists
        self.executableIsRegularFile = executableIsRegularFile
        self.executableReadable = executableReadable
        self.macho = macho
        self.security = security
    }
}

public struct EnvironmentInfo: Codable, Equatable {
    public let operatingSystem: String
    public let hostArchitecture: String
    public let appleSilicon: Bool

    public init(
        operatingSystem: String,
        hostArchitecture: String,
        appleSilicon: Bool
    ) {
        self.operatingSystem = operatingSystem
        self.hostArchitecture = hostArchitecture
        self.appleSilicon = appleSilicon
    }

    public static var current: EnvironmentInfo {
        #if arch(arm64)
        let architecture = "arm64"
        let appleSilicon = true
        #elseif arch(x86_64)
        let architecture = "x86_64"
        let appleSilicon = false
        #else
        let architecture = "unknown"
        let appleSilicon = false
        #endif

        return EnvironmentInfo(
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            hostArchitecture: architecture,
            appleSilicon: appleSilicon
        )
    }
}

public struct DiagnosticReport: Codable, Equatable {
    public let schemaVersion: String
    public let toolVersion: String
    public let target: TargetInspection
    public let environment: EnvironmentInfo
    public let inspectionStatus: InspectionStatus
    public let launchStatus: LaunchStatus
    public let bundle: BundleInspection?
    public let container: ContainerInspection?
    public let findings: [Finding]
    public let diagnosis: Diagnosis
    public let evidence: [Evidence]

    public init(
        schemaVersion: String = LaunchDXVersion.schema,
        toolVersion: String = LaunchDXVersion.current,
        target: TargetInspection,
        environment: EnvironmentInfo = .current,
        inspectionStatus: InspectionStatus,
        launchStatus: LaunchStatus,
        bundle: BundleInspection?,
        container: ContainerInspection? = nil,
        findings: [Finding],
        diagnosis: Diagnosis,
        evidence: [Evidence]
    ) {
        self.schemaVersion = schemaVersion
        self.toolVersion = toolVersion
        self.target = target
        self.environment = environment
        self.inspectionStatus = inspectionStatus
        self.launchStatus = launchStatus
        self.bundle = bundle
        self.container = container
        self.findings = findings
        self.diagnosis = diagnosis
        self.evidence = evidence
    }

    public var exitCode: LaunchDXExitCode {
        if launchStatus == .blocked {
            return .blocked
        }

        switch inspectionStatus {
        case .targetMissing:
            return .noInput
        case .invalidTarget:
            return .dataError
        case .permissionLimited:
            return .noPermission
        case .securityUnavailable:
            return .unavailable
        case .complete:
            return .ok
        }
    }
}

public enum LaunchDXExitCode: Int32, Codable {
    case ok = 0
    case blocked = 1
    case usage = 64
    case dataError = 65
    case noInput = 66
    case unavailable = 69
    case software = 70
    case noPermission = 77
    case configuration = 78
}

public enum CLICommand: Equatable {
    case diagnose
    case evidence
}

public struct CLIOptions: Equatable {
    public let command: CLICommand
    public let path: String
    public let json: Bool
    public let verbose: Bool
    public let noColor: Bool

    public init(
        command: CLICommand,
        path: String,
        json: Bool = false,
        verbose: Bool = false,
        noColor: Bool = false
    ) {
        self.command = command
        self.path = path
        self.json = json
        self.verbose = verbose
        self.noColor = noColor
    }
}

public struct CheckerResult: Equatable {
    public let findings: [Finding]
    public let evidence: [Evidence]

    public init(findings: [Finding], evidence: [Evidence]) {
        self.findings = findings
        self.evidence = evidence
    }
}

public protocol DiagnosticChecker {
    var id: String { get }
    func check(target: TargetInspection) -> CheckerResult
}
