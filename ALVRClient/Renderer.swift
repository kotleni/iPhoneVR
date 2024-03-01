//
//  Renderer.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 23.02.2024.
//

import SwiftUI
import VideoToolbox
import MetalKit
import CoreMotion
import Spatial
import ARKit

// TODO: Move to inside Renderer
let globalPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

final class Renderer {
    struct QueuedFrame {
        let imageBuffer: CVImageBuffer
        let timestamp: UInt64
    }
    
    private let metalDevice: MTLDevice
    private let metalCommandQueue: MTLCommandQueue
    
    let inFlightSemaphore = DispatchSemaphore(value: 3)
    
    var deviceAnchorsLock = NSObject()
    var deviceAnchorsQueue = [UInt64]()
    var deviceAnchorsDictionary = [UInt64: simd_float4x4]()
    var metalTextureCache: CVMetalTextureCache!
    var videoFramePipelineState: MTLRenderPipelineState!
    var lastIpd: Float = -1
    
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
    
    var vtDecompressionSession: VTDecompressionSession? = nil
    var videoFormat: CMFormatDescription? = nil
    
    var lastFps: Int = 0
    var currentFps: Int = 0
    var lastFpsUpdateTime: Int64 = 0
    
    init(metalDevice: MTLDevice) {
        guard let metalCommandQueue = metalDevice.makeCommandQueue() else { fatalError("Can't create command queue.") }
        
        self.metalDevice = metalDevice
        self.metalCommandQueue = metalCommandQueue
        
        if CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &metalTextureCache) != 0 {
            fatalError("CVMetalTextureCacheCreate")
        }
    }
    
    func draw(drawable: CAMetalDrawable, renderPassDescriptor: MTLRenderPassDescriptor) {
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
                if queuedFrame != nil && self.lastSubmittedTimestamp != queuedFrame?.timestamp {
                    let currentTimeNs = UInt64(CACurrentMediaTime() * Double(NSEC_PER_SEC))
                    // print("Finished:", queuedFrame!.timestamp)
                    alvr_report_submit(queuedFrame!.timestamp, vsyncTimeNs &- currentTimeNs)
                    self.lastSubmittedTimestamp = queuedFrame!.timestamp
                }
                semaphore.signal()
            }
            
            renderStreamingFrame(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer, drawable: drawable, queuedFrame: queuedFrame!)
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
    
    func updateStreamingState(isStarted: Bool) {
        if isStarted {
            videoFramePipelineState = try! Renderer.buildRenderPipelineWithDevice(device: metalDevice)
            framesSinceLastIDR = 0
            framesSinceLastDecode = 0
            
            lastIpd = 0.063 // What is it
        } else {
            vtDecompressionSession = nil
            videoFormat = nil
            lastRequestedTimestamp = 0
            lastSubmittedTimestamp = 0
            framesRendered = 0
            framesSinceLastIDR = 0
            framesSinceLastDecode = 0
            
            lastIpd = -1
        }
    }
    
    func createDecoder() {
        // Don't reinstantiate the decoder if it's already created.
        // TODO: Switching from H264 -> HEVC at runtime?
        if vtDecompressionSession != nil {
            return 
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
    }
    
    func updateFrameStats() {
        if Int64.getCurrentMillis() - lastFpsUpdateTime > 1000 {
            lastFpsUpdateTime = Int64.getCurrentMillis()
            
            lastFps = currentFps
            currentFps = 0
            
            print("FPS: \(lastFps)")
        }
        
        currentFps += 1
    }
    
    func updateFrame() {
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
                    self?.updateFrameStats()
                }
            } else {
                print("WARN: vtDecompressionSession is nil!")
                // TODO(zhuowei): hax
                // OR NOT? (kotleni)
                alvr_report_frame_decoded(timestamp)
                alvr_report_compositor_start(timestamp)
                alvr_report_submit(timestamp, 0)
            }
        }
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
    
    func renderStreamingFrame(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, drawable: CAMetalDrawable, queuedFrame: QueuedFrame) {
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            fatalError("Failed to create render encoder")
        }
        
        renderEncoder.label = "Primary Render Encoder"
        renderEncoder.pushDebugGroup("Draw Box")
        renderEncoder.setRenderPipelineState(videoFramePipelineState)
        
        let pixelBuffer = queuedFrame.imageBuffer
        
        for i in 0...1 {
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
    private class func buildRenderPipelineWithDevice(device: MTLDevice) throws -> MTLRenderPipelineState {
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
}
