//
//  ARWorldTrackingSource.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 23.02.2024.
//

import ARKit

class ARWorldTrackingSource: NSObject, ARSessionDelegate, WorldTrackingSource {
    private let dispatchQueue: DispatchQueue
    private let configuration: ARWorldTrackingConfiguration // or AROrientationTrackingConfiguration
    private let arSession: ARSession
    // ARSession have very big impact for battery
    // Maybe i should use CoreMotion?
    // But ARSession can track position in space
    
    private var lastTickTime: Int64 = 0
    private var tps = 0
    
    // FIXME: Monkey code
    private var position: (Float, Float, Float) = (Float.zero, Float.zero, Float.zero)
    private var rotation: (Float, Float, Float) = (Float.zero, Float.zero, Float.zero)
    
    override init() {
        dispatchQueue = .init(label: "ARWorldTrackingSource", qos: .background)
        
        configuration = .init()
        configuration.planeDetection = .horizontal
        
        arSession = ARSession()
        
        super.init()
        
        arSession.delegate = self
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if let framePosition = arSession.currentFrame?.camera.transform.columns.3 {
            // FIXME: Need to calibrate y offset
            // One metter offset just matched for initial position on my desk
            position = (framePosition.x, framePosition.y + 1.0 /* 1 metter offset */, framePosition.z)
        }
        
        if let frameEuler = arSession.currentFrame?.camera.eulerAngles {
            rotation = (frameEuler.x, frameEuler.y, frameEuler.z)
        }
        
        tps += 1
        if Int64.getCurrentMillis() - lastTickTime > 1000 {
            lastTickTime = Int64.getCurrentMillis()
            // print("World tracker tps is \(tps)")
            tps = 0
        }
    }
    
    func start() {
        // Start ar session
        dispatchQueue.async { [weak self] in
            guard let self = self else { return }
            self.arSession.run(self.configuration)
        }
    }
    
    func stop() {
        arSession.pause()
    }
    
    func getPosition() -> (Float, Float, Float) {
        return position
    }
    
    func getRotation() -> (Float, Float, Float) {
        return rotation
    }
}
