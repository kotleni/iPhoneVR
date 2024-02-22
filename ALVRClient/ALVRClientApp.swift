//
//  App.swift
//

import SwiftUI
import VideoToolbox
import MetalKit
import CoreMotion
import Spatial
import ARKit


// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<UniformsArray>.size + 0xFF) & -0x100

let maxBuffersInFlight = 3

enum RendererError: Error {
    case badVertexDescriptor
}

let globalPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

struct MetalView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeMTKView(_ context: MetalView.Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 45
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
        struct QueuedFrame {
            let imageBuffer: CVImageBuffer
            let timestamp: UInt64
        }
        
        private let worldTracker: WorldTracker
        
        static let deviceIdHead = alvr_path_string_to_id("/user/head")
        
        var frameQueueLock = NSObject()
        
        var frameQueue = [QueuedFrame]()
        var frameQueueLastTimestamp: UInt64 = 0
        var frameQueueLastImageBuffer: CVImageBuffer? = nil
        var lastQueuedFrame: QueuedFrame? = nil
        var lastRequestedTimestamp: UInt64 = 0
        var lastSubmittedTimestamp: UInt64 = 0
        
        var framesRendered: Int = 0
        var framesSinceLastIDR: Int = 0
        var framesSinceLastDecode: Int = 0
        
        var parent: MetalView
        var metalDevice: MTLDevice!
        var metalCommandQueue: MTLCommandQueue!
        
        var vtDecompressionSession: VTDecompressionSession? = nil
        var videoFormat: CMFormatDescription? = nil
        var alvrEvent: AlvrEvent = AlvrEvent()

        let inFlightSemaphore = DispatchSemaphore(value: 3)
        
        var deviceAnchorsLock = NSObject()
        var deviceAnchorsQueue = [UInt64]()
        var deviceAnchorsDictionary = [UInt64: simd_float4x4]()
        var metalTextureCache: CVMetalTextureCache!
        var videoFramePipelineState: MTLRenderPipelineState!
        var lastIpd: Float = -1
        
        private var alvrInitialized = false
        
        init(_ parent: MetalView) {
            self.worldTracker = WorldTracker()
            
            self.parent = parent
            if let metalDevice = MTLCreateSystemDefaultDevice() {
                self.metalDevice = metalDevice
            }
            self.metalCommandQueue = metalDevice.makeCommandQueue()!
            
            super.init()
            
            if CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &metalTextureCache) != 0 {
                fatalError("CVMetalTextureCacheCreate")
            }
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            let refreshRates: [Float] = [60]
            let width = UInt32(size.width)
            let oneViewWidth = (width / 2)
            let height = UInt32(size.height)
            alvr_initialize(nil, nil, oneViewWidth, height, refreshRates, Int32(refreshRates.count), true)
            alvr_resume()
            alvr_request_idr()
            
            print("alvr resume!")
        }
        
        func processFrame(imageBuffer: CVImageBuffer) {
            let timestamp = mach_absolute_time()
            
            objc_sync_enter(frameQueueLock)
            framesSinceLastDecode = 0
            if frameQueueLastTimestamp != timestamp
            {
                // TODO: For some reason, really low frame rates seem to decode the wrong image for a split second?
                // But for whatever reason this is fine at high FPS.
                // From what I've read online, the only way to know if an H264 frame has actually completed is if
                // the next frame is starting, so keep this around for now just in case.
                if frameQueueLastImageBuffer != nil {
                    frameQueue.append(QueuedFrame(imageBuffer: frameQueueLastImageBuffer!, timestamp: frameQueueLastTimestamp))
                    //frameQueue.append(QueuedFrame(imageBuffer: imageBuffer, timestamp: timestamp))
                }
                else {
                    frameQueue.append(QueuedFrame(imageBuffer: imageBuffer, timestamp: timestamp))
                }
                if frameQueue.count > 2 {
                    frameQueue.removeFirst()
                }
                
                //print("queue: \(frameQueueLastTimestamp) -> \(timestamp), \(test)")
                
                frameQueueLastTimestamp = timestamp
                frameQueueLastImageBuffer = imageBuffer
            }
            
            // Pull the very last imageBuffer for a given timestamp
            if frameQueueLastTimestamp == timestamp {
                 frameQueueLastImageBuffer = imageBuffer
            }
            
            objc_sync_exit(frameQueueLock)
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
 
        func renderStreamingFrame(view: MTKView, commandBuffer: MTLCommandBuffer, drawable: CAMetalDrawable, queuedFrame: QueuedFrame) {
            let renderPassDescriptor = view.currentRenderPassDescriptor!
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                fatalError("Failed to create render encoder")
            }
            
            renderEncoder.label = "Primary Render Encoder"
            renderEncoder.pushDebugGroup("Draw Box")
            renderEncoder.setRenderPipelineState(videoFramePipelineState)
            
            let pixelBuffer = queuedFrame.imageBuffer
            
            for i in 0...2 {
                var textureOut: CVMetalTexture! = nil
                var err: OSStatus = 0
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                if i == 0 {
                    err = CVMetalTextureCacheCreateTextureFromImage(
                        nil, metalTextureCache, pixelBuffer, nil, .r8Unorm,
                        width, height, 0, &textureOut);
                } else {
                    err = CVMetalTextureCacheCreateTextureFromImage(
                        nil, metalTextureCache, pixelBuffer, nil, .rg8Unorm,
                        width/2, height/2, 1, &textureOut);
                }
                if err != 0 {
                    fatalError("CVMetalTextureCacheCreateTextureFromImage \(err)")
                }
                guard let metalTexture = CVMetalTextureGetTexture(textureOut) else {
                    fatalError("CVMetalTextureCacheCreateTextureFromImage")
                }
                
                renderEncoder.setFragmentTexture(metalTexture, index: i)
            }
            
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
            renderEncoder.popDebugGroup()
            renderEncoder.endEncoding()
        }
        
        /// Build a render state pipeline object
        class func buildRenderPipelineWithDevice(device: MTLDevice) throws -> MTLRenderPipelineState {
            let library = device.makeDefaultLibrary()

            let vertexFunction = library?.makeFunction(name: "mapTexture")
            let fragmentFunction = library?.makeFunction(name: "displayTexture")

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.label = "RenderPipeline"
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = globalPixelFormat
            pipelineDescriptor.depthAttachmentPixelFormat = .invalid
                
            return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        }
        
        func parseMessage(_ message: String) {
            let lines = message.components(separatedBy: "\n")
            for line in lines {
                let keyValuePair = line.split(separator: ":")
                if keyValuePair.count == 2 {
                    let key = keyValuePair[0].trimmingCharacters(in: .whitespaces)
                    let value = keyValuePair[1].trimmingCharacters(in: .whitespaces)
//                        if key == "hostname" {
//                            updateHostname(value)
//                        } else if key == "IP" {
//                            updateIP(value)
//                        }
                }
            }
        }
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable else {
                return
            }
            
            let commandBuffer = metalCommandQueue.makeCommandBuffer()!
            
            framesRendered += 1
            
            var queuedFrame: QueuedFrame? = nil
            if true {
                let startPollTime = CACurrentMediaTime()
                while true {
                    sched_yield()
                    objc_sync_enter(frameQueueLock)
                    queuedFrame = frameQueue.count > 0 ? frameQueue.removeFirst() : nil
                    objc_sync_exit(frameQueueLock)
                    if queuedFrame != nil {
                        break
                    }
                    
                    // Recycle old frame with old timestamp/anchor (visionOS doesn't do timewarp for us?)
                    if lastQueuedFrame != nil {
                        queuedFrame = lastQueuedFrame
                        break
                    }
                    
                    if CACurrentMediaTime() - startPollTime > 0.002 {
                        break
                    }
                }
            }
            
            if queuedFrame != nil && lastSubmittedTimestamp != queuedFrame!.timestamp {
                alvr_report_compositor_start(queuedFrame!.timestamp)
            }
            
            if queuedFrame != nil {
                objc_sync_enter(frameQueueLock)
                framesSinceLastDecode += 1
                objc_sync_exit(frameQueueLock)
                
                let vsyncTime = 1.0 / 60
                let vsyncTimeNs = UInt64(vsyncTime * Double(NSEC_PER_SEC))
                // let framePreviouslyPredictedPose = queuedFrame != nil ? lookupDeviceAnchorFor(timestamp: queuedFrame!.timestamp) : nil
                
                let semaphore = inFlightSemaphore
                commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                    if self.alvrInitialized && queuedFrame != nil && self.lastSubmittedTimestamp != queuedFrame?.timestamp {
                        let currentTimeNs = UInt64(CACurrentMediaTime() * Double(NSEC_PER_SEC))
                        // print("Finished:", queuedFrame!.timestamp)
                        alvr_report_submit(queuedFrame!.timestamp, vsyncTimeNs &- currentTimeNs)
                        self.lastSubmittedTimestamp = queuedFrame!.timestamp
                    }
                    semaphore.signal()
                }
                
                renderStreamingFrame(view: view, commandBuffer: commandBuffer, drawable: drawable, queuedFrame: queuedFrame!)
                
                commandBuffer.present(drawable)
                commandBuffer.commit()
            }
            
            // MARK: Events
            
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
                    
                    // TODO: Foveation is nedded (? or not)
                   // let foveationVars = FFR.calculateFoveationVars(alvrEvent.STREAMING_STARTED)
