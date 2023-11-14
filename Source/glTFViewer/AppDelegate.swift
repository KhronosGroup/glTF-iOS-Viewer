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
import GLTFKit2

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    public let ubiquityContainerIdentifier = "iCloud.org.khronos.gltf.glTFViewer"

    public var launchURL: URL?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    {
        GLTFAsset.dracoDecompressorClassName = "DracoDecompressor"

        runFirstLaunchActionsIfNeeded()

        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration
    {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }

    private func runFirstLaunchActionsIfNeeded() {
        let firstLaunchKey = "HasRunFirstLaunchActions_v1_0"
        let userDefaults = UserDefaults.standard
        let hasRunFirstLaunchActions = userDefaults.value(forKey: firstLaunchKey) as? Bool ?? false
        if !hasRunFirstLaunchActions {
            runFirstLaunchActions()
            userDefaults.setValue(true, forKey: firstLaunchKey)
        }
    }

    private func runFirstLaunchActions() {
        print("Running first-launch actions...")

        DispatchQueue.global(qos: .background).async {
            do {
                let fileManager = FileManager.default
                var documentsDirectory: URL?
                let containerDirectory = fileManager.url(forUbiquityContainerIdentifier:self.ubiquityContainerIdentifier)
                if let containerDirectory {
                    documentsDirectory = containerDirectory.appendingPathComponent("Documents", isDirectory: true)
                    if let documentsDirectory {
                        try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
                    }
                }
                if documentsDirectory == nil {
                    print("Could not retrieve path of Ubiquity container. Falling back to local storage")
                    documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
                }
                if let documentsDirectory {
                    let readmeURL = documentsDirectory.appendingPathComponent("Read Me.txt", isDirectory: false)
                    let readmeText = "Add .gltf and .glb assets to this directory for the optimal viewing experience with the Khronos glTF Viewer app"
                    try readmeText.write(to: readmeURL, atomically: true, encoding: .utf8)
                }
            } catch {
                print("Failed to write readme: \(error)")
            }
        }
    }
}
