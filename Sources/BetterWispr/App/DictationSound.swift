import AppKit
import Foundation

enum DictationSound: String, CaseIterable {
    case started, finished, cancelled, attention

    static let overrideDirectory = URL.applicationSupportDirectory
        .appendingPathComponent("BetterWispr/SoundOverrides", isDirectory: true)

    var systemSoundName: String {
        switch self {
        case .started: "Tink"
        case .finished: "Purr"
        case .cancelled: "Bottle"
        case .attention: "Basso"
        }
    }

    var sound: NSSound? { sound(in: Self.overrideDirectory) }

    func sound(in directory: URL) -> NSSound? {
        if let override = url(in: directory) { return NSSound(contentsOf: override, byReference: false) }
        return NSSound(named: systemSoundName)
    }

    func url(in directory: URL) -> URL? {
        let file = directory.appendingPathComponent(rawValue).appendingPathExtension("wav")
        return FileManager.default.isReadableFile(atPath: file.path) ? file : nil
    }
}
