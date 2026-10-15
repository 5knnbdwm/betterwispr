import CoreML
import Foundation
import Testing
@testable import BetterWisprCore

@Test func chineseScriptConvertsOnlyChinese() {
    #expect(ChineseScript.simplified.convert("這是測試，頭髮", language: "zh") == "这是测试，头发")
    #expect(ChineseScript.traditional.convert("这是测试，头发", language: "zh") == "這是測試，頭髮")
    #expect(ChineseScript.simplified.convert("我們在開會。", language: nil) == "我们在开会。")
    #expect(ChineseScript.simplified.convert("日本語の漢字です。", language: nil) == "日本語の漢字です。")
    #expect(ChineseScript.simplified.convert("漢字", language: "ja") == "漢字")
    #expect(ChineseScript.simplified.convert("Ship it", language: nil) == "Ship it")
}

@Test func workspaceSavedBeforeLanguageChoicesDecodesTheirDefaults() throws {
    var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as! [String: Any]
    object["chineseScript"] = nil
    object["dictationLanguages"] = nil
    let settings = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(settings.chineseScript == nil)
    #expect(settings.dictationLanguages.isEmpty)
    var chosen = AppSettings()
    chosen.chineseScript = .traditional
    chosen.dictationLanguages = ["en", "es"]
    #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(chosen)) == chosen)
}

@Test func languageDetectionChoosesTheLikeliestAllowedLanguage() async throws {
    let logits = try MLMultiArray(shape: [1, 1, 6], dataType: .float32)
    for (index, value) in [0, 4, 9, 2, 3, 8].enumerated() { logits[index] = NSNumber(value: value) }
    let sampled = await AllowedLanguageSampler(languageTokens: [1, 3, 4]).update(tokens: [0], logits: logits, logProbs: [0])
    #expect(sampled.tokens == [0, 1])
    #expect(sampled.logProbs.count == sampled.tokens.count)
}
