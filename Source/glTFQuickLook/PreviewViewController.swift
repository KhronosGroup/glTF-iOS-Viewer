import UIKit
import GLTFKit2
import QuickLook

class PreviewViewController: UIViewController, QLPreviewingController {
    public let environmentLightName = "Neutral-small.hdr"
    public let environmentIntensity = 0.8

    @IBOutlet var sceneView: SCNView!
    private var assetContainerNode = SCNNode()

    override func viewDidLoad() {
        super.viewDidLoad()

        sceneView.backgroundColor = UIColor(named: "BackgroundColor")
        sceneView.antialiasingMode = .multisampling4X
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = true
        sceneView.defaultCameraController.interactionMode = .orbitTurntable

        let scene = SCNScene()
        scene.rootNode.addChildNode(assetContainerNode)
        scene.lightingEnvironment.contents = environmentLightName
        scene.lightingEnvironment.intensity = environmentIntensity

        sceneView.scene = scene
    }
    
    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        loadAsset(url: url, completionHandler: handler)
    }

    private func loadAsset(url assetURL: URL, completionHandler handler: @escaping (Error?) -> Void) {
        GLTFAsset.load(with: assetURL, options: [:]) { (progress, status, maybeAsset, maybeError, _) in
            DispatchQueue.main.async {
                if status == .complete {
                    if let asset = maybeAsset {
                        self.prepareAsset(asset, completionHandler: handler)
                    }
                } else {
                    handler(maybeError)
                }
            }
        }
    }

    private func prepareAsset(_ asset: GLTFAsset, completionHandler handler: @escaping (Error?) -> Void) {
        let source = GLTFSCNSceneSource(asset: asset)
        guard let assetScene = source.defaultScene else {
            handler(nil)
            return
        }

        for node in assetScene.rootNode.childNodes {
            assetContainerNode.addChildNode(node)
        }

        DispatchQueue.main.async {
            guard let scene = self.sceneView.scene else { return }

            self.sceneView.prepare([scene]) { _ in
                DispatchQueue.main.async {
                    handler(nil)
                }
            }
        }
    }
}
