import AppKit
import Darwin

enum SingleInstance {
    private static var lockFD: Int32 = -1

    static func claimOrTerminate() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("BoomBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let lockURL = base.appendingPathComponent(lockID + ".lock")

        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            activateExisting()
            exit(0)
        }
        lockFD = fd
    }

    private static var lockID: String {
        Bundle.main.bundleIdentifier ?? "com.synchro.boombar"
    }

    private static func activateExisting() {
        let me = ProcessInfo.processInfo.processIdentifier
        let candidates: [NSRunningApplication]
        if let bid = Bundle.main.bundleIdentifier {
            candidates = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
        } else {
            let name = ProcessInfo.processInfo.processName
            candidates = NSWorkspace.shared.runningApplications.filter {
                $0.localizedName == name || $0.executableURL?.lastPathComponent == name
            }
        }
        if let existing = candidates.first(where: { $0.processIdentifier != me }) {
            existing.activate()
        }
    }
}
