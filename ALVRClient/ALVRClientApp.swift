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
    
    class Coordinator : NSObject, MTKViewDelegate, EventHandlerDelegate {
        static let deviceIdHead = alvr_path_string_to_id("/user/head")
        
        private var parent: MetalView
        private let renderer: Renderer
        
        init(_ parent: MetalView) {
            self.parent = parent
            
            guard let metalDevice = MTLCreateSystemDefaultDevice() else { fatalError("Can't create metal device.") }
            
            renderer = Renderer(metalDevice: metalDevice)
            Renderer.shared = renderer;
            super.init()
            
            EventHandler.shared.delegate = self
        }
        
        func updateStreamingState(isStarted: Bool) {
            renderer.updateStreamingState(isStarted: isStarted)
        }
        
        func createDecoder() {
            renderer.createDecoder()
        }
        
        func updateFrame() {
            renderer.updateFrame()
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            EventHandler.shared.initialize(size: size)
        }
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor else {
                return
            }
            
            if EventHandler.shared.alvrInitialized {
                renderer.draw(drawable: drawable, renderPassDescriptor: renderPassDescriptor)
            }
            
            // Exec in separated thread
            let thread = Thread {// [weak self] in
                EventHandler.shared.pollEvents()
            }
            thread.name = "Poll Events Thread"
            thread.start()
        }
        
    }
    
    func makeUIView(context: Context) -> MTKView {
        return makeMTKView(context)
    }
        
    func updateUIView(_ nsView: MTKView, context: Context) { }
}
