//
//  WorldTracker.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 22.02.2024.
//

import ARKit

final class WorldTracker {
    enum WorldTrackingMode {
        case arSession
        case coreMotion // Not working yet
    }
    
    private let worldTrackingSource: WorldTrackingSource
    
    init(trackingMode: WorldTrackingMode) {
        print("World tracking mode: \(trackingMode)")
        
        let worldTrackingSource: WorldTrackingSource
        if trackingMode == .arSession {
            worldTrackingSource = ARWorldTrackingSource()
        } else if trackingMode == .coreMotion {
            worldTrackingSource = MotionWorldTrackingSource()
        } else {
            fatalError("Do you miss processing new tracking mode?")
        }
        
        worldTrackingSource.start()
        
        self.worldTrackingSource = worldTrackingSource
    }
    
    /// Get device linear velocity
    func getLinearVelocity() -> (Float, Float, Float) {
        return worldTrackingSource.getLinearVelocity()
    }
    
    /// Get device position
    func getPosition() -> (Float, Float, Float) {
        return worldTrackingSource.getPosition()
    }
    
    /// Get device euler rotation
    func getRotation() -> (Float, Float, Float) {
        return worldTrackingSource.getRotation()
    }
    
    /// Get device quaterion rotation
    func getQuaterionRotation() -> AlvrQuat {
        let r = getRotation()
        
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
