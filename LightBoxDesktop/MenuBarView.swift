import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var isPreviewWindowShown = false
    @State private var flashIntensity: Double = 1.0
    
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
            
            if connectionManager.isConnected {
                // Camera Controls
                Group {
                    // Flashlight Control
                    VStack(spacing: 8) {
                        Button(action: { connectionManager.toggleFlashlight() }) {
                            HStack {
                                Image(systemName: connectionManager.flashlightOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                Text(connectionManager.flashlightOn ? "Turn Off Flashlight" : "Turn On Flashlight")
                                Spacer()
                            }
                        }
                        
                        if connectionManager.flashlightOn {
                            HStack {
                                Text("Intensity")
                                Slider(value: $flashIntensity, in: 0.0...1.0) { changed in
                                    if !changed {
                                        connectionManager.setFlashIntensity(flashIntensity)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Rotation Control
                    Button(action: { connectionManager.rotateCamera() }) {
                        HStack {
                            Image(systemName: "rotate.right")
                            Text("Rotate Camera")
                            Spacer()
                        }
                    }
                    
                    // Camera Preview
                    Button(action: { openPreviewWindow() }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Camera Preview")
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal)
                
                Button(action: { connectionManager.disconnect() }) {
                    HStack {
                        Image(systemName: "disconnect.circle.fill")
                        Text("Disconnect")
                        Spacer()
                    }
                }
                .padding(.horizontal)
                
                Divider()
            } else {
                // Available Devices
                if connectionManager.discoveredDevices.isEmpty {
                    Text("Searching for devices...")
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                } else {
                    ForEach(connectionManager.discoveredDevices) { device in
                        Button(action: { connectionManager.connect(to: device) }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    Text("iPhone Camera")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("Connect")
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Divider()
            }
            
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
                Button("Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
    
    private func openPreviewWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Camera Preview"
        window.contentView = NSHostingView(rootView: CameraPreviewView()
            .environmentObject(connectionManager))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
} 