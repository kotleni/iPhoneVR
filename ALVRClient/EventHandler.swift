//
//  EventHandler.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 26.02.2024.
//

import UIKit

class EventHandler: ObservableObject {
    enum ConnectionState {
        case disconnected
        case connected
        // case connecting
    }
    
    static let shared = EventHandler()
    
    @Published var connectionState: ConnectionState = .disconnected
    @Published var hostname: String = ""
    @Published var ipAddr: String = ""
    
    var alvrInitialized = false
    var streamingActive = false
    private var lastBatteryStateUpdateTime: Int64 = 0
    private var worldTracker: WorldTracker? = nil
    private var alvrEvent: AlvrEvent = AlvrEvent()
    
    var delegate: EventHandlerDelegate? = nil
    
    /// Initialize alvr client but don't allow connecting
    func initialize(size: CGSize) {
        let refreshRates: [Float] = [60]
        let width = UInt32(size.width)
        let oneViewWidth = (width / 2)
        let height = UInt32(size.height)
        var capabilities = AlvrClientCapabilities()
        capabilities.default_view_width = oneViewWidth
        capabilities.default_view_height = height
        capabilities.refresh_rates = UnsafePointer(refreshRates)
        capabilities.refresh_rates_count = Int32(refreshRates.count)
        capabilities.external_decoder = true
        capabilities.foveated_encoding = false
        capabilities.encoder_high_profile = true
        capabilities.encoder_10_bits = true
        capabilities.encoder_av1 = false
        alvr_initialize(capabilities)
        
        print("ALVR initialized.")
    }
    
    /// Allow connection and request frames
    func start() {
        alvr_resume()
        alvr_request_idr()
    }
    
    /// Recreate world tracking with new params
    func setWorldTrackingParams(isTrackOrientation: Bool, isTrackPosition: Bool) {
        worldTracker?.stop()
        worldTracker = .init(isTrackOrientation: isTrackOrientation, isTrackPosition: isTrackPosition)
        worldTracker?.start()
    }
    
    private func parseMessage(_ message: String) {
        let lines = message.components(separatedBy: "\n")
        for line in lines {
            let keyValuePair = line.split(separator: ":")
            if keyValuePair.count == 2 {
                let key = keyValuePair[0].trimmingCharacters(in: .whitespaces)
                let value = keyValuePair[1].trimmingCharacters(in: .whitespaces)
                        if key == "hostname" {
                            updateHostname(value)
                        } else if key == "IP" {
                            updateIp(value)
                        }
            }
        }
    }
    
    private func updateHostname(_ newHostname: String) {
        DispatchQueue.main.async {
            self.hostname = newHostname
        }
    }

    private func updateIp(_ newIp: String) {
        DispatchQueue.main.async {
            self.ipAddr = newIp
        }
    }
    
    private func updateConnectionState(_ newState: ConnectionState) {
        DispatchQueue.main.async {
            self.connectionState = newState
        }
    }
    
    /// Poll all alvr events
    func pollEvents() {
        let res = alvr_poll_event(&alvrEvent)
        if res {
            // print(alvrEvent.tag)
            switch UInt32(alvrEvent.tag) {
            case ALVR_EVENT_HUD_MESSAGE_UPDATED.rawValue:
                print("hud message updated")
                let hudMessageBuffer = UnsafeMutableBufferPointer<CChar>.allocate(capacity: 1024)
                alvr_hud_message(hudMessageBuffer.baseAddress)
                
                let message = String(cString: hudMessageBuffer.baseAddress!, encoding: .utf8)!
                parseMessage(message)
                print(message)
                
                hudMessageBuffer.deallocate()
            case ALVR_EVENT_STREAMING_STARTED.rawValue:
                updateConnectionState(.connected)
                
                print("streaming started: \(alvrEvent.STREAMING_STARTED)")
                delegate?.updateStreamingState(isStarted: true)
                if !streamingActive {
                    streamingActive = true
                    alvr_request_idr()
                }
                alvrInitialized = true
            case ALVR_EVENT_STREAMING_STOPPED.rawValue:
                updateConnectionState(.disconnected)
                
                print("streaming stopped")
                alvrInitialized = false
                streamingActive = false
                delegate?.updateStreamingState(isStarted: false)
            case ALVR_EVENT_HAPTICS.rawValue:
                print("haptics: \(alvrEvent.HAPTICS)")
            case ALVR_EVENT_DECODER_CONFIG.rawValue:
                streamingActive = true
                print("create decoder: \(alvrEvent.DECODER_CONFIG)")
                delegate?.createDecoder()
            case ALVR_EVENT_FRAME_READY.rawValue:
                // print("frame ready")
                if connectionState == .connected {
                    delegate?.updateFrame()
                    
                    if let worldTracker = worldTracker {
                        // YOLO?
                        // Send new tracking
                        let pose = AlvrPose(orientation: worldTracker.getQuaterionRotation(), position: worldTracker.getPosition())
                        var trackingMotion = AlvrDeviceMotion(device_id: MetalView.Coordinator.deviceIdHead, pose: pose, linear_velocity: (0, 0, 0), angular_velocity: (0, 0, 0))
                        let timestamp = mach_absolute_time()
                        //print("sending tracking for timestamp \(timestamp)")
                        
                        let v: Float = 1.0
                        let v2: Float = 1.0
                        let leftAngles = atan(simd_float4(v, v, v, v))
                        let rightAngles = atan(simd_float4(v2, v2, v2, v2))
                        let leftFov = AlvrFov(left: -leftAngles.x, right: leftAngles.y, up: leftAngles.z, down: -leftAngles.w)
                        let rightFov = AlvrFov(left: -rightAngles.x, right: rightAngles.y, up: rightAngles.z, down: -rightAngles.w)
                        let leftPose = pose
                        var rightPose = pose
                        rightPose.position.0 += 0.063 // HAX: each eyes can't have same positions
                        let viewFovsPtr = UnsafeMutablePointer<AlvrViewParams>.allocate(capacity: 2)
                                viewFovsPtr[0] = AlvrViewParams(pose: leftPose, fov: rightFov)
                                viewFovsPtr[1] = AlvrViewParams(pose: rightPose, fov: rightFov)
//                        let ipd = Float(0.063)
                        
                        var viewParams = AlvrViewParams(pose: pose, fov: leftFov)
                        alvr_send_tracking(timestamp, UnsafePointer(viewFovsPtr), &trackingMotion, 1, nil, nil)
                    }
                    
                    // Send battery state every 30 secs
                    if Int64.getCurrentMillis() - lastBatteryStateUpdateTime > 1000 * 30 {
                        lastBatteryStateUpdateTime = Int64.getCurrentMillis()
                        UIDevice.current.isBatteryMonitoringEnabled = true
                        print("Update battery state: \(UIDevice.current.batteryLevel) / 1.0 | Is charging: \(UIDevice.current.batteryState == .charging)")
                        alvr_send_battery(MetalView.Coordinator.deviceIdHead, UIDevice.current.batteryLevel, UIDevice.current.batteryState == .charging)
                    }
                }
            default:
                print("what")
            }
        } else {
            usleep(10000)
        }
    }
}