//                    videoFramePipelineState = try! MainRenderer.buildRenderPipelineForVideoFrameWithDevice(
//                        device: view.device!,
//                        mtlVertexDescriptor: mtlVertexDescriptor,
//                        foveationVars: foveationVars
//                    )
                    videoFramePipelineState = try! Coordinator.buildRenderPipelineWithDevice(device: view.device!)
                    
//                    var trackingMotion = AlvrDeviceMotion(device_id: MetalView.Coordinator.deviceIdHead, orientation: AlvrQuat(x: 1, y: 0, z: 0, w: 0), position: (0, 0, 0), linear_velocity: (0, 0, 0), angular_velocity: (0, 0, 0))
//                    alvr_send_tracking(mach_absolute_time(), &trackingMotion, 1)
                    
                    alvr_request_idr()
                    framesSinceLastIDR = 0
                    framesSinceLastDecode = 0
                    alvrInitialized = true
                    lastIpd = 0.063 // Magic value
                    sendFovConfigs()
                    
                    // TODO: Do it every 30 secs
                    UIDevice.current.isBatteryMonitoringEnabled = true
                    alvr_send_battery(Coordinator.deviceIdHead, UIDevice.current.batteryLevel, UIDevice.current.batteryState == .charging)
                case ALVR_EVENT_STREAMING_STOPPED.rawValue:
                    print("streaming stopped")
                    vtDecompressionSession = nil
                    videoFormat = nil
                    lastRequestedTimestamp = 0
                    lastSubmittedTimestamp = 0
                    framesRendered = 0
                    framesSinceLastIDR = 0
                    framesSinceLastDecode = 0
                    alvrInitialized = false
                    lastIpd = -1
                case ALVR_EVENT_HAPTICS.rawValue:
                    print("haptics: \(alvrEvent.HAPTICS)")
                case ALVR_EVENT_CREATE_DECODER.rawValue:
                    print("create decoder: \(alvrEvent.CREATE_DECODER)")
                    
                    // Don't reinstantiate the decoder if it's already created.
                    // TODO: Switching from H264 -> HEVC at runtime?
                    if vtDecompressionSession != nil {
                        break
                    }
                    
                    while true {
                        guard let (nal, timestamp) = VideoHandler.pollNal() else {
                            fatalError("create decoder: failed to poll nal?!")
                            break
                        }
                        print(nal.count, timestamp)
                        NSLog("%@", nal as NSData)
                        let val = (nal[4] & 0x7E) >> 1
                        print("NAL type of \(val)")
                        if (nal[3] == 0x01 && nal[4] & 0x1f == H264_NAL_TYPE_SPS) || (nal[2] == 0x01 && nal[3] & 0x1f == H264_NAL_TYPE_SPS) {
                            // here we go!
                            (vtDecompressionSession, videoFormat) = VideoHandler.createVideoDecoder(initialNals: nal, codec: H264_NAL_TYPE_SPS)
                            break
                        } else if (nal[3] == 0x01 && (nal[4] & 0x7E) >> 1 == HEVC_NAL_TYPE_VPS) || (nal[2] == 0x01 && (nal[3] & 0x7E) >> 1 == HEVC_NAL_TYPE_VPS) {
                            // The NAL unit type is 32 (VPS)
                            (vtDecompressionSession, videoFormat) = VideoHandler.createVideoDecoder(initialNals: nal, codec: HEVC_NAL_TYPE_VPS)
                            break
                        }
                    }
                case ALVR_EVENT_FRAME_READY.rawValue:
                    // print("frame ready")
                    while true {
                        guard let (nal, timestamp) = VideoHandler.pollNal() else {
                            break
                        }
                        
                        framesSinceLastIDR += 1
                        
                        // Don't submit NALs for decoding if we have already decoded a later frame
                        objc_sync_enter(frameQueueLock)
                        if timestamp < frameQueueLastTimestamp {
//                            print("Skip:", timestamp, frameQueueLastTimestamp)
//                            objc_sync_exit(frameQueueLock)
//                            break
                        }
                        
                        // If we're receiving NALs timestamped from >400ms ago, stop decoding them
                        // to prevent a cascade of needless decoding lag
                        let ns_diff_from_last_req_ts = lastRequestedTimestamp > timestamp ? lastRequestedTimestamp &- timestamp : 0
                        let lagSpiked = (ns_diff_from_last_req_ts > 1000*1000*600 && framesSinceLastIDR > 90*2)
                        // TODO: adjustable framerate
                        // TODO: maybe also call this if we fail to decode for too long.
                        if lastRequestedTimestamp != 0 && (lagSpiked || framesSinceLastDecode > 90*2) {
                            objc_sync_exit(frameQueueLock)
                                                
                            print("Handle spike!", framesSinceLastDecode, framesSinceLastIDR, ns_diff_from_last_req_ts)
                                                
                            // We have to request an IDR to resume the video feed
                            VideoHandler.abandonAllPendingNals()
                            alvr_request_idr()
                            framesSinceLastIDR = 0
                            framesSinceLastDecode = 0
                                                
                            continue
                        }
                        objc_sync_exit(frameQueueLock)
                        
                        if let vtDecompressionSession = vtDecompressionSession {
                            VideoHandler.feedVideoIntoDecoder(decompressionSession: vtDecompressionSession, nals: nal, timestamp: timestamp, videoFormat: videoFormat!) { [weak self] imageBuffer in
                                guard let imageBuffer = imageBuffer else {
                                    return
                                }
                                
                                self?.processFrame(imageBuffer: imageBuffer)
                            }
                        } else {
                            // TODO(zhuowei): hax
                            // OR NOT? (kotleni)
                            alvr_report_frame_decoded(timestamp)
                            alvr_report_compositor_start(timestamp)
                            alvr_report_submit(timestamp, 0)
                        }
                    }
                    // YOLO?
                    var trackingMotion = AlvrDeviceMotion(device_id: MetalView.Coordinator.deviceIdHead, orientation: worldTracker.getQuaterionRotation(), position: worldTracker.getPosition(), linear_velocity: worldTracker.getLinearVelocity(), angular_velocity: (0, 0, 0))
                    let timestamp = mach_absolute_time()
                    //print("sending tracking for timestamp \(timestamp)")
                    alvr_send_tracking(timestamp, &trackingMotion, 1)
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
