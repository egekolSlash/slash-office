import Foundation
@testable import AgentOfficeCore

func json(_ text: String) -> JSONValue {
    try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

func fixture(_ provider: String, _ name: String) throws -> JSONValue {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/\(provider)") else {
        throw CocoaError(.fileNoSuchFile)
    }
    return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
}
