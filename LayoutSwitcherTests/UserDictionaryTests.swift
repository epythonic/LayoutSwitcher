import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct UserDictionaryTests {
    @Test func initLoadsWordsThroughInjectedReadClosure() throws {
        let url = URL(fileURLWithPath: "/tmp/user-dict-ro.json")
        let payload = ["words": ["  Hello ", "", "Țară"]]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let dictionary = UserDictionary(
            language: .ro,
            storageURL: url,
            fileExists: { path in path == url.path },
            readData: { requestedURL in
                #expect(requestedURL == url)
                return data
            },
            writeData: { _, _ in }
        )

        #expect(dictionary.contains("hello"))
        #expect(dictionary.contains("țară"))
        #expect(dictionary.size == 2)
    }

    @Test func addPersistsThroughInjectedStorageClosures() throws {
        let url = URL(fileURLWithPath: "/tmp/user-dict-en.json")
        var createdDirectory: URL?
        var writtenData: Data?

        let dictionary = UserDictionary(
            language: .en,
            storageURL: url,
            createDirectory: { directory in
                createdDirectory = directory
            },
            fileExists: { _ in false },
            readData: { _ in Data() },
            writeData: { data, targetURL in
                #expect(targetURL == url)
                writtenData = data
            }
        )

        dictionary.add(" Hello ")

        #expect(dictionary.contains("hello"))
        #expect(createdDirectory == url.deletingLastPathComponent())

        let data = try #require(writtenData)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: [String]]
        #expect(payload?["words"] == ["hello"])
    }
}
