//
//  File.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 22.02.2024.
//

import SwiftUI

@main
struct Main: App {
    @State private var isLobbyPresented: Bool = true
    
    var body: some Scene {
        WindowGroup {
            MetalView()
                .fullScreenCover(isPresented: $isLobbyPresented, content: {
                    LobbyView(isPresentedLobby: $isLobbyPresented)
                        .background(.windowBackground)
                })
                .ignoresSafeArea()
        }
    }
}
