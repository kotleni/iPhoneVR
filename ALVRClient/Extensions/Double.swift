//
//  Double.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 25.02.2024.
//

import Foundation

extension Double {
    func toDegree() -> Float {
        return Float(self * 180.0 / Double.pi)
    }
}
