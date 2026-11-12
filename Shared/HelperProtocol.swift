import Foundation
import Security

/// The XPC contract between Ember.app and its root helper. The helper only ever touches
/// the MagSafe light key, and only with the values in `SMCKey.allowedLEDValues`.
@objc(EmberHelperProtocol)
protocol EmberHelperProtocol {
    /// Writes one value to the MagSafe light. Replies 0 on success, otherwise an error code and message.
    func setLight(_ value: UInt8, withReply reply: @escaping (Int32, String?) -> Void)
    /// Reports the helper's build so the app can tell when an old helper is still registered.
    func helperVersion(withReply reply: @escaping (String) -> Void)
    /// Asks the helper to exit after replying. launchd starts the (possibly updated) binary
    /// from the app bundle on the next connection. Used after an app update.
    func quit(withReply reply: @escaping () -> Void)
}

enum EmberIdentity {
    /// Bump whenever EmberHelper/ or Shared/ changes, so installed helpers get restarted.
    static let helperVersion = "1.1.0"

    /// Bundle IDs are derived at runtime so changing the prefix in Config/Signing.xcconfig is enough.
    /// App: <prefix>.ember   Helper: <prefix>.ember.helper
    static var appBundleID: String {
        let own = Bundle.main.bundleIdentifier ?? "TME.ember"
        return own.hasSuffix(".helper") ? String(own.dropLast(".helper".count)) : own
    }

    static var helperLabel: String { appBundleID + ".helper" }
    static var machServiceName: String { helperLabel }
    static var helperPlistName: String { helperLabel + ".plist" }

    /// Team ID this process is signed with, if any.
    static func ownTeamID() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Code-signing requirement for the other side of the XPC connection: Apple-issued certificate,
    /// same team, exact identifier. Returns nil when this process has no team (ad-hoc or unsigned),
    /// in which case the caller must refuse to talk, because an identifier alone can be forged.
    static func requirement(forIdentifier identifier: String) -> String? {
        guard let team = ownTeamID(), !team.isEmpty else { return nil }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
}
