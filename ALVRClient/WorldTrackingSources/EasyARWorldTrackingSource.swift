//
//  StupidARWorldTrackingSource.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 26.02.2024.
//

import CoreMotion
import ARKit

class EasyARWorldTrackingSource: NSObject, ARSessionDelegate, WorldTrackingSource {
    private let dispatchQueue: DispatchQueue
    private let configuration: AROrientationTrackingConfiguration
    private let arSession: ARSession
    
    private var lastTickTime: Int64 = 0
    private var tps = 0
    
    // FIXME: Monkey code
    private var position: (Float, Float, Float) = (Float.zero, Float.zero + 1.6, Float.zero)
    private var rotation: CMQuaternion = .init()
    
    override init() {
        dispatchQueue = .init(label: "StupidARWorldTrackingSource", qos: .background)
        
        configuration = .init()
        // configuration.planeDetection = .horizontal
        
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
        
        // TODO: !!!
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
            
            rotation = .init(x: Double(x), y: Double(y), z: Double(z), w: Double(w))
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
    
    func getRotation() -> CMQuaternion {
        return rotation
    }
}
