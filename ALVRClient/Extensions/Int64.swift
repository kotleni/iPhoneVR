//
//  Int64.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 23.02.2024.
//

import Foundation

extension Int64 {
    static func getCurrentMillis() -> Int64 {
        return Int64(NSDate().timeIntervalSince1970 * 1000)
    }
}
