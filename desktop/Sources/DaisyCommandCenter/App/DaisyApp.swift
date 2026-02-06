import SwiftUI
import AppKit

// MARK: - App Delegate for Window Focus

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {

        // Set as regular app so it can receive keyboard focus

        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Start MCP server for Claude Code integration

        MCPServer.shared.start()

        // Install CLI tool

        let cliPath = FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin/daisy"
        let binDir = (cliPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        MCPServer.shared.installCLI(to: cliPath)

        // Auto-start all persona sessions after a short delay

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            DataStore.shared.autoStartAllSessions()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let window = NSApplication.shared.windows.first {
                window.makeKeyAndOrderFront(nil)
                window.appearance = NSAppearance(named: .darkAqua)
                window.backgroundColor = NSColor(white: 0.05, alpha: 1.0)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        return true
    }
}

// MARK: - App Entry Point

@main
struct DaisyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {

        // Write to a debug file

        let debugFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("daisy-debug.log")
        let msg = "[\(Date())] DAISY APP STARTING\n"
        try? msg.write(to: debugFile, atomically: true, encoding: .utf8)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let window = NSApplication.shared.windows.first {
                        window.makeKey()
                        window.makeKeyAndOrderFront(nil)
                    }
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
