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
    
    private var linearVelocity: (Float, Float, Float) = (0.0, 0.0, 0.0)
    private var position: (Float, Float, Float) = (0.0, 0.0, 0.0)
    private var rotation: (Float, Float, Float) = (0.0, 0.0, 0.0)
    
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
        guard motionManager.isDeviceMotionAvailable else {
            // TODO: Handle the case where device motion is not available
            print("Device motion is not available.")
            return
        }
    
        motionManager.startDeviceMotionUpdates(to: operationQueue) { [weak self] (motion, error) in
            guard let self = self, let motion = motion else {
                return
            }
            
            // FIXME: Not working
            // self.linearVelocity = (Float(motion.gravity.y), Float(motion.userAcceleration.z), Float(motion.userAcceleration.z))
            self.position = (0, 1.1, 0)
            //self.rotation = (Float(motion.rotationRate.x), Float(motion.rotationRate.y), Float(motion.rotationRate.z))
            
            self.rotation.0 = Float(motion.userAcceleration.x)
            self.rotation.1 = Float(motion.userAcceleration.y)
            self.rotation.2 = Float(motion.userAcceleration.z)
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
