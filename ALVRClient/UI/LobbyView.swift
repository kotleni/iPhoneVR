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
    
    @Published var isDontTrackOrientation: Bool = true
    @Published var isDontTrackPosition: Bool = true
    
    func loadSettings() {
        isDontTrackOrientation = UserDefaults.standard.bool(forKey: "isDontTrackOrientation")
        isDontTrackPosition = UserDefaults.standard.bool(forKey: "isDontTrackPosition")
    }
    
    func saveSettings() {
        UserDefaults.standard.setValue(isDontTrackOrientation, forKey: "isDontTrackOrientation")
        UserDefaults.standard.setValue(isDontTrackPosition, forKey: "isDontTrackPosition")
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
    
    var body: some View {
        List {
            Section {
                Button("Start") {
                    isPresentedLobby.wrappedValue = false
                    isPresentedLobby.update()
                    
                    viewModel.saveSettings()
                    EventHandler.shared.setWorldTrackingParams(isTrackOrientation: !viewModel.isDontTrackOrientation, isTrackPosition: !viewModel.isDontTrackPosition)
                    EventHandler.shared.start()
                }
                
                Text("After pressing the start button, the device should lie on the table in a horizontal position.")
                    .fontWeight(.light)
            }
            
            Section("Server") {
                ListItem(title: "IP", content: "\(eventHandler.ipAddr)")
                ListItem(title: "Hostname", content: "\(eventHandler.hostname)")
            }
            
            Section("Tracking") {
                Toggle("Orientation", isOn: !$viewModel.isDontTrackOrientation)
                Toggle("Position", isOn: !$viewModel.isDontTrackPosition)
            }
        }
        .onAppear {
            viewModel.loadSettings()
        }
    }
}
