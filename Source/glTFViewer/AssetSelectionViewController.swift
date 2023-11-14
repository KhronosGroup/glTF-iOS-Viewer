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
import UniformTypeIdentifiers

class SampleAssetsTableViewCell: UITableViewCell {
    @IBOutlet weak var collectionView: UICollectionView!

    public override var reuseIdentifier: String {
        return "SampleAssetsTableViewCell"
    }
}

class OpenFromFilesTableViewCell: UITableViewCell {
    public override var reuseIdentifier: String {
        return "OpenFromFilesTableViewCell"
    }
}

protocol AssetSelectionDelegate : NSObject {
    func didSelectAssetWithURL(_ url: URL)
}

class AssetSelectionViewController : UITableViewController, UIDocumentPickerDelegate, AssetSelectionDelegate {

    private var currentDocumentBrowser: UIViewController?
    private var sampleAssetController = AssetCollectionViewController()
    private var metalDevice: MTLDevice?

    private let sampleAssetSectionHeight: CGFloat = 180 /* points */
    private let openInFilesSectionHeight: CGFloat = 44 /* points */

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        // We don't actually do anything with this Metal device, but creating it eagerly here
        // saves us a couple of frames of latency when pushing an asset viewer for the first time.
        metalDevice = MTLCreateSystemDefaultDevice()

        sampleAssetController.selectionDelegate = self
    }

    public func pushFileBrowser() {
        let glbType = UTType(filenameExtension: "glb", conformingTo: UTType.data)!
        let gltfType = UTType(filenameExtension: "gltf", conformingTo: UTType.data)!

        let documentBrowser = UIDocumentPickerViewController(forOpeningContentTypes: [gltfType, glbType])
        documentBrowser.allowsMultipleSelection = false
        documentBrowser.delegate = self
        self.present(documentBrowser, animated: true)
        currentDocumentBrowser = documentBrowser
    }

    public func pushAssetViewer(for assetURL: URL, isLocal: Bool) {
        let assetViewerStoryboard = UIStoryboard(name: "Main", bundle: nil)
        if let assetViewController = assetViewerStoryboard.instantiateViewController(withIdentifier: "AssetViewer") as? AssetViewController {
            assetViewController.modalPresentationStyle = .fullScreen
            assetViewController.assetURL = assetURL
            present(assetViewController, animated: true)
        }
        setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: - AssetSelectionDelegate

    func didSelectAssetWithURL(_ url: URL) {
        pushAssetViewer(for: url, isLocal: url.isFileURL)
    }

    // MARK: - UIDocumentPickerDelegate

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        controller.dismiss(animated: true) {
            if let documentURL = urls.first {
                self.pushAssetViewer(for: documentURL, isLocal: true)
            }
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch (indexPath.section) {
        case 0:
            return sampleAssetSectionHeight
        default:
            return openInFilesSectionHeight
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 1 {
            pushFileBrowser()
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Sample Assets"
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch (indexPath.section) {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SampleAssetsTableViewCell", for: indexPath)
            if let sampleAssetsCell = cell as? SampleAssetsTableViewCell {
                sampleAssetsCell.collectionView.dataSource = sampleAssetController
                sampleAssetsCell.collectionView.delegate = sampleAssetController
            }
            return cell
        case 1:
            return tableView.dequeueReusableCell(withIdentifier: "OpenFromFilesTableViewCell", for: indexPath)
        default:
            break
        }
        return tableView.dequeueReusableCell(withIdentifier: "", for: indexPath)
    }
}
