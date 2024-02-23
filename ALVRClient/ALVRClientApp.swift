//
//  App.swift
//

import SwiftUI
import VideoToolbox
import MetalKit
import CoreMotion
import Spatial
import ARKit

struct MetalView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeMTKView(_ context: MetalView.Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            mtkView.device = metalDevice
        }
        mtkView.framebufferOnly = false
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.drawableSize = mtkView.frame.size
        mtkView.colorPixelFormat = globalPixelFormat
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false
        return mtkView
    }
    
    class Coordinator : NSObject, MTKViewDelegate {
        static let deviceIdHead = alvr_path_string_to_id("/user/head")
        
        private let worldTracker: WorldTracker
        private var alvrEvent: AlvrEvent = AlvrEvent()
        private var parent: MetalView
        
        private let renderer: Renderer
        
        private var alvrInitialized = false
        private var lastBatteryStateUpdateTime: Int64 = 0
        
        init(_ parent: MetalView) {
            self.worldTracker = WorldTracker(trackingMode: .arSession)
            self.parent = parent
            
            guard let metalDevice = MTLCreateSystemDefaultDevice() else { fatalError("Can't create metal device.") }
            
            renderer = Renderer(metalDevice: metalDevice)
            
            super.init()
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
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
                    var trackingMotion = AlvrDeviceMotion(device_id: MetalView.Coordinator.deviceIdHead, pose: pose, linear_velocity: worldTracker.getLinearVelocity(), angular_velocity: (0, 0, 0))
                    let timestamp = mach_absolute_time()
                    //print("sending tracking for timestamp \(timestamp)")
                    alvr_send_tracking(timestamp, &trackingMotion, 1, nil, nil)
                    
                    // Send battery state every 30 secs
                    if Int64.getCurrentMillis() - lastBatteryStateUpdateTime > 1000 * 30 {
                        lastBatteryStateUpdateTime = Int64.getCurrentMillis()
                        UIDevice.current.isBatteryMonitoringEnabled = true
                        print("Update battery state: \(UIDevice.current.batteryLevel) / 1.0 | Is charging: \(UIDevice.current.batteryState == .charging)")
                        alvr_send_battery(Coordinator.deviceIdHead, UIDevice.current.batteryLevel, UIDevice.current.batteryState == .charging)
                    }
                default:
                    print("what")
                }
            } else {
                usleep(10000)
            }
        }
    }
    
    func makeUIView(context: Context) -> MTKView {
        return makeMTKView(context)
    }
        
    func updateUIView(_ nsView: MTKView, context: Context) { }
}
