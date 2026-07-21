//
//  VigilApp.swift
//  Vigil
//
//  Created by Karthik Mahadevan on 21/07/2026.
//

import AppIntents
import GoogleSignIn
import SwiftUI

@main
struct VigilApp: App {
    init() {
        VigilShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
