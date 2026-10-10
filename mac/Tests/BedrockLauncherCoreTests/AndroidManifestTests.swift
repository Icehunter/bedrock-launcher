import Foundation
import Testing
@testable import BedrockLauncherCore

@Suite struct AndroidManifestTests {
    let expected = AndroidManifest(package: "com.mojang.minecraftpe", versionName: "1.26.52.3", versionCode: 972605203)

    @Test func readsVersionFromUTF16Pool() throws {
        let data = AXMLFixture.make(package: "com.mojang.minecraftpe", versionName: "1.26.52.3", versionCode: 972605203, utf8: false)
        #expect(try AndroidManifest.read(data) == expected)
    }

    @Test func readsVersionFromUTF8Pool() throws {
        let data = AXMLFixture.make(package: "com.mojang.minecraftpe", versionName: "1.26.52.3", versionCode: 972605203, utf8: true)
        #expect(try AndroidManifest.read(data) == expected)
    }

    @Test func rejectsPlainText() {
        #expect(throws: AndroidManifest.Error.notBinaryXML) { try AndroidManifest.read(Data("<manifest/>".utf8)) }
    }

    @Test func rejectsTruncatedFile() {
        let data = AXMLFixture.make(package: "p", versionName: "1.0", versionCode: 1, utf8: false)
        #expect(throws: AndroidManifest.Error.notBinaryXML) { try AndroidManifest.read(data.prefix(60)) }
    }

    @Test func reportsMissingVersionCode() {
        let data = AXMLFixture.make(package: "p", versionName: "1.0", versionCode: nil, utf8: false)
        #expect(throws: AndroidManifest.Error.missing("versionCode")) { try AndroidManifest.read(data) }
    }
}
