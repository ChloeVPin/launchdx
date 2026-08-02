import Foundation
#if canImport(Security)
import Security
#endif

protocol SecurityFrameworkChecking {
    func inspect(path: String) -> SecurityFrameworkResult
}

struct SecurityFrameworkResult {
    let available: Bool
    let valid: Bool?
    let identifier: String?
    let teamID: String?
    let detail: String
}

struct SecurityFrameworkInspector: SecurityFrameworkChecking {
    func inspect(path: String) -> SecurityFrameworkResult {
        #if os(macOS) && canImport(Security)
        let url = URL(fileURLWithPath: path)
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return SecurityFrameworkResult(
                available: true,
                valid: nil,
                identifier: nil,
                teamID: nil,
                detail: "SecStaticCodeCreateWithPath failed with OSStatus \(createStatus)."
            )
        }
        let validationFlags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode)
        let validationStatus = SecStaticCodeCheckValidity(staticCode, validationFlags, nil)
        var signingInformation: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        let info = signingInformation as NSDictionary?
        let identifier = info?[kSecCodeInfoIdentifier as String] as? String
        let teamID = info?[kSecCodeInfoTeamIdentifier as String] as? String
        let metadata = "SecStaticCodeCheckValidity OSStatus=\(validationStatus); " +
            "SecCodeCopySigningInformation OSStatus=\(infoStatus); " +
            "identifier=\(identifier ?? "unavailable"); " +
            "teamID=\(teamID ?? "unavailable")"
        return SecurityFrameworkResult(
            available: true,
            valid: validationStatus == errSecSuccess,
            identifier: identifier,
            teamID: teamID,
            detail: metadata
        )
        #else
        return SecurityFrameworkResult(
            available: false,
            valid: nil,
            identifier: nil,
            teamID: nil,
            detail: "Security.framework validation requires macOS."
        )
        #endif
    }
}
