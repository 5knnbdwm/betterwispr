import AppKit
import ApplicationServices
import Testing
@testable import BetterWisprCore

@MainActor
@Test func automaticPasteRefusesChangedOrLostFocusWithinTheSameApp() {
    let original = AXUIElementCreateApplication(1)
    let other = AXUIElementCreateApplication(2)
    #expect(FocusedAppIntegration.focusMatches(original, current: AXUIElementCreateApplication(1)))
    #expect(!FocusedAppIntegration.focusMatches(original, current: other))
    #expect(!FocusedAppIntegration.focusMatches(original, current: nil))
    #expect(FocusedAppIntegration.focusMatches(nil, current: other))
    #expect(FocusedAppIntegration.focusMatches(nil, current: nil))
}

@MainActor
@Test func successiveDictationsPreserveANewerClipboardCopy() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("Before dictation", forType: .string)
    let original = FocusedAppIntegration.clipboardItems(pasteboard, pending: nil)
    pasteboard.clearContents()
    pasteboard.setString("First dictation", forType: .string)
    let pending = (items: original, changeCount: pasteboard.changeCount)
    #expect(FocusedAppIntegration.clipboardItems(pasteboard, pending: pending).first?.string(forType: .string) == "Before dictation")

    pasteboard.clearContents()
    pasteboard.setString("Copied by the user", forType: .string)
    let next = FocusedAppIntegration.clipboardItems(pasteboard, pending: pending)
    #expect(next.first?.string(forType: .string) == "Copied by the user")
}

@MainActor
@Test func clipboardSnapshotKeepsRichRepresentationsAndAnEmptyClipboard() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    #expect(FocusedAppIntegration.clipboardItems(pasteboard, pending: nil).isEmpty)
    let item = NSPasteboardItem()
    item.setString("Hello", forType: .string)
    let rich = Data("{\\rtf1 Hello}".utf8)
    item.setData(rich, forType: .rtf)
    pasteboard.writeObjects([item])
    let snapshot = FocusedAppIntegration.clipboardItems(pasteboard, pending: nil)
    pasteboard.clearContents()
    #expect(snapshot.first?.string(forType: .string) == "Hello")
    #expect(snapshot.first?.data(forType: .rtf) == rich)
}
