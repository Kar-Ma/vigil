//
//  VigilApp.swift
//  Vigil
//
//  Created by Karthik Mahadevan on 21/07/2026.
//

import GoogleSignIn
import SwiftUI

@main
struct VigilApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
