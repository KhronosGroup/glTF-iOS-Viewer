import UIKit
import GLTFKit2
import SceneKit
import QuickLookThumbnailing

class ThumbnailProvider: QLThumbnailProvider {

    public let environmentLightName = "Neutral-small.hdr"
    public let environmentIntensity = 0.8

    private let scene = SCNScene()
    private let sceneRenderer: SCNRenderer
    private let assetContainerNode = SCNNode()

    override init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this system")
        }

        sceneRenderer = SCNRenderer(device: device, options: [:])
        sceneRenderer.scene = scene
        sceneRenderer.autoenablesDefaultLighting = false

        scene.rootNode.addChildNode(assetContainerNode)
        scene.background.contents = UIColor.lightGray
        scene.lightingEnvironment.contents = environmentLightName
        scene.lightingEnvironment.intensity = environmentIntensity

        super.init()
    }

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let reply = QLThumbnailReply(contextSize: request.maximumSize, currentContextDrawing: { () -> Bool in
            do {
                let assetURL = request.fileURL
                let asset = try GLTFAsset(url: assetURL)
                let source = GLTFSCNSceneSource(asset: asset)
                if let assetScene = source.defaultScene {
                    // Clear out existing nodes, since this provider can be reused by the system
                    while self.assetContainerNode.childNodes.count > 0 {
                        self.assetContainerNode.childNodes.first?.removeFromParentNode()
                    }
                    for node in assetScene.rootNode.childNodes {
                        self.assetContainerNode.addChildNode(node)
                    }
                    let image = self.sceneRenderer.snapshot(atTime: 0.0,
                                                            with: request.maximumSize,
                                                            antialiasingMode: .multisampling4X)
                    image.draw(at: .zero)
                } else {
                    return false
                }
            } catch {
                print("Failed to load asset for thumbnail generation: \(error)")
                return false
            }
            return true
        })
        handler(reply, nil)
    }
}
