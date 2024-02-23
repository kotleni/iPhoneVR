//
//  MotionWorldTrackingSource.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 23.02.2024.
//

import CoreMotion

// FIXME: Not working yet!
class MotionWorldTrackingSource: NSObject, WorldTrackingSource {
    private let dispatchQueue: DispatchQueue
    private let motionManager: CMMotionManager
    
    private var lastTickTime: Int64 = 0
    private var tps = 0
    
    // FIXME: Monkey code
    private var linearVelocity: (Float, Float, Float) = (Float.zero, Float.zero, Float.zero)
    private var position: (Float, Float, Float) = (Float.zero, Float.zero, Float.zero)
    private var rotation: (Float, Float, Float) = (Float.zero, Float.zero, Float.zero)
    
    override init() {
        dispatchQueue = .init(label: "ARWorldTrackingSource", qos: .background)
        
        motionManager = .init()
        motionManager.deviceMotionUpdateInterval = 1000 / 30 // 30 tps
        
        super.init()
    }
    
    func start() {
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            if error != nil { return }
            guard let self = self else { return }
            guard let motion = motion else { return }
            
            let attitude = motion.attitude
            rotation = (Float(attitude.roll), Float(attitude.pitch), Float(attitude.yaw))
            
            position.2 = 1.7
        }
    }
    
    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
    
    func getLinearVelocity() -> (Float, Float, Float) {
        return linearVelocity
    }
    
    func getPosition() -> (Float, Float, Float) {
        return position
    }
    
    func getRotation() -> (Float, Float, Float) {
        return rotation
    }
}
