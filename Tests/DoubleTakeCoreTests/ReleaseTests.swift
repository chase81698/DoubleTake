import CryptoKit
import Foundation
import Testing
@testable import DoubleTakeCore

@Suite struct ReleaseTests {
    @Test func parsesVersions() {
        #expect(AppVersion("1.2.3")?.parts == [1, 2, 3])
        #expect(AppVersion("v1.0")?.parts == [1, 0])
        #expect(AppVersion("1.x") == nil)
        #expect(AppVersion("1..2") == nil)
        #expect(AppVersion("") == nil)
        #expect(AppVersion("dev") == nil)
    }

    @Test func comparesVersions() throws {
        func v(_ s: String) throws -> AppVersion { try #require(AppVersion(s)) }
        #expect(try v("1.10.0") > v("1.9.9"))
        #expect(try v("1.0.1") > v("1.0"))
        #expect(try v("1.0") == v("1.0.0"))
        #expect(try v("v2") > v("1.99"))
        #expect(try !(v("1.0.0") < v("1.0.0")))
    }

    @Test func decodesGitHubRelease() throws {
        let json = """
        {"tag_name": "v1.1.0", "body": "Notes", "draft": false, "assets": [
          {"name": "DoubleTake.dmg", "browser_download_url": "https://example.com/DoubleTake.dmg", "size": 1},
          {"name": "DoubleTake.zip", "browser_download_url": "https://example.com/DoubleTake.zip", "size": 2}]}
        """
        let release = try JSONDecoder().decode(Release.self, from: Data(json.utf8))
        #expect(release.version == AppVersion("1.1.0"))
        #expect(release.notes == "Notes")
        #expect(release.archive?.downloadURL.absoluteString == "https://example.com/DoubleTake.zip")
    }

    @Test func releaseWithoutArchive() throws {
        let json = #"{"tag_name": "v1.1.0", "body": null, "assets": []}"#
        let release = try JSONDecoder().decode(Release.self, from: Data(json.utf8))
        #expect(release.archive == nil)
        #expect(release.notes == nil)
    }

    @Test func oldConfigsLeaveUpdateChecksOff() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"isEnabled": true}"#.utf8))
        #expect(settings.checkForUpdatesOnLaunch == false)
        #expect(AppSettings().checkForUpdatesOnLaunch == false)
    }
}

@Suite struct UpdateSecurityTests {
    let repo = "chase81698/DoubleTake"

    @Test(arguments: [
        "https://github.com/chase81698/DoubleTake/releases/download/v1.1.0/DoubleTake.zip",
        "https://GitHub.com/Chase81698/doubletake/releases/download/v2/DoubleTake.zip.sig",
    ])
    func trustsThisRepositorysReleases(_ url: String) throws {
        #expect(Release.isTrustedDownload(try #require(URL(string: url)), repo: repo))
    }

    @Test(arguments: [
        "http://github.com/chase81698/DoubleTake/releases/download/v1.1.0/DoubleTake.zip",
        "https://github.com.evil.example/chase81698/DoubleTake/releases/download/v1.1.0/DoubleTake.zip",
        "https://evil.example/chase81698/DoubleTake/releases/download/v1.1.0/DoubleTake.zip",
        "https://github.com/someone-else/DoubleTake/releases/download/v1.1.0/DoubleTake.zip",
        "https://github.com/chase81698/DoubleTake-fork/releases/download/v1.1.0/DoubleTake.zip",
        "https://github.com/chase81698/DoubleTake/raw/main/DoubleTake.zip",
        "https://user@github.com/chase81698/DoubleTake/releases/download/v1.1.0/DoubleTake.zip",
        "https://github.com:8443/chase81698/DoubleTake/releases/download/v1.1.0/DoubleTake.zip",
        "http://127.0.0.1:8765/DoubleTake.zip",
        "https://github.com/chase81698/DoubleTake/releases/download/../../../someone-else/x/releases/download/v1/DoubleTake.zip",
    ])
    func rejectsEverythingElse(_ url: String) throws {
        #expect(!Release.isTrustedDownload(try #require(URL(string: url)), repo: repo))
    }

    @Test func checksSignatures() {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let data = Data("DoubleTake.zip contents".utf8)
        let signature = (try! key.signature(for: data)).base64EncodedString()

        #expect(UpdateSignature.isValid(signature, for: data, publicKey: publicKey))
        #expect(UpdateSignature.isValid(signature + "\n", for: data, publicKey: publicKey))
        #expect(!UpdateSignature.isValid(signature, for: Data("tampered".utf8), publicKey: publicKey))
        let otherKey = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        #expect(!UpdateSignature.isValid(signature, for: data, publicKey: otherKey))
        #expect(!UpdateSignature.isValid("not base64!", for: data, publicKey: publicKey))
        #expect(!UpdateSignature.isValid(signature, for: data, publicKey: ""))
    }

    @Test func appCarriesAReleaseKey() {
        #expect(Data(base64Encoded: UpdateSignature.publicKey)?.count == 32)
    }

    @Test func findsTheSignatureAsset() throws {
        let json = """
        {"tag_name": "v1.1.0", "assets": [
          {"name": "DoubleTake.zip", "browser_download_url": "https://example.com/a"},
          {"name": "DoubleTake.zip.sig", "browser_download_url": "https://example.com/b"}]}
        """
        let release = try JSONDecoder().decode(Release.self, from: Data(json.utf8))
        #expect(release.signature?.downloadURL.absoluteString == "https://example.com/b")
    }
}
