import Foundation
import CoreBluetooth

enum BLEError: LocalizedError {
    case notPoweredOn(CBManagerState)
    case unauthorized
    case speakerNotFound
    case connectTimedOut
    case connectFailed(Error?)
    case characteristicsUnavailable(Error?)
    case writeFailed(Error?)
    case readFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .notPoweredOn(let state):
            return "Bluetooth is not available (state \(state.rawValue)); check System Settings > Privacy & Security > Bluetooth"
        case .unauthorized:
            return "Bluetooth permission was denied for this app"
        case .speakerNotFound:
            return "no UE speaker found in BLE standby"
        case .connectTimedOut:
            return "timed out connecting to the speaker over Bluetooth LE"
        case .connectFailed(let error):
            return "could not connect over Bluetooth LE\(Self.suffix(error))"
        case .characteristicsUnavailable(let error):
            return "could not discover the speaker's GATT profile\(Self.suffix(error))"
        case .writeFailed(let error):
            return "could not write the wake payload\(Self.suffix(error))"
        case .readFailed(let error):
            return "could not read from the speaker\(Self.suffix(error))"
        }
    }

    private static func suffix(_ error: Error?) -> String {
        guard let error else { return "" }
        return ": \(error.localizedDescription)"
    }
}

struct DiscoveredPeripheral {
    let identifier: UUID
    let name: String?
    let rssi: Int
    let serviceUUIDs: [CBUUID]
    let isSpeaker: Bool
}

struct WakeOutcome {
    let characteristicUUID: CBUUID?
    let payload: Data
    let battery: Int?
    let alreadyOn: Bool
    let peripheralIdentifier: UUID?
    let name: String?
}

struct BatteryOutcome {
    let level: Int?
    let peripheralIdentifier: UUID?
    let name: String?
}

final class BLEReceiver: NSObject {
    static let nameHints = ["UE ", "BOOM", "MEGABOOM", "HYPERBOOM", "EPICBOOM", "EVERBOOM"]
    static let serviceUUIDs = [CBUUID(string: "FE61"), CBUUID(string: "FE9F")]
    static let powerCharacteristicUUIDs = [
        CBUUID(string: "C6D6DC0D-07F5-47EF-9B59-630622B01FD3"),
        CBUUID(string: "69C0F621-1354-4CF8-98A6-328B8FAA1897")
    ]
    static let batteryCharacteristicUUID = CBUUID(string: "00002A19-0000-1000-8000-00805F9B34FB")
    private static let logitechManufacturerID: UInt16 = 224

    private let bleQueue = DispatchQueue(label: "com.megaboombar.ble")
    private let lock = NSLock()

    private var central: CBCentralManager?

    private var state: CBManagerState = .unknown
    private var stateSemaphore: DispatchSemaphore?

    private var speakerSemaphore: DispatchSemaphore?
    private var discovered: [UUID: DiscoveredPeripheral] = [:]
    private var peripherals: [UUID: CBPeripheral] = [:]

    private var connectSemaphore: DispatchSemaphore?
    private var connectError: Error?

    private var servicesSemaphore: DispatchSemaphore?
    private var servicesError: Error?
    private var pendingCharacteristicDiscoveries = 0

    private var writeSemaphore: DispatchSemaphore?
    private var writeError: Error?

    private var readSemaphore: DispatchSemaphore?
    private var readError: Error?
    private var readData: Data?

    static func buildPayloads(hostMAC: String, payloadHex: String?) -> [(label: String, data: Data)] {
        if let payloadHex {
            let cleaned = payloadHex.filter { $0.isHexDigit }
            if cleaned.count % 2 == 0, let data = Data(hexString: cleaned), !data.isEmpty {
                return [("explicit", data)]
            }
        }

        let compact = Config.compactMAC(hostMAC)
        guard compact.count == 12, var normal = Data(hexString: compact) else { return [] }
        normal.append(0x01)

        var octets: [String] = []
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            octets.append(String(compact[index..<next]))
            index = next
        }
        let reversedCompact = octets.reversed().joined()
        var reversed = Data(hexString: reversedCompact) ?? Data()
        reversed.append(0x01)

