//
//  WorldTracker.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 22.02.2024.
//

import ARKit

final class WorldTracker: NSObject, ARSessionDelegate {
    private let dispatchQueue: DispatchQueue
    private let configuration: ARWorldTrackingConfiguration // or AROrientationTrackingConfiguration
    private let arSession: ARSession
    // ARSession have very big impact for battery
    // Maybe i should use CoreMotion?
    // But ARSession can track position in space
    
    private var lastTickTime: Int64 = 0
    private var tps = 0
    
    // FIXME: Monkey code
    private var linearVelocity: (Float, Float, Float) = (Float.zero, Float.zero, Float.zero)
    private var position: (Float, Float, Float) = (Float.zero, Float.zero, Float.zero)
    private var rotation: (Float, Float, Float) = (Float.zero, Float.zero, Float.zero)
    
    override init() {
        dispatchQueue = .init(label: "WorldTrackerQueue", qos: .background)
        
        configuration = .init()
        configuration.planeDetection = .horizontal
        
        arSession = ARSession()
        
        super.init()
        
        // Start ar session
        dispatchQueue.async { [weak self] in
            guard let self = self else { return }
            self.arSession.run(self.configuration)
        }
        
        arSession.delegate = self
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // TODO: linearVelocity
        
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
    
    /// Get device quaterion rotation
    func getQuaterionRotation() -> AlvrQuat {
        let r = rotation
        
        // Get quaternion components
        let cr = cos(r.0 * 0.5)
        let sr = sin(r.0 * 0.5)
        let cp = cos(r.1 * 0.5)
        let sp = sin(r.1 * 0.5)
        let cy = cos(r.2 * 0.5)
        let sy = sin(r.2 * 0.5)

        // Get quaternion values
        let w = Float(cr * cp * cy + sr * sp * sy)
        let x = Float(sr * cp * cy - cr * sp * sy)
        let y = Float(cr * sp * cy + sr * cp * sy)
        let z = Float(cr * cp * sy - sr * sp * cy)
        
        return AlvrQuat.init(x: x, y: y, z: z, w: w)
    }
}
