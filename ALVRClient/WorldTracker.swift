//
//  WorldTracker.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 22.02.2024.
//

import ARKit
import CoreMotion

final class WorldTracker: NSObject, ARSessionDelegate {
    private let dispatchQueue: DispatchQueue
    private let configuration: ARWorldTrackingConfiguration
    private let arSession: ARSession
    
    #if DEBUG
    private var lastTickTime: Int64 = 0
    private var tps = 0
    #endif
    
    // FIXME: Monkey code
    private var position: (Float, Float, Float) = (Float.zero, Float.zero + 1.6, Float.zero)
    private var rotation: CMQuaternion = .init()
    
    private let isTrackOrientation: Bool
    private let isTrackPosition: Bool
    
    init(isTrackOrientation: Bool, isTrackPosition: Bool) {
        print("World tracking params: isTrackOrientation: \(isTrackOrientation), isTrackPosition: \(isTrackPosition)")
        
        self.isTrackOrientation = isTrackOrientation
        self.isTrackPosition = isTrackPosition
        
        dispatchQueue = .init(label: "ARWorldTrackingSource", qos: .background)
        
        configuration = .init()
        configuration.planeDetection = .horizontal
        
        arSession = ARSession()
        
        super.init()
        arSession.delegate = self
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if isTrackOrientation {
            if let frameEuler = arSession.currentFrame?.camera.eulerAngles {
                let r = frameEuler
                
                // Get quaternion components
                let cr = cos(r.x * 0.5)
                let sr = sin(r.x * 0.5)
                let cp = cos(r.y * 0.5)
                let sp = sin(r.y * 0.5)
                let cy = cos(r.z * 0.5)
                let sy = sin(r.z * 0.5)
                
                // Get quaternion values
                let w = (cr * cp * cy + sr * sp * sy)
                let x = (sr * cp * cy - cr * sp * sy)
                let y = (cr * sp * cy + sr * cp * sy)
                let z = (cr * cp * sy - sr * sp * cy)
                
                self.rotation = .init(x: Double(x), y: Double(y), z: Double(z), w: Double(w))
            }
        }
        
        if isTrackPosition {
            if let pos = arSession.currentFrame?.camera.transform.columns.3 {
                self.position = (pos.x, pos.y + 1.0, pos.z)
            }
        }
        
        #if DEBUG
        tps += 1
        if Int64.getCurrentMillis() - lastTickTime > 1000 {
            lastTickTime = Int64.getCurrentMillis()
            // print("World tracker tps is \(tps)")
            tps = 0
        }
        #endif
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
    
    /// Get device position
    func getPosition() -> (Float, Float, Float) {
        return position
    }
    
    /// Get device euler rotation
    func getRotation() -> CMQuaternion {
        return rotation
    }
    
    /// Get device quaterion rotation
    func getQuaterionRotation() -> AlvrQuat {
        let r = getRotation()
        
        return AlvrQuat.init(x: Float(r.x), y: Float(r.y), z: Float(r.z), w: Float(r.w))
    }
}
