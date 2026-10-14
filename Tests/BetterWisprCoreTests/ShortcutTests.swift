import AppKit
import BetterWisprCore
import Carbon.HIToolbox
import IOKit.hidsystem
import Testing
@testable import BetterWispr

@Test @MainActor func standaloneOptionDeliversOnePressAndReleaseForTheRecordedSide() throws {
    let listener = GlobalShortcut()
    let shortcut = try #require(DictationShortcut(keyCode: UInt32(kVK_Option), modifiers: [], key: "Left Option"))
    var transitions: [Bool] = []
    listener.onPress = { transitions.append(true) }
    listener.onRelease = { transitions.append(false) }
    let left = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELALTKEYMASK)).union(.option)
    let right = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERALTKEYMASK)).union(.option)

    func send(_ keyCode: Int, _ flags: NSEvent.ModifierFlags) throws {
        let event = try #require(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags,
                                                timestamp: 0, windowNumber: 0, context: nil, characters: "",
                                                charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(keyCode)))
        listener.handleModifierEvent(event, shortcut: shortcut)
    }

    try send(kVK_RightOption, right)
    try send(kVK_RightOption, [])
    try send(kVK_Option, left.union(.command))
    try send(kVK_Option, .command)
    #expect(transitions.isEmpty)

    try send(kVK_Option, left)
    try send(kVK_Option, left)
    try send(kVK_RightOption, left.union(right))
    try send(kVK_Option, right) // Releasing left must finish even while right is down.
    try send(kVK_RightOption, [])
    #expect(transitions == [true, false])

    try send(kVK_Option, left)
    try send(kVK_Option, .command) // Added modifiers must not swallow the release.
    #expect(transitions == [true, false, true, false])
    listener.unregister()
    try send(kVK_Option, [])
    #expect(transitions == [true, false, true, false])
}

@Test func escapeCancelsUnderTheModifiersStillHeldFromTheDictationShortcut() throws {
    let rightCommand = try #require(DictationShortcut(keyCode: UInt32(kVK_RightCommand), modifiers: [], key: "Right Command"))
    let f5 = try #require(DictationShortcut(keyCode: UInt32(kVK_F5), modifiers: [], key: "F5"))
    let optionEscape = try #require(DictationShortcut(keyCode: UInt32(kVK_Escape), modifiers: .option, key: "Esc"))
    let commandShiftD = try #require(DictationShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: [.command, .shift], key: "D"))
    #expect(DictationShortcut.optionSpace.cancelModifiers == [[], .option])
    #expect(rightCommand.cancelModifiers == [[], .command])
    #expect(f5.cancelModifiers == [[]])
    #expect(optionEscape.cancelModifiers == [[]])
    #expect(commandShiftD.cancelModifiers == [[], [.command, .shift]])
}

@Test @MainActor func eachShortcutAnswersOnlyItsOwnCarbonHotKey() throws {
    let dictation = GlobalShortcut()
    let cancel = GlobalShortcut(id: 2)
    var fired: [String] = []
    dictation.onPress = { fired.append("dictation press") }
    dictation.onRelease = { fired.append("dictation release") }
    cancel.onPress = { fired.append("cancel press") }
    cancel.onRelease = { fired.append("cancel release") }

    func send(_ kind: Int, signature: OSType = 0x42575350, id: UInt32) throws -> [OSStatus] {
        var event: EventRef?
        try #require(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kind), 0, EventAttributes(kEventAttributeNone), &event) == noErr)
        let created = try #require(event)
        defer { ReleaseEvent(created) }
        var hotKey = EventHotKeyID(signature: signature, id: id)
        try #require(SetEventParameter(created, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                       MemoryLayout<EventHotKeyID>.size, &hotKey) == noErr)
        return [dictation.handle(created), cancel.handle(created)]
    }

    let handled = OSStatus(noErr)
    let passed = OSStatus(eventNotHandledErr)
    #expect(try send(kEventHotKeyPressed, id: 2) == [passed, handled])
    #expect(fired == ["cancel press"])
    #expect(try send(kEventHotKeyPressed, id: 1) == [handled, passed])
    #expect(try send(kEventHotKeyReleased, id: 1) == [handled, passed])
    #expect(fired == ["cancel press", "dictation press", "dictation release"])
    #expect(try send(kEventHotKeyPressed, signature: 0x4F544852, id: 1) == [passed, passed])
    #expect(try send(kEventHotKeyPressed, signature: 0x4F544852, id: 2) == [passed, passed])
    #expect(fired == ["cancel press", "dictation press", "dictation release"])
}
