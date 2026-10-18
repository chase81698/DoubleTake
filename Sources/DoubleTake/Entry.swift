import AppKit

@main
enum Entry {
    /// Passed by the login item so the app starts without opening its window.
    static let backgroundFlag = "--background"

    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if CLI.shouldRun(arguments) {
            exit(CLI.run(arguments))
        }
        let background = arguments.contains(backgroundFlag)

        // Only one copy runs at a time; a second launch just brings up the first one's window.
        let me = NSRunningApplication.current
        if NSRunningApplication.runningApplications(withBundleIdentifier: Installer.bundleID)
            .contains(where: { $0.processIdentifier != me.processIdentifier }) {
            if !background {
                DistributedNotificationCenter.default().postNotificationName(
                    AppDelegate.showWindowNotification, object: nil, userInfo: nil, deliverImmediately: true)
            }
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate(launchedInBackground: background)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
