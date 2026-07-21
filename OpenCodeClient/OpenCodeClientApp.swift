//
//  OpenCodeClientApp.swift
//  OpenCodeClient
//
//  Created by Mauricio Istúriz on 7/19/26.
//

import SwiftUI

@main
struct OpenCodeClientApp: App {
    @State private var appModel: AppModel

    init() {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            let dependencies: AppDependencies
            if arguments.contains("UITEST_EMPTY") {
                dependencies = .uiTestEmpty
            } else if arguments.contains("UITEST_WORKSPACE") {
                dependencies = .uiTestWorkspace
            } else {
                dependencies = .live
            }
        #else
            let dependencies = AppDependencies.live
        #endif
        _appModel = State(initialValue: AppModel(dependencies: dependencies))
    }

    var body: some Scene {
        WindowGroup {
            RootView(appModel: appModel)
        }
    }
}
