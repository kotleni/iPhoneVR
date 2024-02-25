//
//  MainViewController.swift
//  HelloCardboard
//
//  Created by Viktor Varenik on 25.02.2024.
//

import UIKit
import GLKit
import MetalKit

class MainViewController: UIViewController, MainCardboardOverlayViewDelegate, MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        initAlvr(size: size)
    }
    
    func didTapTriggerButton() {
        print("didTapTriggerButton")
    }
    
    func presentingViewControllerForSettingsDialog() -> UIViewController? {
        fatalError("Not implemented yet.")
    }

    //var cardboardLensDistortion: CardboardLensDistortion?
//    var cardboardHeadTracker: CardboardHeadTracker?
    //var renderer: cardboard.hello_cardboard.HelloCardboardRenderer?
    var deviceParamsChangedCount: Int = -1
    
    static let deviceIdHead = alvr_path_string_to_id("/user/head")
    
    private var worldTracker: WorldTracker!
    private var alvrEvent: AlvrEvent = AlvrEvent()
    // private var parent: MetalView
    
    private var renderer: Renderer!
    
    private var alvrInitialized = false
    private var lastBatteryStateUpdateTime: Int64 = 0
    private var isRenderPaused = false

    deinit {
//        CardboardLensDistortion_destroy(cardboardLensDistortion)
//        CardboardHeadTracker_destroy(cardboardHeadTracker)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.worldTracker = WorldTracker(trackingMode: .coreMotion)
        
        guard let metalDevice = MTLCreateSystemDefaultDevice() else { fatalError("Can't create metal device.") }
        
        renderer = Renderer(metalDevice: metalDevice)
        
        let mtkView = MTKView()
        mtkView.delegate = self
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.preferredFramesPerSecond = 60
        mtkView.device = metalDevice
        mtkView.framebufferOnly = false
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.drawableSize = mtkView.frame.size
        mtkView.colorPixelFormat = globalPixelFormat
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false
        view = mtkView

        // Create an overlay view on top of the GLKView.
        let overlayView = MainCardboardOverlayView(frame: self.view.bounds)
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlayView.delegate = self
        self.view.addSubview(overlayView)

        // Add a tap gesture to handle viewer trigger action.
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapGLView(_:)))
        self.view.addGestureRecognizer(tapGesture)

        // Prevents screen to turn off.
        UIApplication.shared.isIdleTimerDisabled = true

        // Create cardboard head tracker.
