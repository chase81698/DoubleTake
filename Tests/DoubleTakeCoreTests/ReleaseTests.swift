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
