//
//  MotionWorldTrackingSource.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 23.02.2024.
//

import CoreMotion

// FIXME: Not working yet!
class MotionWorldTrackingSource: NSObject, WorldTrackingSource {
    // private let dispatchQueue: DispatchQueue
    private let operationQueue: OperationQueue
    private let motionManager: CMMotionManager
    
    private var position: (Float, Float, Float) = (0.0, 0.0, 0.0)
    private var rotation: CMQuaternion = .init()
    
    override init() {
        // dispatchQueue = DispatchQueue(label: "MotionWorldTrackingSource DispatchQueue", qos: .background)
        operationQueue = .init()
        operationQueue.name = "MotionWorldTrackingSource OperationQueue"
        operationQueue.qualityOfService = .background
        
        motionManager = CMMotionManager()
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0 // 30 tps
        
        super.init()
    }
    
    func start() {
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: operationQueue) { [weak self] (motion, error) in
            guard let self = self, let motion = motion else {
                return
            }
            
            // FIXME: Not working
            self.position = (0, 1.6, 0)
            
            let sensorToDisplayRotation = CMQuaternion(x: 0.0, y: 0.0, z: -0.7071067811865476, w: 0.7071067811865476)
            let a = CMQuaternion(x: 0.0, y: 0.0, z: -0.7071067811865476, w: 0.7071067811865476)
            let b = CMQuaternion(x: 0.0, y: 0.7071067811865476, z: 0.0, w: 0.7071067811865476)
            self.rotation = sensorToDisplayRotation * motion.attitude.quaternion * a * b

        }
    }
    
    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
    
    func getPosition() -> (Float, Float, Float) {
        return position
    }
    
    func getRotation() -> CMQuaternion {
        return rotation
    }
}