//        cardboardHeadTracker = CardboardHeadTracker_create()
//        cardboardLensDistortion = nil

        // Set the counter to -1 to force a device params update.
        deviceParamsChangedCount = -1
    }
    
    func initAlvr(size: CGSize) {
        let refreshRates: [Float] = [60]
        let width = UInt32(size.width)
        let oneViewWidth = (width / 2)
        let height = UInt32(size.height)
        alvr_initialize(
            nil, nil,
            oneViewWidth, height,
            refreshRates, Int32(refreshRates.count),
            /* support foveated encoding */ false,
            /* external decoding */ true
        )
        alvr_resume()
        alvr_request_idr()
        
        print("alvr resume!")
    }
    
    
    // FIXME: Ipd and fov is invalid maybe
    private func sendFovConfigs() {
        if alvrInitialized {
            print("Send view config")
            let v: Float = 1.0
            let v2: Float = 1.0
            let leftAngles = atan(simd_float4(v, v, v, v))
            let rightAngles = atan(simd_float4(v2, v2, v2, v2))
            let leftFov = AlvrFov(left: -leftAngles.x, right: leftAngles.y, up: leftAngles.z, down: -leftAngles.w)
            let rightFov = AlvrFov(left: -rightAngles.x, right: rightAngles.y, up: rightAngles.z, down: -rightAngles.w)
            let fovs = [leftFov, rightFov]
            let ipd = Float(0.063)
            alvr_send_views_config(fovs, ipd)
        }
    }
    
    func parseMessage(_ message: String) {
        let lines = message.components(separatedBy: "\n")
        for line in lines {
            let keyValuePair = line.split(separator: ":")
            if keyValuePair.count == 2 {
                //let key = keyValuePair[0].trimmingCharacters(in: .whitespaces)
                //let value = keyValuePair[1].trimmingCharacters(in: .whitespaces)
//                        if key == "hostname" {
//                            updateHostname(value)
//                        } else if key == "IP" {
//                            updateIP(value)
//                        }
            }
        }
    }
    
    func draw(in view: MTKView) {
        if !updateDeviceParams() {
            return
        }
        
        if isRenderPaused {
            return
        }
        
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }
        
        if self.alvrInitialized {
            renderer.draw(drawable: drawable, renderPassDescriptor: renderPassDescriptor)
        }
        
        // Exec in separated thread
        let thread = Thread { [weak self] in
            self?.pollEvents()
        }
        thread.name = "Poll Events Thread"
        thread.start()
    }
    
    /// Poll all alvr events
    func pollEvents() {
        let res = alvr_poll_event(&alvrEvent)
        if res {
            // print(alvrEvent.tag)
            switch UInt32(alvrEvent.tag) {
            case ALVR_EVENT_HUD_MESSAGE_UPDATED.rawValue:
                print("hud message updated")
                let hudMessageBuffer = UnsafeMutableBufferPointer<CChar>.allocate(capacity: 1024)
                alvr_hud_message(hudMessageBuffer.baseAddress)
                
                let message = String(cString: hudMessageBuffer.baseAddress!, encoding: .utf8)!
                parseMessage(message)
                print(message)
                
                hudMessageBuffer.deallocate()
            case ALVR_EVENT_STREAMING_STARTED.rawValue:
                print("streaming started: \(alvrEvent.STREAMING_STARTED)")
                renderer.updateStreamingState(isStarted: true)
                
                alvr_request_idr()
                alvrInitialized = true
                sendFovConfigs()
            case ALVR_EVENT_STREAMING_STOPPED.rawValue:
                print("streaming stopped")
                alvrInitialized = false
                renderer.updateStreamingState(isStarted: false)
            case ALVR_EVENT_HAPTICS.rawValue:
                print("haptics: \(alvrEvent.HAPTICS)")
            case ALVR_EVENT_DECODER_CONFIG.rawValue:
                print("create decoder: \(alvrEvent.DECODER_CONFIG)")
                renderer.createDecoder()
            case ALVR_EVENT_FRAME_READY.rawValue:
                // print("frame ready")
                renderer.updateFrame()
                
                // YOLO?
                // Send new tracking
                let pose = AlvrPose(orientation: worldTracker.getQuaterionRotation(), position: worldTracker.getPosition())
                var trackingMotion = AlvrDeviceMotion(device_id: MetalView.Coordinator.deviceIdHead, pose: pose, linear_velocity: (0, 0, 0), angular_velocity: (0, 0, 0))
                let timestamp = mach_absolute_time()
                //print("sending tracking for timestamp \(timestamp)")
                alvr_send_tracking(timestamp, &trackingMotion, 1, nil, nil)
                
                // Send battery state every 30 secs
                if Int64.getCurrentMillis() - lastBatteryStateUpdateTime > 1000 * 30 {
                    lastBatteryStateUpdateTime = Int64.getCurrentMillis()
                    UIDevice.current.isBatteryMonitoringEnabled = true
                    print("Update battery state: \(UIDevice.current.batteryLevel) / 1.0 | Is charging: \(UIDevice.current.batteryState == .charging)")
                    alvr_send_battery(MainViewController.deviceIdHead, UIDevice.current.batteryLevel, UIDevice.current.batteryState == .charging)
                }
            default:
                print("what")
            }
        } else {
            usleep(10000)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if #available(iOS 11.0, *) {
            setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
        resumeCardboard()
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        // Cardboard only supports landscape right orientation for inserting the phone in the viewer.
        return .landscapeRight
    }

    func deviceParamsChanged() -> Bool {
        return deviceParamsChangedCount != CardboardQrCode_getDeviceParamsChangedCount()
    }

    func updateDeviceParams() -> Bool {
        // Check if device parameters have changed.
        guard !deviceParamsChanged() else {
            return true
        }

        var encodedDeviceParams: UnsafeMutablePointer<UInt8>?
        var size: Int32 = 0
        CardboardQrCode_getSavedDeviceParams(&encodedDeviceParams, &size)

        guard size > 0 else {
            print("Saved device params has 0 size.")
            return false
        }

        // Using native scale as we are rendering directly to the screen.
        let screenRect = self.view.bounds
        let screenScale = UIScreen.main.nativeScale
        var height = Int32(screenRect.size.height * screenScale)
        var width = Int32(screenRect.size.width * screenScale)

        // Rendering coordinates assume landscape orientation.
        if height > width {
            let temp = height
            height = width
            width = temp
        }

        // Create CardboardLensDistortion.
//        CardboardLensDistortion_destroy(cardboardLensDistortion)
//        cardboardLensDistortion = CardboardLensDistortion_create(encodedDeviceParams, size, width, height)

        // Initialize HelloCardboardRenderer.
//        renderer = cardboard.hello_cardboard.HelloCardboardRenderer(cardboardLensDistortion, cardboardHeadTracker, width, height)
//        renderer?.InitializeGl()

        CardboardQrCode_destroy(encodedDeviceParams)

        deviceParamsChangedCount = Int(CardboardQrCode_getDeviceParamsChangedCount())

        return true
    }

    func pauseCardboard() {
        isRenderPaused = true
        //CardboardHeadTracker_pause(cardboardHeadTracker)
    }

    func resumeCardboard() {
        var buffer: UnsafeMutablePointer<UInt8>?
        var size: Int32 = 0
        CardboardQrCode_getSavedDeviceParams(&buffer, &size)
        if size == 0 {
            print(size)
            switchViewer()
        }
        CardboardQrCode_destroy(buffer)

        //CardboardHeadTracker_resume(cardboardHeadTracker)
        isRenderPaused = false
    }

    func switchViewer() {
        CardboardQrCode_scanQrCodeAndSaveDeviceParams()
    }

    @objc func didTapGLView(_ sender: Any) {
        //renderer?.OnTriggerEvent()
    }

    func didTapBackButton() {
        // User pressed the back button. Pop this view controller.
        print("User pressed back button")
    }

    func didPresentSettingsDialog(_ presented: Bool) {
        // The overlay view is presenting the settings dialog. Pause our rendering while presented.
        isRenderPaused = presented
    }

    func didChangeViewerProfile() {
        pauseCardboard()
        switchViewer()
        resumeCardboard()
    }
}

