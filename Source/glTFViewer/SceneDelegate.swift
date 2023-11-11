//
// Copyright 2023 The Khronos Group, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var launchURL: URL?

    var rootNavigationController: NavigationController? {
        return window?.rootViewController as? NavigationController
    }

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions)
    {
        if let launchURLContext = connectionOptions.urlContexts.first {
            // If we launched with a URL to open, defer opening it until our UI is on screen
            launchURL = launchURLContext.url
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // If we deferred opening a launch URL, open it now
        if let launchURL = self.launchURL {
            openURL(launchURL)
            self.launchURL = nil
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // If we're being asked to open a URL while already running, open it immediately
        if let firstContext = URLContexts.first {
            let assetURL = firstContext.url
            openURL(assetURL)
        }
    }

    private func openURL(_ url: URL) {
        guard let navigationController = rootNavigationController else {
            print("Scene did not have a navigation controller at its root; will not open requested URLs...")
            return
        }

        // If we've previously presented a view controller, dismiss it before trying to present another
        if navigationController.presentedViewController != nil {
            navigationController.dismiss(animated: false)
        }

        let assetViewerStoryboard = UIStoryboard(name: "Main", bundle: nil)
        if let assetViewController = assetViewerStoryboard.instantiateViewController(withIdentifier: "AssetViewer") as? AssetViewController {
            assetViewController.modalPresentationStyle = .fullScreen
            assetViewController.assetURL = url
            navigationController.present(assetViewController, animated: false)
        }
    }
}
