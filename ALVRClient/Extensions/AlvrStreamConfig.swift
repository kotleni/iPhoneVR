//
//  AlvrStreamConfig.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 26.02.2024.
//

import Foundation

extension AlvrStreamConfig {
    static func createDefault(_ body: StreamingStarted_Body) -> AlvrStreamConfig {
        let cfg = AlvrStreamConfig(view_resolution_width: body.view_width, view_resolution_height: body.view_height, swapchain_textures: .none, swapchain_length: 0, enable_foveation: true, foveation_center_size_x: 0.45, foveation_center_size_y: 0.4, foveation_center_shift_x: 0.4, foveation_center_shift_y: 0.1, foveation_edge_ratio_x: 4.0, foveation_edge_ratio_y: 5.0)
        return cfg
    }
}
