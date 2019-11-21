//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import UIKit
import SwiftUI
import PLRelationalCombine

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    var contentViewModel: ContentViewModel!

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Create the SwiftUI view that provides the window contents
        // TODO: Specify path for persistence
        let undoManager = PLRelationalCombine.UndoManager()
        let model = Model(undoManager: undoManager, path: nil)
        if !model.dbAlreadyExisted {
            _ = model.addDefaultData()
        }
        contentViewModel = ContentViewModel(model: model)
        let contentView = ContentView(model: contentViewModel)

        // Use a UIHostingController as window root view controller
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = UIHostingController(rootView: contentView)
            self.window = window
            window.makeKeyAndVisible()
        }
    }
}
