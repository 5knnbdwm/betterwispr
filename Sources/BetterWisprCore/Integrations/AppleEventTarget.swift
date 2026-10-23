import AppKit

/// Apple Event targets addressed by running process, so a closed app is never launched, and asked for consent only on request.
public enum AppleEventTarget {
    public static func descriptor(for bundleID: String) -> NSAppleEventDescriptor? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            .map { NSAppleEventDescriptor(processIdentifier: $0.processIdentifier) }
    }

    /// Can block for a while, so never call it on the main thread.
    @discardableResult
    public static func allowed(_ target: NSAppleEventDescriptor, askingUser: Bool) -> Bool {
        AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, askingUser) == noErr
    }

    /// Specifies a property of `container`, or of the application when it is nil, by its four-character scripting code.
    static func property(_ code: String, of container: NSAppleEventDescriptor? = nil) -> NSAppleEventDescriptor? {
        specifier(want: NSAppleEventDescriptor(typeCode: fourCharCode("prop")), form: "prop",
                  key: NSAppleEventDescriptor(typeCode: fourCharCode(code)), of: container)
    }

    /// Specifies the element of a class at a one-based index, where 1 is the frontmost window.
    static func element(_ classCode: String, at index: Int32, of container: NSAppleEventDescriptor? = nil) -> NSAppleEventDescriptor? {
        specifier(want: NSAppleEventDescriptor(typeCode: fourCharCode(classCode)), form: "indx",
                  key: NSAppleEventDescriptor(int32: index), of: container)
    }

    /// Gets the specified value without ever interacting, giving up after a second. Blocks, so call it off the main thread.
    static func get(_ specifier: NSAppleEventDescriptor?, from target: NSAppleEventDescriptor) -> NSAppleEventDescriptor? {
        guard let specifier else { return nil }
        let event = NSAppleEventDescriptor(eventClass: fourCharCode("core"), eventID: fourCharCode("getd"), targetDescriptor: target,
                                           returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(specifier, forKeyword: fourCharCode("----"))
        return try? event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 1).paramDescriptor(forKeyword: fourCharCode("----"))
    }

    private static func specifier(want: NSAppleEventDescriptor, form: String, key: NSAppleEventDescriptor,
                                  of container: NSAppleEventDescriptor?) -> NSAppleEventDescriptor? {
        guard let specifier = NSAppleEventDescriptor.record().coerce(toDescriptorType: fourCharCode("obj ")) else { return nil }
        specifier.setDescriptor(want, forKeyword: fourCharCode("want"))
        specifier.setDescriptor(container ?? .null(), forKeyword: fourCharCode("from"))
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: fourCharCode(form)), forKeyword: fourCharCode("form"))
        specifier.setDescriptor(key, forKeyword: fourCharCode("seld"))
        return specifier
    }

    private static func fourCharCode(_ text: String) -> FourCharCode {
        text.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }
}
