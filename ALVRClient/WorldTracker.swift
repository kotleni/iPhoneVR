//
//  WorldTracker.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 22.02.2024.
//

import ARKit

final class WorldTracker: NSObject, ARSessionDelegate {
    private let configuration: ARWorldTrackingConfiguration // or AROrientationTrackingConfiguration
    private let arSession: ARSession
    
    private var linearVelocity: (Float, Float, Float) = (Float.zero, Float.zero, Float.zero)
    private var position: (Float, Float, Float) = (Float.zero, Float.zero, Float.zero)
    private var rotation: (Float, Float, Float) = (Float.zero, Float.zero, Float.zero)
    
    override init() {
        configuration = .init()
        configuration.planeDetection = .horizontal
        
        arSession = ARSession()
        
        super.init()
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.arSession.run(self!.configuration)
        }
        
        arSession.delegate = self
    }
    
    func getCurrentMillis() -> Int64 {
        return Int64(NSDate().timeIntervalSince1970 * 1000)
    }
    
    var lastTime: Int64 = 0
    var tps = 0
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // TODO: linearVelocity
        
        if let framePosition = arSession.currentFrame?.camera.transform.columns.3 {
            position = (framePosition.x, framePosition.y + 1.0 /* 1 metter offset */, framePosition.z)
        }
        
        if let frameEuler = arSession.currentFrame?.camera.eulerAngles {
            rotation = (frameEuler.x, frameEuler.y, frameEuler.z)
        }
        
        tps += 1
        if getCurrentMillis() - lastTime > 1000 {
            lastTime = getCurrentMillis()
            // print("World tracker tps is \(tps)")
            tps = 0
        }
    }
    
    /// Get device linear velocity
    func getLinearVelocity() -> (Float, Float, Float) {
        return linearVelocity
    }
    
    /// Get device position
    func getPosition() -> (Float, Float, Float) {
        return position
    }
    
    /// Get device euler rotation
    func getRotation() -> (Float, Float, Float) {
        return rotation
    }
    
    func getQuaterionRotation() -> AlvrQuat {
        let r = rotation
        
        let cr = cos(r.0 * 0.5)
        let sr = sin(r.0 * 0.5)
        let cp = cos(r.1 * 0.5)
        let sp = sin(r.1 * 0.5)
        let cy = cos(r.2 * 0.5)
        let sy = sin(r.2 * 0.5)

        let w = Float(cr * cp * cy + sr * sp * sy)
        let x = Float(sr * cp * cy - cr * sp * sy)
        let y = Float(cr * sp * cy + sr * cp * sy)
        let z = Float(cr * cp * sy - sr * sp * cy)
        
        return AlvrQuat.init(x: x, y: y, z: z, w: w)
    }
}
