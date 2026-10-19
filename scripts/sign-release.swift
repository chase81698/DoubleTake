// Signs a release archive with DoubleTake's release key, so the in-app updater will install it.
//   swift scripts/sign-release.swift dist/DoubleTake.zip   writes dist/DoubleTake.zip.sig
//   swift scripts/sign-release.swift --generate             creates the key (once) and builds its public half into the app
// The private key lives only in your login Keychain, as "DoubleTake release signing key". Back it up
// (Keychain Access › that item › Show password): without it, installed copies can't verify new releases
// and people would have to reinstall from the DMG.
import CryptoKit
import Foundation
import Security

let service = "DoubleTake release signing key"
let account = "chase81698/DoubleTake"
let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let keyFile = root.appendingPathComponent("Sources/DoubleTakeCore/UpdateSignature.swift")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func loadKey() -> Curve25519.Signing.PrivateKey? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
        kSecAttrAccount as String: account, kSecReturnData as String: true,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let stored = item as? Data, let raw = Data(base64Encoded: stored) else { return nil }
    return try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
}

func builtInPublicKey() -> String {
    guard let source = try? String(contentsOf: keyFile, encoding: .utf8),
          let line = source.split(separator: "\n").first(where: { $0.contains("static let publicKey = \"") }),
          let start = line.firstIndex(of: "\""), let end = line.lastIndex(of: "\""), start < end else {
        fail("couldn't find publicKey in \(keyFile.path)")
    }
    return String(line[line.index(after: start)..<end])
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments == ["--generate"] {
    if loadKey() != nil { fail("a release key is already in your Keychain; refusing to replace it") }
    let key = Curve25519.Signing.PrivateKey()
    let add: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
        kSecAttrAccount as String: account, kSecAttrLabel as String: service,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        kSecValueData as String: Data(key.rawRepresentation.base64EncodedString().utf8),
    ]
    let status = SecItemAdd(add as CFDictionary, nil)
    guard status == errSecSuccess else { fail("couldn't save the key to your Keychain (OSStatus \(status))") }
    let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
    let source = try String(contentsOf: keyFile, encoding: .utf8)
        .replacingOccurrences(of: "static let publicKey = \"\(builtInPublicKey())\"", with: "static let publicKey = \"\(publicKey)\"")
    try source.write(to: keyFile, atomically: true, encoding: .utf8)
    print("Saved the private key to your Keychain as \"\(service)\". Back it up somewhere safe.")
    print("Public key \(publicKey) written to \(keyFile.path)")
    exit(0)
}

guard arguments.count == 1, !arguments[0].hasPrefix("-") else {
    fail("usage: swift scripts/sign-release.swift <DoubleTake.zip> | --generate")
}
guard let key = loadKey() else { fail("no release key in your Keychain; run with --generate first") }
let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
guard publicKey == builtInPublicKey() else {
    fail("the key in your Keychain doesn't match the public key built into the app (\(keyFile.lastPathComponent))")
}
let archive = URL(fileURLWithPath: arguments[0])
guard let data = try? Data(contentsOf: archive) else { fail("can't read \(archive.path)") }
let signature = try key.signature(for: data).base64EncodedString()
guard key.publicKey.isValidSignature(Data(base64Encoded: signature)!, for: data) else { fail("signature didn't verify") }
let out = archive.appendingPathExtension("sig")
try (signature + "\n").write(to: out, atomically: true, encoding: .utf8)
print("Wrote \(out.path)")
