//
//  _Music2FuriousApp.swift
//  2Music2Furious
//
//  Created by Brian McDonald on 12/2/25.
//

import SwiftUI

@main
struct _Music2FuriousApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                // Check for articles added via Share Extension
                ArticleManager.shared.checkForPendingArticles()
            }
        }
    }
}
