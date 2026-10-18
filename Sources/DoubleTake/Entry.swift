import AppKit

@main
enum Entry {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if CLI.shouldRun(arguments) {
            exit(CLI.run(arguments))
        }
        // Only one copy of the menu bar app at a time.
        let me = NSRunningApplication.current
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Installer.bundleID)
            .first(where: { $0 != me && $0.processIdentifier != me.processIdentifier }) {
            other.activate()
            exit(0)
        }
        DoubleTakeApp.main()
    }
}
