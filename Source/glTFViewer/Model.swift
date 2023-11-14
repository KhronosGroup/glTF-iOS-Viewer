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

import Foundation
import UIKit

struct LocalAssetDescription {
    var displayName: String
    var filename: String
    var previewImageName: String

    var assetURL: URL? {
        return Bundle.main.url(forResource: filename, withExtension: nil)
    }

    var previewImage: UIImage? {
        guard let thumbnail = UIImage(named: previewImageName) else {
            // TODO: Add fallback thumbnail image?
            print("Could not find preview image named \(previewImageName) in app bundle")
            return nil
        }
        return thumbnail
    }
}

class SampleAssetStore {
    static let `default` = SampleAssetStore()

    let assets: [LocalAssetDescription]

    init() {
        do {
            let sampleAssetURL = Bundle.main.url(forResource: "SampleAssets", withExtension: "plist")!
            let plistData = try Data(contentsOf: sampleAssetURL)
            var format = PropertyListSerialization.PropertyListFormat.xml
            let root = try PropertyListSerialization.propertyList(from: plistData, format:&format)
            if let assetArray = root as? [[String : Any]] {
                assets = assetArray.map({ assetDescription in
                    return LocalAssetDescription(displayName: assetDescription["displayName"] as? String ?? "",
                                                 filename: assetDescription["filename"] as? String ?? "",
                                                 previewImageName: assetDescription["previewImageName"] as? String ?? "")
                })
            } else {
                print("Did not find sample assset plist in correct format in app bundle")
                assets = []
            }
        } catch {
            print("Error when deserializing sample asset plist: \(error)")
            assets = []
        }
    }
}

extension GLTFAsset {
    var referencedURLs : [URL] {
        var urls = [URL]()
        for buffer in self.buffers {
            if let bufferURL = buffer.uri, bufferURL.isFileURL {
                urls.append(bufferURL)
            }
        }
        for image in self.images {
            if let imageURL = image.uri, imageURL.isFileURL {
                urls.append(imageURL)
            }
        }
        return urls
    }
}

struct AssetInformationItem {
    enum ContentPresentation {
        case singleLine
        case multipleLine
    }

    var title: String?
    var contents: String?
    var contentsPresentation: ContentPresentation

    init(title: String? = nil,
         contents: String? = nil,
         presentation: ContentPresentation = .singleLine)
    {
        self.title = title
        self.contents = contents
        self.contentsPresentation = presentation
    }
}

struct AssetInformation {
    let metadata: [AssetInformationItem]
    let statistics: [AssetInformationItem]
    let copyright: [AssetInformationItem]

    private let fileSizeFormatter: ByteCountFormatter!
    private let largeNumberFormatter: NumberFormatter!

    init(_ asset: GLTFAsset) {
        fileSizeFormatter = ByteCountFormatter()
        largeNumberFormatter = NumberFormatter()
        largeNumberFormatter.numberStyle = .decimal
        largeNumberFormatter.usesGroupingSeparator = true

        var metadataInfo = [AssetInformationItem]()
        if let fileName = asset.url?.lastPathComponent {
            metadataInfo.append(AssetInformationItem(title: "Filename", contents: fileName))
        }
        if let generator = asset.generator {
            metadataInfo.append(AssetInformationItem(title: "Generator", contents: generator))
        }
        if let extras = asset.extras as? [String : Any] {
            // Look for common metadata included by Sketchfab
            if let title = extras["title"] as? String {
                metadataInfo.insert(AssetInformationItem(title: "Title", contents: title), at: 0)
            }
            if let author = extras["author"] as? String {
                metadataInfo.append(AssetInformationItem(title: "Author", contents: author, presentation: .multipleLine))
            }
            if let source = extras["source"] as? String {
                metadataInfo.append(AssetInformationItem(title: "Source", contents: source, presentation: .multipleLine))
            }
        }

        var statisticsInfo = [AssetInformationItem]()

        do {
            var fileSizeValue: AnyObject?
            try (asset.url as? NSURL)?.getResourceValue(&fileSizeValue, forKey: .fileSizeKey)
            if let fileSizeNumber = fileSizeValue as? NSNumber {
                statisticsInfo.append(AssetInformationItem(title: "Asset File Size",
                                                           contents: fileSizeFormatter.string(fromByteCount: fileSizeNumber.int64Value)))
            }

            var totalReferencedFileSize: Int64 = 0
            for url in asset.referencedURLs {
                try (url as NSURL).getResourceValue(&fileSizeValue, forKey: .fileSizeKey)
                if let fileSizeNumber = fileSizeValue as? NSNumber {
                    totalReferencedFileSize += fileSizeNumber.int64Value
                }
            }
            if totalReferencedFileSize > 0 {
                statisticsInfo.append(AssetInformationItem(title: "Referenced File Size",
                                                           contents: fileSizeFormatter.string(fromByteCount: totalReferencedFileSize)))
            }
        } catch {}

        let vertexCount = asset.meshes.reduce(0) { partialResult, mesh in
            return partialResult + mesh.primitives.reduce(0, { partialResult, primitive in
                let positionAttribute = primitive.attribute(forName: "POSITION")
                return partialResult + (positionAttribute?.accessor.count ?? 0)
            })
        }
        
        let triangleCount = asset.meshes.reduce(0) { partialResult, mesh in
            return partialResult + mesh.primitives.reduce(0, { partialResult, primitive in
                let positionAttribute = primitive.attribute(forName: "POSITION")
                let indexCount = primitive.indices?.count ?? positionAttribute?.accessor.count ?? 0
                switch primitive.primitiveType {
                case .triangles:
                    return partialResult + (indexCount / 3)
                case .triangleStrip:
                    return partialResult + (indexCount - 2)
                case .triangleFan:
                    return partialResult + (indexCount - 2)
                default:
                    return partialResult
                }
            })
        }
        statisticsInfo.append(AssetInformationItem(title: "Vertices",
                                                   contents: largeNumberFormatter.string(from: NSNumber(value: vertexCount))))
        statisticsInfo.append(AssetInformationItem(title: "Triangles",
                                                   contents: largeNumberFormatter.string(from: NSNumber(value: triangleCount))))
        if asset.animations.count > 0 {
            statisticsInfo.append(AssetInformationItem(title: "Animations",
                                                       contents: largeNumberFormatter.string(from: NSNumber(value: asset.animations.count))))
        }

        var copyrightInfo = [AssetInformationItem]()

        if let extras = asset.extras as? [String : Any] {
            // Look for Sketchfab license info
            if let license = extras["license"] as? String {
                copyrightInfo.append(AssetInformationItem(title: "License", contents: license, presentation: .multipleLine))
            }
        }
        if let copyright = asset.copyright {
            copyrightInfo.append(AssetInformationItem(title: "Copyright", contents: copyright, presentation: .multipleLine))
        }

        self.metadata = metadataInfo
        self.statistics = statisticsInfo
        self.copyright = copyrightInfo
    }
}
