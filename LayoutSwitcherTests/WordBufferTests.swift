import CoreGraphics
import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct WordBufferTests {
    @Test func appendAccumulatesCharacters() {
        let buffer = Self.makeBuffer()
        buffer.append(KeyEvent(keyCode: 5, flags: [], unicode: "g", timestamp: 1))
        buffer.append(KeyEvent(keyCode: 4, flags: [], unicode: "h", timestamp: 2))
        #expect(buffer.characters.count == 2)
        #expect(buffer.characters.map(\.unicode) == ["g", "h"])
    }

    @Test func commitEmitsWordAndClearsBuffer() {
        let buffer = Self.makeBuffer()
        var committed: CommittedWord?
        buffer.onCommitted = { word in committed = word }
        buffer.append(KeyEvent(keyCode: 5, flags: [], unicode: "g", timestamp: 1))
        buffer.commit(separator: .space, separatorKeyCode: 49)
        #expect(committed != nil)
        #expect(committed?.text == "g")
        #expect(committed?.separator == .space)
        #expect(buffer.characters.isEmpty)
        #expect(buffer.lastCommitted?.text == "g")
    }

    @Test func deleteLastRemovesOneCharacter() {
        let buffer = Self.makeBuffer()
        buffer.append(KeyEvent(keyCode: 5, flags: [], unicode: "g", timestamp: 1))
        buffer.append(KeyEvent(keyCode: 4, flags: [], unicode: "h", timestamp: 2))
        buffer.deleteLast()
        #expect(buffer.characters.count == 1)
        #expect(buffer.characters.first?.unicode == "g")
    }

    @Test func resetClearsBufferAndLastCommitted() {
        let buffer = Self.makeBuffer()
        buffer.append(KeyEvent(keyCode: 5, flags: [], unicode: "g", timestamp: 1))
        buffer.commit(separator: .space, separatorKeyCode: 49)
        buffer.reset(reason: .appChanged)
        #expect(buffer.characters.isEmpty)
        #expect(buffer.lastCommitted == nil)
    }

    @Test func clearLastCommittedDoesNotAffectCharacters() {
        let buffer = Self.makeBuffer()
        buffer.append(KeyEvent(keyCode: 5, flags: [], unicode: "g", timestamp: 1))
        buffer.append(KeyEvent(keyCode: 4, flags: [], unicode: "h", timestamp: 2))
        buffer.clearLastCommitted()
        #expect(buffer.characters.count == 2)
        #expect(buffer.lastCommitted == nil)
    }

    @Test func appendAfterCommitClearsLastCommitted() {
        let buffer = Self.makeBuffer()
        buffer.append(KeyEvent(keyCode: 5, flags: [], unicode: "g", timestamp: 1))
        buffer.commit(separator: .space, separatorKeyCode: 49)
        #expect(buffer.lastCommitted != nil)
        buffer.append(KeyEvent(keyCode: 4, flags: [], unicode: "h", timestamp: 2))
        #expect(buffer.lastCommitted == nil)
    }

    @Test func resetWithNavigationKeepsLastCommitted() {
        let buffer = Self.makeBuffer()
        buffer.append(KeyEvent(keyCode: 5, flags: [], unicode: "g", timestamp: 1))
        buffer.commit(separator: .space, separatorKeyCode: 49)
        // .navigation clears lastCommitted per current implementation
        buffer.reset(reason: .navigation)
        #expect(buffer.lastCommitted == nil)
    }

    private static func makeBuffer() -> WordBuffer {
        WordBuffer(now: { Date(timeIntervalSinceReferenceDate: 1_000) })
    }
}
