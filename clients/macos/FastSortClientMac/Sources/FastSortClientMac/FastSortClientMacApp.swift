import AppKit
import SwiftUI

@main
@MainActor
final class FastSortClientMacApp: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: FastSortClientMacApp?
    private var window: NSWindow?

    static func main() {
        disableStateRestoration()
        let app = NSApplication.shared
        let delegate = FastSortClientMacApp()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false
        app.finishLaunching()
        delegate.showMainWindow()
        DispatchQueue.main.async {
            delegate.showMainWindow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            delegate.showMainWindow()
        }
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.disableStateRestoration()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.disableStateRestoration()
        showMainWindow()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func showMainWindow() {
        if let window {
            if !window.isVisible || window.frame.width < 100 || window.frame.height < 100 {
                window.setFrame(Self.initialWindowFrame(), display: true)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = NSHostingView(rootView: NativeRootHostView())
        let initialFrame = Self.initialWindowFrame()
        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "迅拣"
        window.minSize = NSSize(width: 1180, height: 760)
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("FastSortMainWindow")
        window.restorationClass = nil
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private static func disableStateRestoration() {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let savedStateURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Saved Application State/\(bundleIdentifier).savedState")
        try? FileManager.default.removeItem(at: savedStateURL)
    }

    private static func initialWindowFrame() -> NSRect {
        NSRect(x: 120, y: 120, width: 1512, height: 900)
    }
}
