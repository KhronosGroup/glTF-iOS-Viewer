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
import OSLog

class SampleAssetCollectionViewCell: UICollectionViewCell {
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!

    public override var reuseIdentifier: String {
        return "SampleAssetCollectionViewCell"
    }

    public var representedAsset: LocalAssetDescription? {
        didSet {
            imageView.image = representedAsset?.previewImage
            titleLabel.text = representedAsset?.displayName
        }
    }
}

class AssetCollectionViewController : UICollectionViewController, UICollectionViewDelegateFlowLayout {

    let assetStore = SampleAssetStore.default

    weak var selectionDelegate: AssetSelectionDelegate?

    private var log = Logger()

    // This method produces a collection view layout that lays out all items in a single horizontal row
    private var layout: UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(75), heightDimension: .absolute(75))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, repeatingSubitem: item, count: 1)
        group.edgeSpacing = NSCollectionLayoutEdgeSpacing(leading: .fixed(16), top: .flexible(0), trailing: nil, bottom: .flexible(0))

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 0

        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.scrollDirection = .horizontal

        let layout = UICollectionViewCompositionalLayout(section: section, configuration:config)
        return layout
    }

    // MARK: - UICollectionViewDataSource

    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return assetStore.assets.count
    }

    override func collectionView(_ collectionView: UICollectionView,
                                 cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
    {
        let asset = assetStore.assets[indexPath.item]
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "SampleAssetCollectionViewCell", for: indexPath)
        (cell as? SampleAssetCollectionViewCell)?.representedAsset = asset
        return cell
    }

    // MARK: - UICollectionViewDelegate

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let asset = assetStore.assets[indexPath.item]
        if let assetURL = asset.assetURL {
            selectionDelegate?.didSelectAssetWithURL(assetURL)
        } else {
            log.notice("Could not find asset \(asset.filename) in bundle")
        }
        collectionView.deselectItem(at: indexPath, animated: false)
    }

    // MARK: - UICollectionViewDelegateFlowLayout

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize
    {
        return CGSize(width: 132, height: 148)
    }

}
