import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    
    var body: some View {
        VStack(spacing: 12) {
            // Connection Status
            HStack {
                Image(systemName: connectionManager.isConnected ? "circle.fill" : "circle")
                    .foregroundColor(connectionManager.isConnected ? .green : .red)
                Text(connectionManager.isConnected ? "Connected" : "Disconnected")
                Spacer()
            }
            .padding(.horizontal)
            
            Divider()
            
            // Flashlight Control
            Button(action: { connectionManager.toggleFlashlight() }) {
                HStack {
                    Image(systemName: connectionManager.flashlightOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    Text(connectionManager.flashlightOn ? "Turn Off Flashlight" : "Turn On Flashlight")
                    Spacer()
                }
            }
            .disabled(!connectionManager.isConnected)
            .padding(.horizontal)
            
            Divider()
            
            // Quality Settings
            VStack(alignment: .leading, spacing: 8) {
                Text("Stream Quality")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Quality", selection: $connectionManager.currentQuality) {
                    ForEach(StreamQuality.allCases, id: \.self) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            // Auto-connect Toggle
            Toggle("Auto-connect on launch", isOn: $connectionManager.autoConnect)
                .padding(.horizontal)
            
            Divider()
            
            // Settings and Quit Buttons
            HStack {
                SettingsLink {
                    Label("Settings", systemImage: "gear")
                }
                
                Spacer()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .frame(width: 300)
    }
} 