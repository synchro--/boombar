import Foundation

final class Config {
    private enum Key {
        static let hostMAC = "hostMAC"
        static let speakerMAC = "speakerMAC"
        static let speakerName = "speakerName"
        static let peripheralIdentifier = "peripheralIdentifier"
        static let payloadHex = "payloadHex"
        static let setAsDefaultOutput = "setAsDefaultOutput"
    }

    private let defaults: UserDefaults
    private let prefix = "MegaBoomBar."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hostMAC: String? {
        get { defaults.string(forKey: prefix + Key.hostMAC) }
        set { store(newValue, forKey: Key.hostMAC) }
    }

    var speakerMAC: String? {
        get { defaults.string(forKey: prefix + Key.speakerMAC) }
        set { store(newValue, forKey: Key.speakerMAC) }
    }

    var speakerName: String? {
        get { defaults.string(forKey: prefix + Key.speakerName) }
        set { store(newValue, forKey: Key.speakerName) }
    }

    var peripheralIdentifier: String? {
        get { defaults.string(forKey: prefix + Key.peripheralIdentifier) }
        set { store(newValue, forKey: Key.peripheralIdentifier) }
    }

    var payloadHex: String? {
        get { defaults.string(forKey: prefix + Key.payloadHex) }
        set { store(newValue, forKey: Key.payloadHex) }
    }

    var setAsDefaultOutput: Bool {
        get { defaults.bool(forKey: prefix + Key.setAsDefaultOutput) }
        set { defaults.set(newValue, forKey: prefix + Key.setAsDefaultOutput) }
    }

    private func store(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: prefix + key)
        } else {
            defaults.removeObject(forKey: prefix + key)
        }
    }

    static func normalizeMAC(_ value: String) -> String? {
        let compact = compactMAC(value)
        guard compact.count == 12, compact.allSatisfy({ $0.isHexDigit }) else { return nil }
        var octets: [String] = []
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            octets.append(String(compact[index..<next]))
            index = next
        }
        return octets.joined(separator: ":")
    }

    static func compactMAC(_ value: String) -> String {
        value
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .uppercased()
    }
}

extension Data {
    init?(hexString: String) {
        let characters = Array(hexString)
        guard characters.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(characters.count / 2)
        var index = 0
        while index < characters.count {
            let pair = String(characters[index...index + 1])
            guard let byte = UInt8(pair, radix: 16) else { return nil }
            bytes.append(byte)
            index += 2
        }
        self.init(bytes)
    }
}
