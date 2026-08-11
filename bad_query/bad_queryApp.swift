//
//  bad_queryApp.swift
//  bad_query
//
//  Created by Taj C on 8/10/26.
//

import SwiftUI

@main
struct bad_queryApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem {
                        Label("Sandbox", systemImage: "lock.open")
                    }
                AIEnablerView()
                    .tabItem {
                        Label("AI Enabler", systemImage: "brain")
                    }
            }
        }
    }
}
