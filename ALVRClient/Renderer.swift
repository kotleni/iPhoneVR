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

// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<UniformsArray>.size + 0xFF) & -0x100

let maxBuffersInFlight = 3

// Focal depth of the timewarp panel, ideally would be adjusted based on the depth
// of what the user is looking at.
let panel_depth: Float = 1

// TODO(zhuowei): what's the z supposed to be?
// x, y, z
// u, v
let fullscreenQuadVertices:[Float] = [-panel_depth, -panel_depth, -panel_depth,
                                       panel_depth, -panel_depth, -panel_depth,
                                       -panel_depth, panel_depth, -panel_depth,
                                       panel_depth, panel_depth, -panel_depth,
                                       0, 1,
                                       0.5, 1,
                                       0, 0,
                                       0.5, 0]

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
    
    let mtlVertexDescriptor: MTLVertexDescriptor
    
    var mesh: MTKMesh
    
    var uniformBufferOffset = 0

    var uniformBufferIndex = 0
    
    var dynamicUniformBuffer: MTLBuffer
    var uniforms: UnsafeMutablePointer<UniformsArray>
    
    var fullscreenQuadBuffer:MTLBuffer!
    
    init(metalDevice: MTLDevice) {
        guard let metalCommandQueue = metalDevice.makeCommandQueue() else { fatalError("Can't create command queue.") }
        
        self.metalDevice = metalDevice
        self.metalCommandQueue = metalCommandQueue
        
        let uniformBufferSize = alignedUniformsSize * maxBuffersInFlight
        
        self.dynamicUniformBuffer = metalDevice.makeBuffer(length:uniformBufferSize,
                                                                   options:[MTLResourceOptions.storageModeShared])!

        self.dynamicUniformBuffer.label = "UniformBuffer"

        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents()).bindMemory(to:UniformsArray.self, capacity:1)

        
        self.mtlVertexDescriptor = Renderer.buildMetalVertexDescriptor()
        
        do {
            mesh = try Renderer.buildMesh(device: metalDevice, mtlVertexDescriptor: mtlVertexDescriptor)
        } catch {
            fatalError("Unable to build MetalKit Mesh. Error info: \(error)")
        }
        
        if CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &metalTextureCache) != 0 {
            fatalError("CVMetalTextureCacheCreate")
        }
        
        fullscreenQuadVertices.withUnsafeBytes {
            fullscreenQuadBuffer = metalDevice.makeBuffer(bytes: $0.baseAddress!, length: $0.count)
        }
    }
    
    private func updateDynamicBufferState() {
        /// Update the state of our uniform buffers before rendering

        uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight

        uniformBufferOffset = alignedUniformsSize * uniformBufferIndex

        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents() + uniformBufferOffset).bindMemory(to:UniformsArray.self, capacity:1)
    }
    
    func draw(drawable: CAMetalDrawable, renderPassDescriptor: MTLRenderPassDescriptor) {
        self.updateDynamicBufferState()
        
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
            
//            commandBuffer.present(drawable)
//            commandBuffer.commit()
            
        }
    }
    
    func updateStreamingState(isStarted: Bool, foveationVars: FoveationVars?) {
        if isStarted {
            guard let foveationVars = foveationVars else { fatalError("foveationVars for isStarted = true can't be nil.") }
            videoFramePipelineState = try! Renderer.buildRenderPipelineWithDevice(device: metalDevice, foveationVars: foveationVars, mtlVertexDescriptor: mtlVertexDescriptor)
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
                }
            } else {
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
    
    private func updateGameStateForVideoFrame(framePose: simd_float4x4) {
            let simdDeviceAnchor = matrix_identity_float4x4
            
            func uniforms(forViewIndex viewIndex: Int) -> Uniforms {
                let tangentsForViews: [simd_float4] = [
                    simd_float4(3, 3, 3, 3),
                    simd_float4(6, 6, 6, 6)
                ]
                
                let tangents = tangentsForViews[viewIndex]
                let viewMatrix = (framePose.inverse * simdDeviceAnchor).inverse
                let projection = ProjectiveTransform3D(leftTangent: Double(tangents[0]),
                                                       rightTangent: Double(tangents[1]),
                                                       topTangent: Double(tangents[2]),
                                                       bottomTangent: Double(tangents[3]),
                                                       nearZ: Double(0.01),
                                                       farZ: Double(100.0),
                                                       reverseZ: true)
                return Uniforms(projectionMatrix: .init(projection), modelViewMatrix: viewMatrix, tangents: tangents)
            }
            
            self.uniforms[0].uniforms.0 = uniforms(forViewIndex: 0)
            self.uniforms[0].uniforms.1 = uniforms(forViewIndex: 1)
        }
    
    func renderStreamingFrameEye(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, drawable: CAMetalDrawable, queuedFrame: QueuedFrame, renderEncoder: MTLRenderCommandEncoder, eyeIndex: Int) {
        // Attach eye index to shader
        uniforms[0].eyeIndex = ushort(eyeIndex)
        
        renderEncoder.label = "Primary Render Encoder \(eyeIndex)"
        renderEncoder.pushDebugGroup("Draw Box \(eyeIndex)")
        renderEncoder.setCullMode(.back)
        renderEncoder.setFrontFacing(.counterClockwise)
        
        renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset: uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
        renderEncoder.setRenderPipelineState(videoFramePipelineState)
        
        let width: Double = Double(drawable.texture.width / 2)
        let height: Double = Double(drawable.texture.height)
        let viewports: [MTLViewport] = [
            .init(originX: 0, originY: 0, width: width, height: height, znear: 0.01, zfar: 100.0),
            .init(originX: width , originY: 0, width: width, height: height, znear: 0.01, zfar: 100.0)
        ]
        renderEncoder.setViewport(viewports[eyeIndex])
        
        // Cut another viewport
//        renderEncoder.setScissorRect(.init(x: Int(viewports[eyeIndex == 0 ? 0 : 1].originX), y: Int(viewports[eyeIndex].originY), width: Int(viewports[eyeIndex].width), height: Int(viewports[eyeIndex].height)))
        
        let pixelBuffer = queuedFrame.imageBuffer
        
        // TODO: optimization, prepare textures one time for each eyes
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
        
        renderEncoder.setVertexBuffer(fullscreenQuadBuffer, offset: 0, index: VertexAttribute.position.rawValue)
        renderEncoder.setVertexBuffer(fullscreenQuadBuffer, offset: (3*4)*4, index: VertexAttribute.texcoord.rawValue)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
        
        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()
    }
    
    func renderStreamingFrame(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, drawable: CAMetalDrawable, queuedFrame: QueuedFrame) {
        
        self.updateDynamicBufferState()
        // TODO: framePreviouslyPredictedPose
        self.updateGameStateForVideoFrame(framePose: matrix_identity_float4x4)
        
        // TODO: Optimize me, maybe we can put index value by another way?
        // TODO: And after do only one present/commit
        // Draw each eyes
        for i in 0...1 {
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                fatalError("Failed to create render encoder")
            }
            
            // Draw each eyes
            renderStreamingFrameEye(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer, drawable: drawable, queuedFrame: queuedFrame, renderEncoder: renderEncoder, eyeIndex: i)
            
            // Finish
            
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    /// Build a render state pipeline object
    private class func buildRenderPipelineWithDevice(device: MTLDevice, foveationVars: FoveationVars, mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
        let library = device.makeDefaultLibrary()

        let vertexFunction = library?.makeFunction(name: "videoFrameVertexShader")
        
        let fragmentConstants = FFR.makeFunctionConstants(foveationVars)
        let fragmentFunction = try library?.makeFunction(name: "videoFrameFragmentShader", constantValues: fragmentConstants)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "RenderPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = globalPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = .invalid
        
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    class func buildMetalVertexDescriptor() -> MTLVertexDescriptor {
            // Create a Metal vertex descriptor specifying how vertices will by laid out for input into our render
            //   pipeline and how we'll layout our Model IO vertices

            let mtlVertexDescriptor = MTLVertexDescriptor()

            mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].format = MTLVertexFormat.float3
            mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].offset = 0
            mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].bufferIndex = BufferIndex.meshPositions.rawValue

            mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].format = MTLVertexFormat.float2
            mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].offset = 0
            mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].bufferIndex = BufferIndex.meshGenerics.rawValue

            mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stride = 12
            mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepRate = 1
            mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepFunction = MTLVertexStepFunction.perVertex

            mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stride = 8
            mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepRate = 1
            mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepFunction = MTLVertexStepFunction.perVertex

            return mtlVertexDescriptor
        }
    
    class func buildMesh(device: MTLDevice,
                             mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTKMesh {
            /// Create and condition mesh data to feed into a pipeline using the given vertex descriptor

            let metalAllocator = MTKMeshBufferAllocator(device: device)

            let mdlMesh = MDLMesh.newBox(withDimensions: SIMD3<Float>(4, 4, 4),
                                         segments: SIMD3<UInt32>(2, 2, 2),
                                         geometryType: MDLGeometryType.triangles,
                                         inwardNormals:false,
                                         allocator: metalAllocator)

            let mdlVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(mtlVertexDescriptor)

            guard let attributes = mdlVertexDescriptor.attributes as? [MDLVertexAttribute] else {
                fatalError("?????: mdlVertexDescriptor.attributes as? [MDLVertexAttribute] else {")
                //throw RendererError.badVertexDescriptor
            }
            attributes[VertexAttribute.position.rawValue].name = MDLVertexAttributePosition
            attributes[VertexAttribute.texcoord.rawValue].name = MDLVertexAttributeTextureCoordinate

            mdlMesh.vertexDescriptor = mdlVertexDescriptor

            return try MTKMesh(mesh:mdlMesh, device:device)
        }
}
