//
//  LobbyView.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 26.02.2024.
//

import SwiftUI

class LobbyViewModel: ObservableObject {
    @Published var version: String = ""
    @Published var hostName: String = ""
    @Published var ipAddr: String = ""
    
    @Published var selectedTrackingMode: WorldTracker.WorldTrackingMode = .easyArSession
    
    func loadSettings() {
        WorldTracker.WorldTrackingMode.allCases.forEach { mode in
            if mode.rawValue == UserDefaults.standard.string(forKey: "selectedTrackingMode") {
                selectedTrackingMode = mode
            }
        }
    }
    
    func saveSettings() {
        UserDefaults.standard.setValue(selectedTrackingMode.rawValue, forKey: "selectedTrackingMode")
    }
}

struct ListItem: View {
    let title: String
    let content: String
    
    var body: some View {
        HStack {
            Text(title)
                //.bold()
            Spacer()
            Text(content)
        }
    }
}

struct LobbyView: View {
    @State var isPresentedLobby: Binding<Bool>
    
    @ObservedObject private var viewModel = LobbyViewModel()
    @ObservedObject private var eventHandler = EventHandler.shared
    
    private let trackindModes: [WorldTracker.WorldTrackingMode] = [.arSession, .easyArSession]
    
    var body: some View {
        List {
            Section {
                Button("Start") {
                    isPresentedLobby.wrappedValue = false
                    isPresentedLobby.update()
                    
                    viewModel.saveSettings()
                    EventHandler.shared.start()
                }
            }
            
            Section("Server") {
                // ListItem(title: "Version", content: eventHandler.version)
                ListItem(title: "IP", content: "\(eventHandler.ipAddr)")
                ListItem(title: "Hostname", content: "\(eventHandler.hostname)")
            }
            
            Section("Settings") {
                Picker("World tracking mode", selection: $viewModel.selectedTrackingMode) {
                    ForEach(trackindModes, id: \.self) { mode in
                        Text("\(mode.rawValue)")
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadSettings()
        }
    }
}
