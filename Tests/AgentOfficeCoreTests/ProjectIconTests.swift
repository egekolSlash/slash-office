import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct ProjectIconTests {
    private func makeProject(_ files: [String: String]) throws -> String {
        // Enumerator `/private/var/...` döndürür; `resolvingSymlinksInPath` ise `/private`'ı atar, realpath atmaz.
        let tmp = String(cString: realpath(FileManager.default.temporaryDirectory.path, nil))
        let root = URL(fileURLWithPath: tmp).appendingPathComponent(UUID().uuidString)
        for (path, content) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return root.path
    }

    @Test func unityIconResolvedThroughMetaGUID() throws {
        let guid = "c582db692cff14089a49fca231d3c3db"
        let dir = try makeProject([
            "ProjectSettings/ProjectSettings.asset": """
              m_BuildTargetIcons:
              - m_BuildTarget:
                m_Icons:
                - serializedVersion: 2
                  m_Icon: {fileID: 2800000, guid: \(guid), type: 3}
            """,
            "Assets/Art/Other.png.meta": "fileFormatVersion: 2\nguid: 00000000000000000000000000000000\n",
            "Assets/Art/Icon/App_Icon.png": "png",
            "Assets/Art/Icon/App_Icon.png.meta": "fileFormatVersion: 2\nguid: \(guid)\n",
        ])
        #expect(ProjectIconLocator.locate(directory: dir) == .image(path: "\(dir)/Assets/Art/Icon/App_Icon.png"))
    }

    @Test func unityWithoutIconFallsBackToKind() throws {
        let dir = try makeProject(["ProjectSettings/ProjectSettings.asset": "m_BuildTargetIcons: []\n"])
        #expect(ProjectIconLocator.locate(directory: dir) == .kind(.unity))
    }

    @Test func xcodeAppIconPicksLargestPNG() throws {
        let dir = try makeProject([
            "App/Assets.xcassets/AppIcon.appiconset/small.png": "s",
            "App/Assets.xcassets/AppIcon.appiconset/large.png": String(repeating: "x", count: 100),
            "Package.swift": "",
        ])
        #expect(ProjectIconLocator.locate(directory: dir) == .image(path: "\(dir)/App/Assets.xcassets/AppIcon.appiconset/large.png"))
    }

    @Test func commonIconFilesAndKinds() throws {
        let web = try makeProject(["package.json": "{}", "public/favicon.png": "p"])
        #expect(ProjectIconLocator.locate(directory: web) == .image(path: "\(web)/public/favicon.png"))
        #expect(ProjectIconLocator.locate(directory: try makeProject(["Package.swift": ""])) == .kind(.swift))
        #expect(ProjectIconLocator.locate(directory: try makeProject(["package.json": "{}"])) == .kind(.web))
        #expect(ProjectIconLocator.locate(directory: try makeProject(["README.md": ""])) == .kind(.generic))
    }
}
