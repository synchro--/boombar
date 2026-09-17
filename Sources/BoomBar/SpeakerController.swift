import Foundation

enum SpeakerError: LocalizedError {
    case hostAddressUnavailable
    case speakerUnavailable
    case audioConnectionFailed
    case batteryUnavailable

    var errorDescription: String? {
        switch self {
        case .hostAddressUnavailable:
            return "could not determine this Mac's Bluetooth address"
        case .speakerUnavailable:
            return "no speaker address known; pair the speaker with this Mac first"
        case .audioConnectionFailed:
            return "audio connection failed (is the speaker on?)"
        case .batteryUnavailable:
            return "battery level unavailable"
        }
    }
}

final class SpeakerController {
    private let config: Config
    private let ble = BLEReceiver()
    private let workQueue = DispatchQueue(label: "com.synchro.boombar.speaker")

    private(set) var isConnected = false
    private(set) var isBusy = false
    private(set) var statusText = "Checking\u{2026}"
    private(set) var batteryLevel: Int?

    var onStateChange: (() -> Void)?

    init(config: Config) {
        self.config = config
    }

    var toggleTitle: String {
        isConnected ? "Turn Off" : "Turn On"
    }

    var setAsDefaultOutput: Bool {
        config.setAsDefaultOutput
    }

    func refresh() {
        workQueue.async { [weak self] in
            guard let self else { return }
            let mac = self.resolveSpeakerMAC()
            let connected = mac.map { ClassicBluetooth.isConnected(mac: $0) } ?? false
            DispatchQueue.main.async {
                self.isConnected = connected
                if !self.isBusy {
                    self.statusText = connected
                        ? "Connected: \(self.displayName(fallback: mac))"
                        : "Off / standby"
                }
                self.notify()
            }
        }
    }

    func turnOn(completion: ((Result<String, Error>) -> Void)? = nil) {
        run(message: "Waking speaker\u{2026}", completion: completion) {
            let hostMAC = self.config.hostMAC ?? ClassicBluetooth.hostMAC()
            guard let hostMAC else { throw SpeakerError.hostAddressUnavailable }
            self.config.hostMAC = hostMAC

            let outcome = try self.ble.wake(hostMAC: hostMAC,
                                            cachedIdentifier: self.config.peripheralIdentifier,
                                            payloadHex: self.config.payloadHex)
            if let identifier = outcome.peripheralIdentifier {
                self.config.peripheralIdentifier = identifier.uuidString
            }
            if let name = outcome.name, !name.isEmpty {
                self.config.speakerName = name
            }
            if outcome.alreadyOn {
                return "Speaker already on"
            }

            guard let mac = self.resolveSpeakerMAC() else {
                return "Speaker woken"
            }
            let result = ClassicBluetooth.connectAudio(mac: mac,
                                                       name: self.config.speakerName,
                                                       setOutput: self.config.setAsDefaultOutput)
            return result.stable ? "Speaker ready" : "Speaker woken (audio not connected)"
        }
    }

    func turnOff(completion: ((Result<String, Error>) -> Void)? = nil) {
        run(message: "Turning off\u{2026}", completion: completion) {
            guard let mac = self.resolveSpeakerMAC() else { throw SpeakerError.speakerUnavailable }
            try ClassicBluetooth.powerOff(mac: mac)
            return "Speaker turned off"
        }
    }

    func connectAudio(completion: ((Result<String, Error>) -> Void)? = nil) {
        run(message: "Connecting audio\u{2026}", completion: completion) {
            guard let mac = self.resolveSpeakerMAC() else { throw SpeakerError.speakerUnavailable }
            let result = ClassicBluetooth.connectAudio(mac: mac,
                                                       name: self.config.speakerName,
                                                       setOutput: self.config.setAsDefaultOutput)
            guard result.stable else { throw SpeakerError.audioConnectionFailed }
            return "Audio connected"
        }
    }

    func readBattery() {
        guard !isBusy else { return }
        isBusy = true
        statusText = "Reading battery\u{2026}"
        notify()

        workQueue.async { [weak self] in
            guard let self else { return }
            var level: Int?
            var error: Error?
            do {
                let outcome = try self.ble.readBattery(cachedIdentifier: self.config.peripheralIdentifier)
                if let identifier = outcome.peripheralIdentifier {
                    self.config.peripheralIdentifier = identifier.uuidString
                }
                if let name = outcome.name, !name.isEmpty {
                    self.config.speakerName = name
                }
                level = outcome.level
            } catch let caught {
                error = caught
            }

            DispatchQueue.main.async {
                self.isBusy = false
                if let error {
                    self.statusText = "Error: \(error.localizedDescription)"
                } else if let level {
                    self.batteryLevel = level
                    self.statusText = "Battery: \(level)%"
                } else {
                    self.statusText = "Battery unavailable"
                }
                self.notify()
            }
        }
    }

    @discardableResult
    func toggleDefaultOutput() -> Bool {
        config.setAsDefaultOutput.toggle()
        return config.setAsDefaultOutput
    }

    // MARK: - Internals

    private func run(message: String,
                     completion: ((Result<String, Error>) -> Void)?,
                     task: @escaping () throws -> String) {
        guard !isBusy else { return }
        isBusy = true
        statusText = message
        notify()

        workQueue.async { [weak self] in
            guard let self else { return }
            let result: Result<String, Error>
            do {
                result = .success(try task())
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                self.isBusy = false
                switch result {
                case .success(let text):
                    self.statusText = text
                case .failure(let error):
                    self.statusText = "Error: \(error.localizedDescription)"
                }
                self.notify()
                completion?(result)
                self.refresh()
            }
        }
    }

    private func resolveSpeakerMAC() -> String? {
        if let mac = config.speakerMAC { return mac }
        if let found = ClassicBluetooth.pairedSpeaker() {
            config.speakerName = found.name
            config.speakerMAC = found.mac
            return found.mac
        }
        return nil
    }

    private func displayName(fallback: String?) -> String {
        if let name = config.speakerName, !name.isEmpty { return name }
        return fallback ?? "speaker"
    }

    private func notify() {
        onStateChange?()
    }
}
