//
//  CMQuaternion.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 26.02.2024.
//

import CoreMotion

extension CMQuaternion {
    static func * (lhs: CMQuaternion, rhs: CMQuaternion) -> CMQuaternion {
        let result = CMQuaternion(
            x: lhs.w * rhs.w - lhs.x * rhs.x - lhs.y * rhs.y - lhs.z * rhs.z,
            y: lhs.w * rhs.x + lhs.x * rhs.w + lhs.y * rhs.z - lhs.z * rhs.y,
            z: lhs.w * rhs.y - lhs.x * rhs.z + lhs.y * rhs.w + lhs.z * rhs.x,
            w: lhs.w * rhs.z + lhs.x * rhs.y - lhs.y * rhs.x + lhs.z * rhs.w
        )
        return result
    }
}
