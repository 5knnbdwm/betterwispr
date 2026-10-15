import Foundation
import NaturalLanguage

public enum ChineseScript: String, Codable, Sendable {
    case simplified, traditional

    /// Rewrites Chinese text in this script; nil language checks the text itself, and other languages stay unchanged.
    public func convert(_ text: String, language: String?) -> String {
        guard let code = language ?? NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue,
              Locale(identifier: code).language.languageCode == .chinese else { return text }
        return text.applyingTransform(StringTransform("Hant-Hans"), reverse: self == .traditional) ?? text
    }
}
