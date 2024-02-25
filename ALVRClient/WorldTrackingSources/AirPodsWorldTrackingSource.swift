//
//  AirPodsWorldTrackingSource.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 25.02.2024.
//

import CoreMotion

// FIXME: Flipped two axis
class AirPodsWorldTrackingSource: NSObject, WorldTrackingSource {
    // private let dispatchQueue: DispatchQueue
    private let operationQueue: OperationQueue
    private let motionManager: CMHeadphoneMotionManager
    
    private var position: (Float, Float, Float) = (0.0, 0.0, 0.0)
    private var rotation: (Float, Float, Float) = (0.0, 0.0, 0.0)
    
    override init() {
        // dispatchQueue = DispatchQueue(label: "MotionWorldTrackingSource DispatchQueue", qos: .background)
        operationQueue = .init()
        operationQueue.name = "MotionWorldTrackingSource OperationQueue"
        operationQueue.qualityOfService = .background
        
        motionManager = CMHeadphoneMotionManager()
        // motionManager.deviceMotionUpdateInterval = 1.0 / 30.0 // 30 tps
        
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
            
            // Motion don't support position tracking
            self.position = (0, 1.6, 0)
            
            let q = motion.attitude.quaternion
            
            // roll (x-axis rotation)
            let sinr_cosp = 2 * (q.w * q.x + q.y * q.z);
            let cosr_cosp = 1 - 2 * (q.x * q.x + q.y * q.y);
            let roll = Float(atan2(sinr_cosp, cosr_cosp))

            // pitch (y-axis rotation)
            let sinp = sqrt(1 + 2 * (q.w * q.y - q.x * q.z));
            let cosp = sqrt(1 - 2 * (q.w * q.y - q.x * q.z));
            let pitch = Float(2 * atan2(sinp, cosp) - Double.pi / 2)

            // yaw (z-axis rotation)
            let siny_cosp = 2 * (q.w * q.z + q.x * q.y);
            let cosy_cosp = 1 - 2 * (q.y * q.y + q.z * q.z);
            let yaw = Float(atan2(siny_cosp, cosy_cosp))
            
            self.rotation = (roll, pitch, yaw)
        }
    }
    
    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
    
    func getPosition() -> (Float, Float, Float) {
        return position
    }
    
    func getRotation() -> (Float, Float, Float) {
        return rotation
    }
}