        var variants: [(label: String, data: Data)] = [("normal", normal)]
        if reversed != normal {
            variants.append(("reversed", reversed))
        }
        return variants
    }

    // MARK: - Public API (blocking; call off the BLE callback queue)

    func scan(timeout: TimeInterval) throws -> [DiscoveredPeripheral] {
        ensureCentral()
        try waitForPoweredOn(5)

        let semaphore = DispatchSemaphore(value: 0)
        lock.lock()
        discovered.removeAll()
        peripherals.removeAll()
        speakerSemaphore = semaphore
        lock.unlock()

        manager.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        _ = semaphore.wait(timeout: .now() + timeout)
        manager.stopScan()

        lock.lock()
        speakerSemaphore = nil
        let values = Array(discovered.values)
        lock.unlock()

        return values.sorted { lhs, rhs in
            if lhs.isSpeaker != rhs.isSpeaker { return lhs.isSpeaker }
            return lhs.rssi > rhs.rssi
        }
    }

    func wake(hostMAC: String, cachedIdentifier: String?, payloadHex: String?) throws -> WakeOutcome {
        let payloads = Self.buildPayloads(hostMAC: hostMAC, payloadHex: payloadHex)
        var lastError: Error?

        for attempt in 0..<2 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 1.2) }
            do {
                let (peripheral, name) = try resolvePeripheral(cachedIdentifier: cachedIdentifier, scanTimeout: 8)
                try connect(peripheral, timeout: 12)
                defer { manager.cancelPeripheralConnection(peripheral) }

                try discoverAllCharacteristics(peripheral, timeout: 12)
                let battery = batteryValue(on: peripheral)

                guard let powerCharacteristic = characteristic(on: peripheral, matchingAny: Self.powerCharacteristicUUIDs) else {
                    return WakeOutcome(characteristicUUID: nil,
                                       payload: Data(),
                                       battery: battery,
                                       alreadyOn: true,
                                       peripheralIdentifier: peripheral.identifier,
                                       name: name ?? peripheral.name)
                }

                for payload in payloads {
                    do {
                        try write(payload.data, to: powerCharacteristic, on: peripheral, timeout: 8)
                        return WakeOutcome(characteristicUUID: powerCharacteristic.uuid,
                                           payload: payload.data,
                                           battery: battery,
                                           alreadyOn: false,
                                           peripheralIdentifier: peripheral.identifier,
                                           name: name ?? peripheral.name)
                    } catch {
                        lastError = error
                    }
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? BLEError.writeFailed(nil)
    }

    func readBattery(cachedIdentifier: String?) throws -> BatteryOutcome {
        let (peripheral, name) = try resolvePeripheral(cachedIdentifier: cachedIdentifier, scanTimeout: 8)
        try connect(peripheral, timeout: 12)
        defer { manager.cancelPeripheralConnection(peripheral) }

        try discoverAllCharacteristics(peripheral, timeout: 12)
        return BatteryOutcome(level: batteryValue(on: peripheral),
                              peripheralIdentifier: peripheral.identifier,
                              name: name ?? peripheral.name)
    }

    // MARK: - Internals

    private var manager: CBCentralManager {
        if let central { return central }
        return ensureCentral()
    }

    @discardableResult
    private func ensureCentral() -> CBCentralManager {
        lock.lock()
        let existing = central
        lock.unlock()
        if let existing { return existing }

        bleQueue.sync {
            if self.central == nil {
                self.central = CBCentralManager(delegate: self, queue: self.bleQueue)
            }
        }
        lock.lock()
        let created = central
        lock.unlock()
        return created!
    }

    private func waitForPoweredOn(_ timeout: TimeInterval) throws {
        lock.lock()
        if state == .unauthorized { lock.unlock(); throw BLEError.unauthorized }
        if state == .poweredOn { lock.unlock(); return }
        let semaphore = DispatchSemaphore(value: 0)
        stateSemaphore = semaphore
        lock.unlock()

        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { throw BLEError.notPoweredOn(currentState()) }
            if semaphore.wait(timeout: .now() + remaining) == .timedOut {
                throw BLEError.notPoweredOn(currentState())
            }
            let current = currentState()
            if current == .poweredOn { return }
            if current == .unauthorized { throw BLEError.unauthorized }
            if current == .unsupported || current == .poweredOff {
                throw BLEError.notPoweredOn(current)
            }
        }
    }

    private func currentState() -> CBManagerState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    private func resolvePeripheral(cachedIdentifier: String?, scanTimeout: TimeInterval) throws -> (CBPeripheral, String?) {
        let found = try scan(timeout: scanTimeout)
        if let target = selectTarget(found, cachedIdentifier: cachedIdentifier),
           let peripheral = peripheral(for: target.identifier) {
            return (peripheral, target.name)
        }
        if let cachedIdentifier, let identifier = UUID(uuidString: cachedIdentifier),
           let peripheral = manager.retrievePeripherals(withIdentifiers: [identifier]).first {
            return (peripheral, peripheral.name)
        }
        throw BLEError.speakerNotFound
    }

    private func selectTarget(_ found: [DiscoveredPeripheral], cachedIdentifier: String?) -> DiscoveredPeripheral? {
        if let cachedIdentifier, let identifier = UUID(uuidString: cachedIdentifier),
           let match = found.first(where: { $0.identifier == identifier }) {
            return match
        }
        return found.first(where: { $0.isSpeaker }) ?? found.first
    }

    private func peripheral(for identifier: UUID) -> CBPeripheral? {
        lock.lock()
        let cached = peripherals[identifier]
        lock.unlock()
        if let cached { return cached }
        return manager.retrievePeripherals(withIdentifiers: [identifier]).first
    }

    private func connect(_ peripheral: CBPeripheral, timeout: TimeInterval) throws {
        let semaphore = DispatchSemaphore(value: 0)
        lock.lock()
        connectSemaphore = semaphore
        connectError = nil
        lock.unlock()

        peripheral.delegate = self
        manager.connect(peripheral, options: nil)

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            manager.cancelPeripheralConnection(peripheral)
            lock.lock()
            connectSemaphore = nil
            lock.unlock()
            throw BLEError.connectTimedOut
        }

        lock.lock()
        let error = connectError
        connectSemaphore = nil
        lock.unlock()
        if let error { throw BLEError.connectFailed(error) }
    }

    private func discoverAllCharacteristics(_ peripheral: CBPeripheral, timeout: TimeInterval) throws {
        let semaphore = DispatchSemaphore(value: 0)
        lock.lock()
        servicesSemaphore = semaphore
        servicesError = nil
        pendingCharacteristicDiscoveries = -1
        lock.unlock()

        peripheral.discoverServices(nil)

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            lock.lock()
            servicesSemaphore = nil
            lock.unlock()
            throw BLEError.characteristicsUnavailable(nil)
        }

        lock.lock()
        let error = servicesError
        servicesSemaphore = nil
        lock.unlock()
        if let error { throw BLEError.characteristicsUnavailable(error) }
    }

    private func characteristic(on peripheral: CBPeripheral, matchingAny uuids: [CBUUID]) -> CBCharacteristic? {
        for service in peripheral.services ?? [] {
            for characteristic in service.characteristics ?? [] where uuids.contains(characteristic.uuid) {
                return characteristic
            }
        }
        return nil
    }

    private func batteryValue(on peripheral: CBPeripheral) -> Int? {
        guard let characteristic = characteristic(on: peripheral, matchingAny: [Self.batteryCharacteristicUUID]) else {
            return nil
        }
        guard let data = try? read(characteristic, on: peripheral, timeout: 6), let first = data.first else {
            return nil
        }
        return Int(first)
    }

    private func write(_ data: Data, to characteristic: CBCharacteristic, on peripheral: CBPeripheral, timeout: TimeInterval) throws {
        if !characteristic.properties.contains(.write) {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        lock.lock()
        writeSemaphore = semaphore
        writeError = nil
        lock.unlock()

        peripheral.writeValue(data, for: characteristic, type: .withResponse)

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            lock.lock()
            writeSemaphore = nil
            lock.unlock()
            throw BLEError.writeFailed(nil)
        }

        lock.lock()
        let error = writeError
        writeSemaphore = nil
        lock.unlock()
        if let error { throw BLEError.writeFailed(error) }
    }

    private func read(_ characteristic: CBCharacteristic, on peripheral: CBPeripheral, timeout: TimeInterval) throws -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        lock.lock()
        readSemaphore = semaphore
        readError = nil
        readData = nil
        lock.unlock()

        peripheral.readValue(for: characteristic)

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            lock.lock()
            readSemaphore = nil
            lock.unlock()
            throw BLEError.readFailed(nil)
        }

        lock.lock()
        let error = readError
        let data = readData
        readSemaphore = nil
        lock.unlock()
        if let error { throw BLEError.readFailed(error) }
        return data
    }

    private static func isSpeaker(name: String?, services: [CBUUID], manufacturerData: Data?) -> Bool {
        if let name, nameHints.contains(where: { name.uppercased().contains($0) }) {
            return true
        }
        if Self.serviceUUIDs.contains(where: { services.contains($0) }) {
            return true
        }
        if let manufacturerData, manufacturerData.count >= 2 {
            let identifier = UInt16(manufacturerData[manufacturerData.startIndex])
                | (UInt16(manufacturerData[manufacturerData.startIndex + 1]) << 8)
            if identifier == logitechManufacturerID { return true }
        }
        return false
    }
}

