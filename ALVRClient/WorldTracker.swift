//
//  WorldTracker.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 22.02.2024.
//

import ARKit
import CoreMotion

final class WorldTracker {
    enum WorldTrackingMode {
        case arSession
        case easyArSession
        case coreMotion
    }
    
    private let worldTrackingSource: WorldTrackingSource
    
    init(trackingMode: WorldTrackingMode) {
        print("World tracking mode: \(trackingMode)")
        
        let worldTrackingSource: WorldTrackingSource
        if trackingMode == .arSession {
            worldTrackingSource = ARWorldTrackingSource()
        } else if trackingMode == .easyArSession {
            worldTrackingSource = StupidARWorldTrackingSource()
        } else if trackingMode == .coreMotion {
            worldTrackingSource = MotionWorldTrackingSource()
        } else {
            fatalError("Do you miss processing new tracking mode?")
        }
        
        worldTrackingSource.start()
        
        self.worldTrackingSource = worldTrackingSource
    }
    
    /// Get device position
    func getPosition() -> (Float, Float, Float) {
        return worldTrackingSource.getPosition()
    }
    
    /// Get device euler rotation
    func getRotation() -> CMQuaternion {
        return worldTrackingSource.getRotation()
    }
    
    /// Get device quaterion rotation
    func getQuaterionRotation() -> AlvrQuat {
        let r = getRotation()
        
        return AlvrQuat.init(x: Float(r.x), y: Float(r.y), z: Float(r.z), w: Float(r.w))
    }
}
