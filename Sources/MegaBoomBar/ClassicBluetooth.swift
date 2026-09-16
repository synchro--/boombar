import Foundation
import IOBluetooth

enum ClassicBluetoothError: LocalizedError {
    case deviceNotFound(String)
    case connectionFailed(String, IOReturn)
    case rfcommFailed(String, IOReturn)
    case writeFailed(IOReturn)
    case hostAddressUnavailable

    var errorDescription: String? {
        switch self {
        case .deviceNotFound(let mac):
            return "Bluetooth device \(mac) not found; pair the speaker first"
        case .connectionFailed(let mac, let status):
            return "could not open a classic Bluetooth connection to \(mac) (IOBluetooth error \(Self.hex(status))); make sure the speaker is on"
        case .rfcommFailed(let mac, let status):
            return "could not open RFCOMM channel 1 on \(mac) (IOBluetooth error \(Self.hex(status)))"
        case .writeFailed(let status):
            return "RFCOMM write failed (IOBluetooth error \(Self.hex(status)))"
        case .hostAddressUnavailable:
            return "could not determine this Mac's Bluetooth address"
        }
    }

    private static func hex(_ status: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: status))
    }
}

struct AudioConnectResult {
    let connected: Bool
    let stable: Bool
    let method: String
    let outputSwitched: Bool
}

enum ClassicBluetooth {
    static let rfcommChannel: BluetoothRFCOMMChannelID = 1
    static let powerOffMessage = Data([0x02, 0x01, 0xB6])
    static let nameHints = ["UE ", "BOOM", "MEGABOOM", "HYPERBOOM", "EPICBOOM", "EVERBOOM"]
    static let blueutilCandidates = ["/opt/homebrew/bin/blueutil", "/usr/local/bin/blueutil"]

    // MARK: - Host address

    static func hostMAC() -> String? {
        if let raw = IOBluetoothHostController.default()?.addressAsString(),
           let mac = Config.normalizeMAC(raw) {
            return mac
        }
        return hostMACFromSystemProfiler()
    }

    static func hostMACFromSystemProfiler() -> String? {
        guard let output = run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"], timeout: 30),
              let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return findControllerAddress(in: object)
    }

    private static func findControllerAddress(in node: Any) -> String? {
        if let dictionary = node as? [String: Any] {
            for (key, value) in dictionary {
                if (key == "controller_address" || key == "device_address"), let text = value as? String {
                    if let match = firstMAC(in: text), let mac = Config.normalizeMAC(match) {
                        return mac
                    }
                }
                if let found = findControllerAddress(in: value) { return found }
            }
        } else if let array = node as? [Any] {
            for item in array {
                if let found = findControllerAddress(in: item) { return found }
            }
        }
        return nil
    }

    private static func firstMAC(in text: String) -> String? {
        let pattern = "[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[matchRange])
    }

    // MARK: - Paired devices