extension BLEReceiver: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        lock.lock()
        state = central.state
        let semaphore = stateSemaphore
        stateSemaphore = nil
        lock.unlock()
        semaphore?.signal()
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let speaker = Self.isSpeaker(name: name, services: services, manufacturerData: manufacturerData)

        let found = DiscoveredPeripheral(identifier: peripheral.identifier,
                                         name: name,
                                         rssi: RSSI.intValue,
                                         serviceUUIDs: services,
                                         isSpeaker: speaker)

        lock.lock()
        peripherals[peripheral.identifier] = peripheral
        discovered[peripheral.identifier] = found
        let semaphore = speaker ? speakerSemaphore : nil
        lock.unlock()

        if speaker { semaphore?.signal() }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        lock.lock()
        let semaphore = connectSemaphore
        lock.unlock()
        semaphore?.signal()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        lock.lock()
        connectError = error ?? BLEError.connectFailed(nil)
        let semaphore = connectSemaphore
        lock.unlock()
        semaphore?.signal()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    }
}

extension BLEReceiver: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            lock.lock()
            servicesError = error
            let semaphore = servicesSemaphore
            servicesSemaphore = nil
            lock.unlock()
            semaphore?.signal()
            return
        }

        let services = peripheral.services ?? []
        if services.isEmpty {
            lock.lock()
            let semaphore = servicesSemaphore
            servicesSemaphore = nil
            lock.unlock()
            semaphore?.signal()
            return
        }

        lock.lock()
        pendingCharacteristicDiscoveries = services.count
        lock.unlock()

        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        var semaphore: DispatchSemaphore?
        lock.lock()
        if let error { servicesError = error }
        if pendingCharacteristicDiscoveries > 0 {
            pendingCharacteristicDiscoveries -= 1
        }
        if pendingCharacteristicDiscoveries == 0 {
            semaphore = servicesSemaphore
            servicesSemaphore = nil
        }
        lock.unlock()
        semaphore?.signal()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        lock.lock()
        writeError = error
        let semaphore = writeSemaphore
        lock.unlock()
        semaphore?.signal()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        lock.lock()
        readError = error
        readData = characteristic.value
        let semaphore = readSemaphore
        lock.unlock()
        semaphore?.signal()
    }
}
