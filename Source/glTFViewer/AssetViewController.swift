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
import SceneKit
import ARKit
import GLTFKit2
import CoreHaptics
import OSLog

class AssetViewController: UIViewController,
                           UIDocumentPickerDelegate,
                           UIGestureRecognizerDelegate,
                           ARSessionDelegate,
                           ARSCNViewDelegate
{
    enum ViewerMode {
        case object
        case AR
    }
    var mode = ViewerMode.object {
        didSet {
            if mode != oldValue {
                transitionToViewerMode(mode)
            }
        }
    }

    public let environmentLightName = "Neutral-small.hdr"
    public let environmentIntensity = 1.0

    public var assetURL: URL? {
        didSet {
            assetDirectory = assetURL?.deletingLastPathComponent()
        }
    }
    private var assetDirectory: URL?
    private var assetInfo: AssetInformation?
    private var animations = [GLTFSCNAnimation]()
    private var assetContainerNode: SCNNode!
    private let assetContainerName = "AssetContainer"
    private let assetConversionQueue = DispatchQueue.global(qos: .userInitiated)

    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var modeSelectionControl: UISegmentedControl!
    @IBOutlet weak var infoButton: UIButton!
    @IBOutlet weak var sceneView: SCNView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var modeTransitionView: UIView!
    private weak var arSceneView: ARSCNView!

    private var hasRenderedFirstFrameForAsset = false {
        didSet {
            if hasRenderedFirstFrameForAsset {
                activityIndicator.isHidden = true
                progressView.isHidden = true
            }
        }
    }

    private var arSessionIsRunning = false
    private var currentlyPresentedViewController: UIViewController?

    private let log = Logger()
    private let device = MTLCreateSystemDefaultDevice()!
    
    private var supportsHaptics: Bool = false
    private var hapticsReady: Bool = false
    private var hapticEngine: CHHapticEngine?
    private var hapticTapPlayer: CHHapticPatternPlayer?

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - View controller lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        let hapticCapability = CHHapticEngine.capabilitiesForHardware()
        supportsHaptics = hapticCapability.supportsHaptics
        if supportsHaptics {
            prepareHaptics()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        log.info("Asset view will appear to display asset at \(self.assetURL?.path ?? "Invalid path")")

        progressView.isHidden = true
        activityIndicator.isHidden = false
        activityIndicator.startAnimating()

        closeButton.layer.cornerRadius = 10.0
        infoButton.layer.cornerRadius = 10.0

        view.addConstraint(NSLayoutConstraint(item: modeSelectionControl!, attribute: .height,
                                              relatedBy: .equal,
                                              toItem: closeButton, attribute: .height,
                                              multiplier: 1.0, constant: 0))

        // Hide the mode selection control in unsupported contexts (macOS, Vision Pro, etc.)
        if !ARWorldTrackingConfiguration.isSupported {
            modeSelectionControl.isHidden = true
        }

        assetContainerNode = SCNNode()
        assetContainerNode.name = assetContainerName

        sceneView.delegate = self
        configureSceneView(sceneView, for: .object)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        log.info("Asset view did appear")

        loadAsset()

        let arView = ARSCNView(frame: view.bounds, options: [:])
        modeTransitionView.addSubview(arView)
        arSceneView = arView
        arSceneView.delegate = self
        arSceneView.session.delegate = self
        arSceneView.isHidden = true
        arSceneView.translatesAutoresizingMaskIntoConstraints = false
        modeTransitionView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "|[subview]|",
                                                                         metrics: nil,
                                                                         views: ["subview" : arSceneView!]))
        modeTransitionView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[subview]|",
                                                                         metrics: nil,
                                                                         views: ["subview" : arSceneView!]))
        configureSceneView(arSceneView, for: .AR)
        installARGestures(on: arSceneView)
    }

    override func viewWillDisappear(_ animated: Bool) {
        pauseARSession()
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if segue.identifier == "ShowInfoSheet" {
            // Configure info sheet to only take up the bottom half of the screen in compact size classes
            segue.destination.sheetPresentationController?.detents = [.medium()]

            if let infoNavigationController = (segue.destination as? UINavigationController),
               let infoController = (infoNavigationController.viewControllers.first as? AssetInformationViewController)
            {
                infoController.assetInfo = self.assetInfo
            }
        } else {
            log.notice("Asset view controller was asked to prepare for a segue it does not recognize")
        }
    }

    // MARK: -

    private func configureSceneView(_ sceneView: SCNView, for viewingMode: ViewerMode) {
        log.info("Configuring a scene view for \(String(describing: viewingMode)) mode")

        sceneView.backgroundColor = UIColor(named: "ObjectModeBackgroundColor")

        sceneView.antialiasingMode = .multisampling4X
        sceneView.autoenablesDefaultLighting = false

        let scene = SCNScene()

        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.automaticallyAdjustsZRange = true
        cameraNode.camera = camera

        if (viewingMode == .object) {
            sceneView.allowsCameraControl = true
            sceneView.defaultCameraController.interactionMode = .orbitTurntable
            sceneView.defaultCameraController.pointOfView = cameraNode
            scene.rootNode.addChildNode(cameraNode)
        } else {
            sceneView.allowsCameraControl = false
            sceneView.pointOfView = cameraNode
            camera.wantsExposureAdaptation = true
            camera.exposureOffset = -1
            camera.minimumExposure = -1
            camera.maximumExposure = 3
        }

        let sunLight = SCNLight()
        sunLight.type = .directional
        sunLight.intensity = 400
        sunLight.color = UIColor.white
        sunLight.castsShadow = true
        sunLight.shadowMapSize = CGSize(width: 2048, height: 2048)
        sunLight.shadowBias = 2.0
        if (viewingMode == .AR) {
            // When in AR mode, use deferred mode to cast shadows onto virtual plane geometry
            sunLight.shadowMode = .deferred
            sunLight.shadowColor = UIColor(white: 0.0, alpha: 0.20)
        }
        let sun = SCNNode()
        sun.light = sunLight
        scene.rootNode.addChildNode(sun)
        sun.look(at: SCNVector3(-0.25, -1, -0.25))

        scene.lightingEnvironment.contents = environmentLightName
        scene.lightingEnvironment.intensity = environmentIntensity

        sceneView.scene = scene
    }

    // MARK: - IBActions

    @IBAction func closeButtonWasTapped(_ sender: Any) {
        self.dismiss(animated: true)
    }

    @IBAction func modeSelectionDidChange(_ sender: Any) {
        if modeSelectionControl.selectedSegmentIndex == 0 {
            mode = .object
        } else if modeSelectionControl.selectedSegmentIndex == 1 {
            mode = .AR
        }
    }

    // MARK: - Asset Loading

    private func loadAsset() {
        guard let assetURL else {
            log.notice("No asset URL provided to asset viewer; skipping load...")
            return
        }

        log.info("Loading asset")

        hasRenderedFirstFrameForAsset = false

        var accessingScopedResource = assetURL.startAccessingSecurityScopedResource()

        let options = assetDirectory != nil ? [ GLTFAssetLoadingOption.assetDirectoryURLKey : assetDirectory!] : [:]
        GLTFAsset.load(with: assetURL, options: options) { (progress, status, maybeAsset, maybeError, _) in
            self.log.info("Asset loading callback called with status \(String(describing: status.rawValue)), progress \(progress * 100)%")
            DispatchQueue.main.async {
                if accessingScopedResource {
                    assetURL.stopAccessingSecurityScopedResource()
                    accessingScopedResource = false
                }

                if status == .complete {
                    if let asset = maybeAsset {
                        // Store some metadata so we don't have to retain the whole asset in memory
                        self.assetInfo = AssetInformation(asset)
                        // Convert the asset to SceneKit format and display it
                        self.prepareAssetAsync(asset)
                    }
                } else if let error = maybeError {
                    self.log.notice("Error occurred during asset loading: \(error)")
                    self.handleError(error, forAssetAtURL: assetURL)
                }

                if progress < 1.0 && status != .complete && maybeError == nil {
                    self.log.info("Asset loading complete")
                    self.activityIndicator.isHidden = true
                    self.progressView.isHidden = false
                    self.progressView.progress = progress
                }
            }
        }
    }

    private func handleError(_ error: Error, forAssetAtURL assetURL: URL?) {
        let nsError = error as NSError
        if (nsError.code == GLTFErrorCodeIOError) && assetURL != nil {
            log.info("File I/O error. Will attempt recovery by requesting additional file permissions.")

            // Clear any prior alert or other popover before asking for additional permissions
            currentlyPresentedViewController?.dismiss(animated: false)

            let assetDirectory = assetURL!.deletingLastPathComponent()
            let accessRequestMessage = "Grant access by selecting the folder containing this asset (\"\(assetDirectory.lastPathComponent)\") in the file picker and tapping \"Open.\""
            let alertController = UIAlertController(title: "Additional Access Required",
                                                    message: accessRequestMessage,
                                                    preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
                self.currentlyPresentedViewController = nil
                self.dismiss(animated: true)
            }))
            let okAction = UIAlertAction(title: "OK", style: .default, handler: { _ in
                self.currentlyPresentedViewController = nil
                let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
                documentPicker.delegate = self
                documentPicker.directoryURL = assetDirectory
                self.present(documentPicker, animated: true) {
                    self.currentlyPresentedViewController = documentPicker
                }
            })
            alertController.addAction(okAction)
            alertController.preferredAction = okAction
            present(alertController, animated: true) {
                self.currentlyPresentedViewController = alertController
            }
        } else {
            if self.currentlyPresentedViewController != nil { return }

            let alertController = UIAlertController(title: "Error Loading Asset",
                                                    message: "Could not load the specified asset.\n(Error code \(nsError.code))",
                                                    preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                self.currentlyPresentedViewController = nil
            }))
            present(alertController, animated: true) {
                self.currentlyPresentedViewController = alertController
            }
        }
    }

    private func prepareAssetAsync(_ asset: GLTFAsset) {
        log.info("Converting asset default scene to SceneKit")
        assetConversionQueue.async {
            let source = GLTFSCNSceneSource(asset: asset)
            guard let assetScene = source.defaultScene else { return }
            self.animations = source.animations

            for node in assetScene.rootNode.childNodes {
                self.assetContainerNode.addChildNode(node)
            }

            // Uncomment to visualize computed bounding box
            /*
            let (minCorner, maxCorner) = self.assetContainerNode.boundingBox
            let boundingGeometry = SCNBox(width: CGFloat(maxCorner.x - minCorner.x),
                                          height: CGFloat(maxCorner.y - minCorner.y),
                                          length: CGFloat(maxCorner.z - minCorner.z), chamferRadius: 0.0)
            boundingGeometry.firstMaterial?.diffuse.contents = UIColor(white: 1.0, alpha: 0.2)
            let boundingNode = SCNNode(geometry: boundingGeometry)
            boundingNode.position = SCNVector3((simd_float3(minCorner) + simd_float3(maxCorner)) * 0.5)
            self.assetContainerNode.addChildNode(boundingNode)
             */

            self.prepareAndDisplayScene() {
                if !self.hasRenderedFirstFrameForAsset {
                    self.log.info("SceneKit did render the asset for the first time")
                    self.hasRenderedFirstFrameForAsset = true
                }
            }
        }
    }

    private func prepareAndDisplayScene(completion: @escaping () -> Void) {
        let view: SCNView! = mode == .object ? sceneView : arSceneView
        let scene: SCNScene! = view.scene
        let pointOfView: SCNNode! = view.pointOfView

        DispatchQueue.main.async {
            scene.rootNode.addChildNode(self.assetContainerNode)

            let (sceneCenter, sceneRadius) = scene.rootNode.boundingSphere
            let simdCenter = simd_float3(Float(sceneCenter.x), Float(sceneCenter.y), Float(sceneCenter.z))
            pointOfView.simdPosition = sceneRadius * SIMD3<Float>(0, 0, 3) + simdCenter
            pointOfView.look(at: sceneCenter, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))

            self.log.info("Requesting SceneKit prepare scene for rendering")
            view.prepare([scene!]) { _ in
                if let defaultAnimation = self.animations.first {
                    scene.rootNode.addAnimationPlayer(defaultAnimation.animationPlayer, forKey: nil)
                    defaultAnimation.animationPlayer.play()
                }
                DispatchQueue.main.async {
                    self.log.info("SceneKit reported scene preparation complete")
                    completion()
                }
            }
        }
    }

    private func transitionToViewerMode(_ mode: ViewerMode) {
        log.info("Transitioning to view mode \(String(describing: mode))")

        let outgoingView: SCNView! = mode == .object ? arSceneView : sceneView
        let incomingView: SCNView! = mode == .object ? sceneView : arSceneView

        outgoingView.isHidden = true
        incomingView.isHidden = false

        switch mode {
        case .object:
            let scene: SCNScene! = sceneView.scene
            let pointOfView: SCNNode! = sceneView.pointOfView

            scene.rootNode.addChildNode(assetContainerNode)

            assetContainerNode.pivot = SCNMatrix4Identity
            assetContainerNode.transform = SCNMatrix4Identity

            let (sceneCenter, sceneRadius) = assetContainerNode.boundingSphere
            let simdCenter = simd_float3(sceneCenter)
            pointOfView.simdPosition = sceneRadius * simd_float3(0, 0, 3) + simdCenter
            pointOfView.look(at: sceneCenter, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))

        case .AR:
            arSceneView.pointOfView!.addChildNode(assetContainerNode)

            let (minPoint, maxPoint) = assetContainerNode.boundingBox
            assetContainerNode.pivot = SCNMatrix4MakeTranslation((minPoint.x + maxPoint.x) / 2,
                                                                 (minPoint.y + maxPoint.y) / 2,
                                                                 (minPoint.z + maxPoint.z) / 2)

            assetContainerNode.scale = preferredSceneScale()
            assetContainerNode.position = SCNVector3(0, 0, -0.5)
        }

        currentPlaneAnchor = nil // Regardless of whether we were attached to a plane anchor, we aren't now

        if !arSceneView.isHidden {
            assetContainerNode.isHidden = true // Hide scene until we get a frame update
            startARSession()
        } else {
            pauseARSession()
        }
    }

    // MARK: - Gestures

    private var longPressGesture: UILongPressGestureRecognizer!
    private var rotationGesture: UIRotationGestureRecognizer!
    private var panGesture: UIPanGestureRecognizer!
    private var zoomGesture: UIPinchGestureRecognizer!
    private var rotationDelta: Float = 0
    private var scaleFactorDelta: Float = 0
    private var cumulativeRotation: Float = 0
    private var cumulativeScale: Float = 0
    private var dragGestureIsActive = false
    private var panGestureIsActive = false
    private var dragTouchLocation = CGPoint.zero
    private var currentPlaneAnchor: ARPlaneAnchor?
    private var worldAnchorPoint: SCNVector3?
    // Minimum distance from the camera at which an asset will be placed if it is not already attached to a surface
    // We need this so we don't place a huge asset directly in front of the user's face if they're seated at a desk/table.
    private let minimumInitialPlacementDistance: Float = 0.5

    private func installARGestures(on view: SCNView) {
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(longPressDidRecognize(_:)))
        longPressGesture.delegate = self
        longPressGesture.minimumPressDuration = 0.05
        view.addGestureRecognizer(longPressGesture)

        rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(rotateDidRecognize(_:)))
        rotationGesture.delegate = self
        view.addGestureRecognizer(rotationGesture)

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(panDidRecognize(_:)))
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)

        zoomGesture = UIPinchGestureRecognizer(target: self, action: #selector(zoomDidRecognize(_:)))
        zoomGesture.delegate = self
        view.addGestureRecognizer(zoomGesture)
    }

    private func updateARGestures() {
        guard mode == .AR else { return }

        if let _ = worldAnchorPoint {
            if dragGestureIsActive || panGestureIsActive {
                if let placementQuery = arSceneView.raycastQuery(from: dragTouchLocation,
                                                                 allowing: .existingPlaneGeometry,
                                                                 alignment: .any)
                {
                    // Now that we have our list of candidate plane intersections, find the one closest to the camera
                    let planeCastHits = arSceneView.session.raycast(placementQuery)
                    let cameraPosition = arSceneView.pointOfView!.simdWorldPosition
                    let closestPlaneHit = planeCastHits.sorted(by: { lhs, rhs in
                        let lhsDistance = simd_length_squared(cameraPosition - lhs.worldTransform.columns.3.xyz)
                        let rhsDistance = simd_length_squared(cameraPosition - rhs.worldTransform.columns.3.xyz)
                        return lhsDistance < rhsDistance
                    }).first

                    if let closestPlaneHit {
                        if let planeAnchor = closestPlaneHit.anchor as? ARPlaneAnchor {
                            let hitPoint = closestPlaneHit.worldTransform.columns.3.xyz
                            attachToPlaneAnchor(planeAnchor, at: hitPoint)
                        }
                    }
                }
            }
            if rotationDelta != 0.0 {
                // Accumulate rotational delta from gestures to find target rotation
                cumulativeRotation += rotationDelta
            }
            if scaleFactorDelta != 1.0 {
                let oldScale = cumulativeScale
                cumulativeScale *= scaleFactorDelta
                let scaleDetentTolerance: Float = 0.05
                if (abs(1.0 - oldScale) > scaleDetentTolerance && abs(1.0 - cumulativeScale) < scaleDetentTolerance) {
                    playHapticTap()
                }
            }

            updateSceneTransform()
        } else {
            // We are not currently attached to a plane anchor, so we have no real-world point to move
            // relative to. We perform a ray cast through the center of the screen looking for the nearest
            // plane. If we find a good candidate, we attach ourself to the corresponding plane
            let screenSpaceCastOrigin = CGPoint(x: arSceneView.bounds.midX, y: arSceneView.bounds.midY)
            if let placementQuery = arSceneView.raycastQuery(from: screenSpaceCastOrigin,
                                                             allowing: .existingPlaneGeometry,
                                                             alignment: .any)
            {
                // Now that we have our list of candidate plane intersections, find the one closest to the camera
                let planeCastHits = arSceneView.session.raycast(placementQuery)
                let cameraPosition = arSceneView.pointOfView!.simdWorldPosition
                let sortedPlaneHits = planeCastHits.sorted(by: { lhs, rhs in
                    let lhsDistance = simd_length_squared(cameraPosition - lhs.worldTransform.columns.3.xyz)
                    let rhsDistance = simd_length_squared(cameraPosition - rhs.worldTransform.columns.3.xyz)
                    return lhsDistance < rhsDistance
                })
                // Filter the candidate plane intersections by distance, accepting the nearest one that's not
                // "too close for comfort" according to an empirically chosen distance
                let closestPlaneHit = sortedPlaneHits.first { result in
                    let eyeDistance = simd_length_squared(cameraPosition - result.worldTransform.columns.3.xyz)
                    return eyeDistance > minimumInitialPlacementDistance
                }
                // If we found a viable candidate, go ahead and anchor there
                if let closestPlaneHit {
                    if let planeAnchor = closestPlaneHit.anchor as? ARPlaneAnchor {
                        let hitPoint = closestPlaneHit.worldTransform.columns.3.xyz
                        attachToPlaneAnchor(planeAnchor, at: hitPoint)
                    }
                }
            }
        }
        rotationDelta = 0
        scaleFactorDelta = 1.0
    }

    private func attachToPlaneAnchor(_ newPlaneAnchor: ARPlaneAnchor, at point: simd_float3) {
        //playHapticTap()

        if assetContainerNode.parent != arSceneView.scene.rootNode {
            // Move from being attached to the camera to being attached to the world
            arSceneView.scene.rootNode.addChildNode(assetContainerNode)
            assetContainerNode.pivot = SCNMatrix4Identity
        }

        // If we're not currently anchored, try to choose an asset scale that honors the asset's
        // native size while not allowing it to be enormous. The user can always scale it up as needed.
        if worldAnchorPoint == nil {
            cumulativeScale = preferredSceneScale(forMaximumWorldSpaceSize: 1.5 /* meters */).y
        }

        if currentPlaneAnchor?.alignment != newPlaneAnchor.alignment {
            // Only permit rotation about the plane normal, resetting when moving between planes of differing alignment
            cumulativeRotation = 0.0
        }

        if let _ = arSceneView.node(for: newPlaneAnchor) {
            currentPlaneAnchor = newPlaneAnchor
        }

        self.worldAnchorPoint = SCNVector3(point)
    }

    private func updateSceneTransform() {
        guard let worldAnchorPoint = worldAnchorPoint else { return
        }
        // bounds of asset in local space
        let (minPoint, maxPoint) = assetContainerNode.boundingBox

        let uniformScale = cumulativeScale

        let midX = (minPoint.x + maxPoint.x) * 0.5
        let midY = (minPoint.y + maxPoint.y) * 0.5
        let midZ = (minPoint.z + maxPoint.z) * 0.5

        var worldTransform = matrix_identity_float4x4

        switch currentPlaneAnchor?.alignment {
        case .horizontal:
            worldTransform = simd_float4x4(translation: simd_float3(-midX, -minPoint.y, -midZ)) * worldTransform
            worldTransform = simd_float4x4(uniformScale: uniformScale) * worldTransform
            worldTransform = simd_float4x4(rotationAbout: simd_float3(0, 1, 0), by: cumulativeRotation) * worldTransform
        case .vertical:
            worldTransform = simd_float4x4(translation: simd_float3(-midX, -midY, -minPoint.z)) * worldTransform
            worldTransform = simd_float4x4(uniformScale: uniformScale) * worldTransform
            worldTransform = simd_float4x4(rotationAbout: simd_float3(0, 0, 1), by: cumulativeRotation) * worldTransform
            break
        default:
            break
        }

        if let anchorTransform = currentPlaneAnchor?.transform {
            if currentPlaneAnchor?.alignment == .vertical {
                worldTransform = simd_float4x4(rotationAbout: simd_float3(1, 0, 0), by: -.pi / 2) * worldTransform
            }

            let anchorOrientation = simd_float4x4(anchorTransform.upperLeft3x3)
            worldTransform = anchorOrientation * worldTransform
        }

        worldTransform = simd_float4x4(translation: simd_float3(worldAnchorPoint)) * worldTransform

        SCNTransaction.begin()
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .linear)
        SCNTransaction.animationDuration = 0.050
        assetContainerNode.simdWorldTransform = worldTransform
        SCNTransaction.commit()
    }

    @objc func longPressDidRecognize(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            dragTouchLocation = gesture.location(in: arSceneView)
            let hitTestOptions: [SCNHitTestOption : Any] = [.rootNode : assetContainerNode!,
                                                            .searchMode : SCNHitTestSearchMode.any.rawValue]
            let touchHits = arSceneView.hitTest(dragTouchLocation, options: hitTestOptions)
            dragGestureIsActive = (touchHits.count > 0)
        case .changed:
            if dragGestureIsActive {
                dragTouchLocation = gesture.location(in: arSceneView)
            }
        case .ended:
            dragGestureIsActive = false
        default:
            break
        }
    }

    @objc func rotateDidRecognize(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .began:
            rotationDelta += Float(gesture.rotation) * -1.0
            gesture.rotation = 0
        case .changed:
            rotationDelta += Float(gesture.rotation) * -1.0
            gesture.rotation = 0
        default:
            rotationDelta = 0
        }
    }

    @objc func panDidRecognize(_ gesture: UIPanGestureRecognizer) {
        // TODO: Enable two-finger panning rather than just one-finger dragging
        /*
        switch gesture.state {
        case .began:
            // Verify that the centroid of the touches is over the model before allowing panning
            let hitTestOptions: [SCNHitTestOption : Any] = [.rootNode : assetContainerNode!,
                                                            .searchMode : SCNHitTestSearchMode.any.rawValue]
            let touchHits = arSceneView.hitTest(dragTouchLocation, options: hitTestOptions)
            panGestureIsActive = (touchHits.count > 0)
            if panGestureIsActive {
                dragTouchLocation = gesture.location(in: arSceneView)
                log.info("Pan gesture did begin")
            }
        case .changed:
            dragTouchLocation = gesture.location(in: arSceneView)
        default:
            panGestureIsActive = false
        }*/
    }

    @objc func zoomDidRecognize(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            gesture.scale = 1.0
        case .changed:
            scaleFactorDelta = Float(gesture.scale)
            gesture.scale = 1.0
            break
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
    {
        let candidates = Set([gestureRecognizer, otherGestureRecognizer])
        let eligibleRecognizers = Set([rotationGesture, panGesture, zoomGesture])
        // Any two of: rotation, pan, and zoom can recognize simultaneously with one another.
        if (eligibleRecognizers.intersection(candidates).count == 2) {
            return true
        }
        return false
    }

    // MARK: - AR Session Management

    private func startARSession() {
        log.info("Starting ARKit session")
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .none
        arSceneView.session.run(configuration, options: [])
        arSessionIsRunning = true
    }

    private func pauseARSession() {
        if arSessionIsRunning {
            log.info("Pausing ARKit session")
            arSceneView.session.pause()
            arSessionIsRunning = false
        }
    }

    private var planeNodes = [UUID : SCNNode]()

    private func didAddPlaneAnchors(_ anchors: [ARPlaneAnchor]) {
    }

    private func didUpdatePlaneAnchors(_ anchors: [ARPlaneAnchor]) {
        for anchor in anchors {
            if let planeNode = planeNodes[anchor.identifier] {
                let planeGeometry = planeNode.geometry as? ARSCNPlaneGeometry
                planeGeometry?.update(from: anchor.geometry)
            }
        }
    }

    private func didRemovePlaneAnchors(_ anchors: [ARPlaneAnchor]) {
        for anchor in anchors {
            if anchor == currentPlaneAnchor {
                log.info("Anchor we were attached to went away. Will resume search for another plane...")
                currentPlaneAnchor = nil
            }
            if let _ = planeNodes[anchor.identifier] {
                planeNodes[anchor.identifier] = nil
            }
        }
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didFailWithError error: Error) {
        arSessionIsRunning = false
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
    }

    func sessionWasInterrupted(_ session: ARSession) {
        arSessionIsRunning = false
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        arSessionIsRunning = true
    }

    private func preferredSceneScale(forMaximumWorldSpaceSize maxSize: Float = 0.3) -> SCNVector3 {
        let preferredMaxSize: Float = maxSize
        let (minPoint, maxPoint) = assetContainerNode.boundingBox
        let simdMinPoint = simd_float3(minPoint), simdMaxPoint = simd_float3(maxPoint)
        let size = simdMaxPoint - simdMinPoint
        let maxDim = max(size.x, max(size.y, size.z))
        let scale = (maxDim > preferredMaxSize) ? (preferredMaxSize / maxDim) : 1.0
        return SCNVector3(scale, scale, scale)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if assetContainerNode.isHidden {
            assetContainerNode.isHidden = false
            //let targetScale = preferredSceneScale().x
            //let tinyScale = 1e-4 * targetScale
            //assetContainerNode.scale = SCNVector3(tinyScale, tinyScale, tinyScale)
            //assetContainerNode.runAction(SCNAction.scale(to: CGFloat(targetScale), duration: 0.3)) {
            //    self.log.info("Did finish scaling from tiny to default user scale after Obj->AR transition")
            //}
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let planeAnchors = anchors.compactMap { $0 as? ARPlaneAnchor }
        if planeAnchors.count > 0 {
            didAddPlaneAnchors(planeAnchors)
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        let planeAnchors = anchors.compactMap { $0 as? ARPlaneAnchor }
        if planeAnchors.count > 0 {
            didUpdatePlaneAnchors(planeAnchors)
        }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let planeAnchors = anchors.compactMap { $0 as? ARPlaneAnchor }
        if planeAnchors.count > 0 {
            didRemovePlaneAnchors(planeAnchors)
        }
    }

    // MARK: - SCNARViewDelegate

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            // Check the plane node cache for an existing node for this plane
            var planeNode = planeNodes[planeAnchor.identifier]
            if planeNode == nil {
                // Cache miss. Create a node for this plane, give it an initial geometry,
                // and make it able to receive (but not cast) shadows.
                let node = SCNNode()
                node.name = "Plane"
                node.geometry = ARSCNPlaneGeometry(device: device)
                node.geometry?.firstMaterial?.colorBufferWriteMask = [ .alpha ]
                node.castsShadow = false
                planeNode = node
                planeNodes[planeAnchor.identifier] = node
            }
            return planeNode
        } else {
            return nil
        }
    }

    // MARK: - SCNSceneRendererDelegate

    func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
        guard let _ = arSceneView else { return }
        DispatchQueue.main.async {
            self.updateARGestures()
        }
    }

    // MARK: - Haptics

    var lastHapticPlaybackTime = CACurrentMediaTime()
    let hapticPlaybackLockout = 0.500

    private func prepareHaptics() {
        do {
            hapticEngine = try CHHapticEngine()
            hapticEngine?.start(completionHandler: { maybeError in
                if maybeError == nil {
                    self.hapticsReady = true
                    DispatchQueue.main.async {
                        self.prepareHapticPatterns()
                    }
                }
            })
        } catch {
            log.warning("Failed to prepare haptic engine for playback")
        }
    }

    private func prepareHapticPatterns() {
        guard let engine = hapticEngine else { return }

        do {
            let eventProps: [CHHapticPattern.Key : Any] = [
                .eventType: CHHapticEvent.EventType.hapticTransient,
                .time: CHHapticTimeImmediate,
                .eventDuration: 0.2
            ]
            let patternEvents: [[CHHapticPattern.Key : Any]] = [ [ .event: eventProps ] ]
            let patternProps: [CHHapticPattern.Key : Any] = [ .pattern: patternEvents ]
            let pattern = try CHHapticPattern(dictionary: patternProps)
            hapticTapPlayer = try engine.makePlayer(with: pattern)
        } catch {
            log.error("Failed to create haptic pattern player")
        }
    }

    private func playHapticTap() {
        let now = CACurrentMediaTime()
        if (now < (lastHapticPlaybackTime + hapticPlaybackLockout)) {
            return // Too soon to restart playback
        }
        do {
            try hapticTapPlayer?.start(atTime: CHHapticTimeImmediate)
        } catch {
            return
        }
        lastHapticPlaybackTime = now
    }

    // MARK: - UIDocumentPickerDelegate

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        currentlyPresentedViewController = nil
        if let selectedURL = urls.first {
            if let assetDirectory, assetDirectory.path.hasPrefix(selectedURL.path) || (assetURL == selectedURL) {
                self.assetDirectory = selectedURL
                loadAsset()
            } else {
                log.notice("User did not select a directory containing the asset; skipping reload attempt")
                // TODO: Present permissions error atop object view and dismiss spinner
            }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        currentlyPresentedViewController = nil
        // TODO: Present permissions error atop object view and dismiss spinner
    }
}
