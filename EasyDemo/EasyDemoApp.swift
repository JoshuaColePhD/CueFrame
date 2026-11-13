//
//  EasyDemoApp.swift
//  EasyDemo
//
//  Created by Daniel Oquelis on 28.10.25.
//

import SwiftUI
import AVFoundation

@main
struct EasyDemoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - Constants

    private let githubURL = "https://github.com/JoshuaColePhD/EasyDemo"

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(WindowAccessor())
        }
        .commands {
            configureAppInfoMenu()
            configureHelpMenu()
        }
        Settings { AISettingsView() }
    }

    // MARK: - Menu Configuration

    private func configureAppInfoMenu() -> some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Cueframe") {
                AboutWindowController.shared.showAboutWindow()
            }
        }
    }

    private func configureHelpMenu() -> some Commands {
        CommandGroup(replacing: .help) {
            if let url = URL(string: githubURL) {
                Link("Documentation", destination: url)
                    .keyboardShortcut("?", modifiers: .command)

                Divider()

                Link("View Source on GitHub", destination: url)
            }
        }
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if RecordingEngine.shared.phase == .recording {
            Task { @MainActor in
                _ = await RecordingEngine.shared.stopRecording()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        if RecordingEngine.shared.isRecording { return .terminateCancel }
        WebcamCapture.stopAllCaptures()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
