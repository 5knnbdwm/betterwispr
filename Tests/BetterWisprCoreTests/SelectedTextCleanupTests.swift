import BetterWisprCore
import Foundation
import Testing
@testable import BetterWispr

@Test func selectedTextIsRefusedWhenEmptyShortNotEnglishOrTheCleanupProviderIsMissing() {
    var settings = AppSettings()
    settings.cleanupSelection = .ollama("llama3.2")
    let sentence = "  so um we should probably ship it on friday i think  "

    #expect(SelectedTextCleanup.refusal(of: " \n\t ", settings: settings.cleanupSettings) == .noSelection)
    #expect(SelectedTextCleanup.refusal(of: "ship it friday", settings: settings.cleanupSettings) == .tooShort)
    #expect(SelectedTextCleanup.refusal(of: "Bonjour à tous, je voudrais réserver une table pour ce soir.", settings: settings.cleanupSettings) == .notEnglish)
    #expect(SelectedTextCleanup.refusal(of: sentence, settings: settings.cleanupSettings) == nil)

    settings.cleanupSelection = .connection(UUID())
    #expect(SelectedTextCleanup.refusal(of: sentence, settings: settings.cleanupSettings)
        == .unavailable("The selected notes connection is missing. Choose a notes model in Models."))
}

@Test func replacementKeepsTheWhitespaceAroundTheSelectionAndSkipsAnUnchangedEdit() {
    let selected = "\n  so um we ship it friday \n"

    #expect(SelectedTextCleanup.replacement(of: selected, with: "We ship it Friday.") == "\n  We ship it Friday. \n")
    #expect(SelectedTextCleanup.replacement(of: selected, with: "so um we ship it friday") == nil)
    #expect(SelectedTextCleanup.replacement(of: "We ship it Friday.", with: "We ship it on Friday.") == "We ship it on Friday.")
}
