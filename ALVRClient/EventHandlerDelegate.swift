//
//  EventHandlerDelegate.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 27.02.2024.
//

import Foundation

protocol EventHandlerDelegate {
    func updateStreamingState(isStarted: Bool)
    func createDecoder()
    func updateFrame()
}
