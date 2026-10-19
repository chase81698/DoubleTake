import CryptoKit
import Foundation

/// Proves an update came from DoubleTake's maintainer. Each release's DoubleTake.zip is signed with a
/// private Ed25519 key that never leaves the maintainer's Keychain (scripts/sign-release.swift), and the
/// signature is published next to it as DoubleTake.zip.sig. The app carries only the public half, so
/// nobody else can produce a download it will install, even with access to the GitHub repo.
public enum UpdateSignature {
    /// The public half of the release-signing key, base64. `swift scripts/sign-release.swift --generate` writes it.
    public static let publicKey = "9xt0Wgv9KXkMQsauRusYZym1PoxRBVjK8VTS0oO6bMs="
    public static let fileName = "DoubleTake.zip.sig"

    /// Whether `signature` (base64, as in DoubleTake.zip.sig) is the release key's signature of `data`.
    public static func isValid(_ signature: String, for data: Data, publicKey: String = publicKey) -> Bool {
        guard let signatureData = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)),
              let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { return false }
        return key.isValidSignature(signatureData, for: data)
    }
}
