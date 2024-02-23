//
//  WorldTrackingSource.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 23.02.2024.
//

import Foundation

protocol WorldTrackingSource {
    func getPosition() -> (Float, Float, Float)
    func getRotation() -> (Float, Float, Float)
    
    func start()
    func stop()
}
