//
//  Squirrel2App.swift
//  Squirrel2
//
//  Created by Bradley Ryan on 8/25/25.
//

import SwiftUI
import FirebaseCore

@main
struct Squirrel2App: App {
    @StateObject private var firebaseManager: FirebaseManager
    
    init() {
        // Configure Firebase FIRST, before anything else
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        
        // Now create the FirebaseManager after Firebase is configured
        let manager = FirebaseManager()
        _firebaseManager = StateObject(wrappedValue: manager)
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(firebaseManager)
        }
    }
}
