//
//  WorldTrackingSource.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 23.02.2024.
//

import Foundation
import CoreMotion

protocol WorldTrackingSource {
    func getPosition() -> (Float, Float, Float)
    func getRotation() -> CMQuaternion
    
    func start()
    func stop()
}
