//
//  myForkLiftApp.swift
//  myForkLift
//
//  Created by noone on 2025/11/17.
//

import SwiftUI
import AppKit

@main
struct myForkLiftApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .help) {
                Button("About myForkLift") {
                    showAboutDialog()
                }
                .keyboardShortcut("/")
            }
        }
    }
    
    private func showAboutDialog() {
        let alert = NSAlert()
        alert.messageText = "myForkLift"
        alert.informativeText = "Version v1.2.1\n\nAuthor: Shylock Wolf\nCreation Date: 2025-12-22"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
