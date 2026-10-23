import AppKit
import ApplicationServices
import AVFoundation
import Testing
@testable import BetterWisprCore
@testable import BetterWispr

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["BETTERWISPR_LIVE_PASTE"] == "1"))
func chromeYouTubeReceivesTheSavedDictationFromASyntheticRecording() async throws {
    try #require(AXIsProcessTrusted())
    try #require(CGPreflightPostEventAccess())
    let target = try #require(NSWorkspace.shared.frontmostApplication)
    try #require(target.bundleIdentifier == "com.google.Chrome")
    let app = AXUIElementCreateApplication(target.processIdentifier)
    try #require(app.element(kAXFocusedWindowAttribute)?.string(kAXTitleAttribute)?.contains("YouTube") == true)
    let field = try #require(FocusedAppIntegration.focusedElement(in: target))
    try #require(field.string(kAXRoleAttribute) == "AXComboBox")
    let initial = field.string(kAXValueAttribute) ?? ""
    let isDisposableQuery = initial.isEmpty || initial == "The release meeting starts on Friday. We agreed to test the search box before publishing."
    try #require(isDisposableQuery, "Focus the disposable YouTube search field.")
    var selectedValue: CFTypeRef?
    try #require(AXUIElementCopyAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, &selectedValue) == .success)
    let selection = try #require(selectedValue)
    try #require(CFGetTypeID(selection) == AXValueGetTypeID())
    var range = CFRange()
    try #require(AXValueGetValue(selection as! AXValue, .cfRange, &range))
    try #require(range.location >= 0 && range.length >= 0 && range.location + range.length <= (initial as NSString).length)

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let audio = directory.appendingPathComponent("synthetic.aiff")
    let say = Process()
    say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    say.arguments = ["-o", audio.path, "The release meeting starts on Friday. We agreed to test the search box before publishing."]
    try say.run()
    say.waitUntilExit()
    try #require(say.terminationStatus == 0)
    let file = try AVAudioFile(forReading: audio)
    let duration = Double(file.length) / file.processingFormat.sampleRate
    let speechModel = try #require(SpeechModel.catalog.first { $0.id == "parakeet-ultra" })
    try #require(ParakeetProvider.isInstalled(speechModel))
    let store = LocalStore(directory: directory)
    let model = AppModel(store: store, startsServices: false)
    model.settings.selectedModelID = speechModel.id
    model.settings.language = "en"
    model.settings.cleanup = .light
    model.settings.autoPaste = true
    model.settings.copyToClipboard = false
    model.settings.saveHistory = true
    model.settings.learnCorrections = false
    model.settings.soundEffects = false
    defer { model.discardRecording() }

    model.transcribe(DictationRecording(audio: RecordedAudio(url: audio, duration: duration, hasSpeech: true),
                                       model: speechModel, settings: model.settings, vocabulary: [],
                                       target: target, targetElement: field))
    let deadline = ContinuousClock.now + .seconds(60)
    while model.isBusy, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
    try #require(!model.isBusy, "Dictation did not finish within 60 seconds.")
    let transcript = try #require(model.history.first)
    let expected = (initial as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: transcript.text)
    #expect(!transcript.text.isEmpty)
    #expect(try store.load().history.first?.text == transcript.text)
    let deliveryDeadline = ContinuousClock.now + .seconds(3)
    while field.string(kAXValueAttribute) != expected, ContinuousClock.now < deliveryDeadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(model.phase == .idle, "The test must complete automatic delivery, not manual-paste fallback.")
    #expect(field.string(kAXValueAttribute) == expected)
    // Keep the process alive until the app's deferred clipboard restoration has run.
    try await Task.sleep(for: .seconds(1))
}
