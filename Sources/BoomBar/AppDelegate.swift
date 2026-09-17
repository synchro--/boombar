import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let version = "1.0.0"

    private let config = Config()
    private lazy var controller = SpeakerController(config: config)

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var batteryTimer: Timer?

    private let statusLine = NSMenuItem(title: "Checking\u{2026}", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Turn On", action: nil, keyEquivalent: "")
    private let connectItem = NSMenuItem(title: "Connect Audio", action: nil, keyEquivalent: "")
    private let batteryItem = NSMenuItem(title: "Battery: \u{2014}", action: nil, keyEquivalent: "")
    private let outputItem = NSMenuItem(title: "Set as Default Output", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        buildMenu()

        controller.onStateChange = { [weak self] in
            self?.updateUI()
        }
        updateUI()
        controller.refresh()
        controller.readBattery()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.controller.readBattery()
        }
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = icon(connected: false)
        item.button?.toolTip = "BoomBar"
        item.menu = menu
        statusItem = item
    }

    private func buildMenu() {
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        toggleItem.target = self
        toggleItem.action = #selector(togglePower)
        menu.addItem(toggleItem)

        connectItem.target = self
        connectItem.action = #selector(connectAudio)
        menu.addItem(connectItem)

        batteryItem.target = self
        batteryItem.action = #selector(refreshBattery)
        menu.addItem(batteryItem)

        outputItem.target = self
        outputItem.action = #selector(toggleOutput)
        menu.addItem(outputItem)

        menu.addItem(.separator())
        let versionItem = NSMenuItem(title: "BoomBar \(Self.version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func updateUI() {
        statusLine.title = controller.statusText
        toggleItem.title = controller.toggleTitle
        toggleItem.isEnabled = !controller.isBusy
        connectItem.isEnabled = !controller.isBusy
        batteryItem.isEnabled = !controller.isBusy
        outputItem.state = controller.setAsDefaultOutput ? .on : .off

        if controller.isBusy {
            batteryItem.title = "Battery: \u{2026}"
        } else if let level = controller.batteryLevel {
            batteryItem.title = "Battery: \(level)%"
        } else {
            batteryItem.title = "Battery: \u{2014}"
        }

        statusItem?.button?.image = icon(connected: controller.isConnected)
    }

    private func icon(connected: Bool) -> NSImage? {
        let symbol = connected ? "hifispeaker.fill" : "hifispeaker"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "BoomBar")
        image?.isTemplate = true
        return image
    }

    @objc private func togglePower() {
        if controller.isConnected {
            controller.turnOff()
        } else {
            controller.turnOn { [weak self] result in
                if case .success = result {
                    self?.controller.readBattery()
                }
            }
        }
    }

    @objc private func connectAudio() {
        controller.connectAudio()
    }

    @objc private func refreshBattery() {
        controller.readBattery()
    }

    @objc private func toggleOutput() {
        _ = controller.toggleDefaultOutput()
        updateUI()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
