import AppKit
import ApplicationServices

public enum OutputResult: Sendable, Equatable {
    case copied
    case copiedForManualPaste
    case pasted(into: String)
}

@MainActor
public protocol TextOutputIntegration {
    func deliver(_ text: String, to target: NSRunningApplication?) async throws -> OutputResult
}

@MainActor
public struct ClipboardIntegration: TextOutputIntegration {
    public init() {}
    public func deliver(_ text: String, to target: NSRunningApplication?) async throws -> OutputResult {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else { throw OutputError.clipboard }
        return .copied
    }
}

@MainActor
public struct FocusedAppIntegration: TextOutputIntegration {
    private static var pendingRestore: (items: [NSPasteboardItem], task: Task<Void, Never>)?
    private static let remoteDesktops: Set<String> = ["com.apple.ScreenSharing"]
    public let keepsCopy: Bool
    public init(keepsCopy: Bool) { self.keepsCopy = keepsCopy }
    public func deliver(_ text: String, to target: NSRunningApplication?) async throws -> OutputResult {
        // Never steal focus or paste into an app the user switched to while decoding.
        guard let target, !target.isTerminated,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
              AXIsProcessTrusted() else {
            _ = try await ClipboardIntegration().deliver(text, to: nil)
            return .copiedForManualPaste
        }
        let pasteboard = NSPasteboard.general
        let previousItems: [NSPasteboardItem] = Self.pendingRestore?.items ?? pasteboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []
        Self.pendingRestore?.task.cancel()
        Self.pendingRestore = nil
        _ = try await ClipboardIntegration().deliver(text, to: target)
        let ourChange = pasteboard.changeCount
        guard let events = Self.pasteKeystroke() else { return .copiedForManualPaste }
        for event in events { event.postToPid(target.processIdentifier) }
        if !keepsCopy, !Self.remoteDesktops.contains(target.bundleIdentifier ?? "") {
            Self.pendingRestore = (previousItems, Task {
                // ponytail: applications expose no paste acknowledgement; allow 750 ms before restoring.
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled else { return }
                Self.pendingRestore = nil
                if pasteboard.changeCount == ourChange {
                    pasteboard.clearContents()
                    if !previousItems.isEmpty { _ = pasteboard.writeObjects(previousItems) }
                }
            })
        }
        return .pasted(into: target.localizedName ?? "your app")
    }

    /// Command-V as a physical keyboard sends it, with Command pressed and released as its own events.
    static func pasteKeystroke() -> [CGEvent]? {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else { return nil }
        commandDown.type = .flagsChanged
        commandUp.type = .flagsChanged
        commandDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        commandUp.flags = []
        return [commandDown, vDown, vUp, commandUp]
    }
}

public enum OutputError: LocalizedError {
    case clipboard
    public var errorDescription: String? { "Could not write to the clipboard. Your transcript is still available in BetterWispr." }
}