    static func pairedDevices() -> [(name: String, address: String)] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return devices.compactMap { device in
            guard let name = device.name, let address = device.addressString else { return nil }
            return (name, address)
        }
    }

    static func pairedSpeaker() -> (name: String, mac: String)? {
        for device in pairedDevices() {
            guard looksLikeSpeaker(device.name), let mac = Config.normalizeMAC(device.address) else { continue }
            return (device.name, mac)
        }
        return nil
    }

    static func looksLikeSpeaker(_ name: String?) -> Bool {
        guard let name else { return false }
        let upper = name.uppercased()
        return nameHints.contains(where: { upper.contains($0) })
    }

    // MARK: - Connection state

    static func isConnected(mac: String) -> Bool {
        if let device = IOBluetoothDevice(addressString: mac), device.isConnected() {
            return true
        }
        return blueutilIsConnected(mac: mac)
    }

    // MARK: - Power off (classic RFCOMM)

    static func powerOff(mac: String) throws {
        guard let device = IOBluetoothDevice(addressString: mac) else {
            throw ClassicBluetoothError.deviceNotFound(mac)
        }

        try ensureConnected(device, mac: mac)

        var (result, channel) = openRFCOMM(device)
        if result != kIOReturnSuccess || channel == nil {
            // A stale ACL link makes RFCOMM opens fail with kIOReturnError; drop
            // and re-establish the classic connection before retrying once.
            _ = device.closeConnection()
            Thread.sleep(forTimeInterval: 1.0)
            try ensureConnected(device, mac: mac)
            (result, channel) = openRFCOMM(device)
        }

        guard result == kIOReturnSuccess, let channel else {
            throw ClassicBluetoothError.rfcommFailed(mac, result)
        }

        var written: IOReturn = kIOReturnError
        powerOffMessage.withUnsafeBytes { buffer in
            written = channel.writeSync(UnsafeMutableRawPointer(mutating: buffer.baseAddress),
                                        length: UInt16(powerOffMessage.count))
        }
        Thread.sleep(forTimeInterval: 0.3)
        _ = channel.close()

        if written != kIOReturnSuccess {
            throw ClassicBluetoothError.writeFailed(written)
        }
    }

    private static func ensureConnected(_ device: IOBluetoothDevice, mac: String) throws {
        guard !device.isConnected() else { return }
        let result = device.openConnection()
        guard result == kIOReturnSuccess else {
            throw ClassicBluetoothError.connectionFailed(mac, result)
        }
        Thread.sleep(forTimeInterval: 1.5)
    }

    private static func openRFCOMM(_ device: IOBluetoothDevice) -> (IOReturn, IOBluetoothRFCOMMChannel?) {
        var channel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelSync(&channel, withChannelID: rfcommChannel, delegate: nil)
        return (result, channel)
    }

    // MARK: - Audio / classic connect

    @discardableResult
    static func connectAudio(mac: String, name: String?, setOutput: Bool) -> AudioConnectResult {
        Thread.sleep(forTimeInterval: 2.5)

        var method: String?
        if blueutilConnect(mac: mac) {
            method = "blueutil"
        } else if iobluetoothConnect(mac: mac) {
            method = "iobluetooth"
        }

        guard let method else {
            return AudioConnectResult(connected: false, stable: false, method: "none", outputSwitched: false)
        }

        var stable = true
        for _ in 0..<6 {
            Thread.sleep(forTimeInterval: 1.0)
            if !isConnected(mac: mac) {
                stable = false
                break
            }
        }

        var outputSwitched = false
        if stable, setOutput, let name {
            outputSwitched = switchOutput(to: name)
        }

        return AudioConnectResult(connected: stable, stable: stable, method: method, outputSwitched: outputSwitched)
    }

    private static func blueutilConnect(mac: String) -> Bool {
        for _ in 0..<4 {
            _ = runBlueutil(["--connect", mac])
            if isConnected(mac: mac) { return true }
            Thread.sleep(forTimeInterval: 1.0)
        }
        return false
    }

    private static func iobluetoothConnect(mac: String) -> Bool {
        guard let device = IOBluetoothDevice(addressString: mac) else { return false }
        if device.isConnected() { return true }
        if device.openConnection() == kIOReturnSuccess, isConnected(mac: mac) {
            return true
        }
        return false
    }

    @discardableResult
    static func switchOutput(to name: String) -> Bool {
        guard let path = which("SwitchAudioSource") else { return false }
        return run(path, ["-s", name], timeout: 8) != nil
    }

    // MARK: - blueutil / process helpers

    static func blueutilPath() -> String? {
        for candidate in blueutilCandidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return which("blueutil")
    }

    private static func blueutilIsConnected(mac: String) -> Bool {
        guard let output = runBlueutil(["--is-connected", mac]) else { return false }
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    private static func runBlueutil(_ arguments: [String]) -> String? {
        guard let path = blueutilPath() else { return nil }
        return run(path, arguments, timeout: 10)
    }

    static func which(_ tool: String) -> String? {
        if tool.contains("/") {
            return FileManager.default.isExecutableFile(atPath: tool) ? tool : nil
        }
        let environment = ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
        for directory in environment.split(separator: ":") {
            let candidate = "\(directory)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
