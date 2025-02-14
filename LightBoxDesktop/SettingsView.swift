import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    
    var body: some View {
        TabView {
            ConnectionSettingsView()
                .tabItem {
                    Label("Connection", systemImage: "network")
                }
            
            VideoSettingsView()
                .tabItem {
                    Label("Video", systemImage: "video")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct ConnectionSettingsView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    
    var body: some View {
        Form {
            Section("Connection Settings") {
                Toggle("Auto-connect on launch", isOn: $connectionManager.autoConnect)
                
                // Connection Status
                Group {
                    HStack {
                        connectionStateIcon
                        Text(connectionStateText)
                            .foregroundColor(connectionStateColor)
                    }
                }
                
                if case .failed(let error) = connectionManager.connectionState {
                    Text(error.localizedDescription)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                if connectionManager.isConnected {
                    Button("Disconnect") {
                        connectionManager.disconnect()
                    }
                    .foregroundColor(.red)
                }
            }
            
            Section("Available Devices") {
                if connectionManager.discoveredDevices.isEmpty {
                    Text("Searching for devices...")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(connectionManager.discoveredDevices) { device in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name)
                                Text("iPhone Camera")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if case .connecting = connectionManager.connectionState {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Button(action: { connectionManager.connect(to: device) }) {
                                    Text("Connect")
                                }
                                .disabled(connectionManager.isConnected)
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private var connectionStateIcon: some View {
        let (imageName, color) = connectionStateIconInfo
        Image(systemName: imageName)
            .foregroundColor(color)
    }
    
    private var connectionStateIconInfo: (imageName: String, color: Color) {
        switch connectionManager.connectionState {
        case .connected:
            return ("circle.fill", .green)
        case .connecting:
            return ("circle.fill", .yellow)
        case .preparing:
            return ("circle.fill", .yellow)
        case .ready:
            return ("circle.fill", .yellow)
        case .waiting:
            return ("circle.fill", .yellow)
        case .disconnected:
            return ("circle.fill", .red)
        case .failed:
            return ("exclamationmark.circle.fill", .red)
        case .cancelled:
            return ("circle.fill", .red)
        }
    }
    
    private var connectionStateText: String {
        switch connectionManager.connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .preparing:
            return "Preparing..."
        case .ready:
            return "Ready"
        case .waiting(let error):
            return "Waiting: \(error.localizedDescription)"
        case .disconnected:
            return "Disconnected"
        case .failed(let error):
            return "Failed: \(error.localizedDescription)"
        case .cancelled:
            return "Cancelled"
        }
    }
    
    private var connectionStateColor: Color {
        switch connectionManager.connectionState {
        case .connected:
            return .green
        case .connecting, .preparing, .ready, .waiting:
            return .yellow
        case .disconnected, .failed, .cancelled:
            return .red
        }
    }
}

struct VideoSettingsView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var isInstallingCamera = false
    @State private var installationError: String?
    
    var body: some View {
        Form {
            Section("Video Quality") {
                Picker("Stream Quality", selection: $connectionManager.currentQuality) {
                    ForEach(StreamQuality.allCases, id: \.self) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Resolution: \(connectionManager.currentQuality.resolution.width)×\(connectionManager.currentQuality.resolution.height)")
                    Text("Frame Rate: \(connectionManager.currentQuality.frameRate) FPS")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Section("Virtual Camera") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Virtual Camera Status: \(connectionManager.isVirtualCameraInstalled ? "Installed" : "Not Installed")")
                    
                    if isInstallingCamera {
                        ProgressView("Installing...")
                    } else {
                        Button(connectionManager.isVirtualCameraInstalled ? "Uninstall Virtual Camera" : "Install Virtual Camera") {
                            installVirtualCamera()
                        }
                    }
                    
                    if let error = installationError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .disabled(isInstallingCamera)
        }
        .padding()
    }
    
    private func installVirtualCamera() {
        isInstallingCamera = true
        installationError = nil
        
        Task {
            do {
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                switch status {
                case .notDetermined:
                    let granted = await AVCaptureDevice.requestAccess(for: .video)
                    if !granted {
                        throw NSError(domain: "com.lightbox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Camera access denied"])
                    }
                case .restricted:
                    throw NSError(domain: "com.lightbox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Camera access restricted"])
                case .denied:
                    throw NSError(domain: "com.lightbox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Camera access denied. Please enable it in System Settings."])
                case .authorized:
                    break
                @unknown default:
                    break
                }
                
                // Install virtual camera
                await MainActor.run {
                    connectionManager.installVirtualCamera { success, error in
                        isInstallingCamera = false
                        if !success {
                            installationError = error ?? "Failed to install virtual camera"
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isInstallingCamera = false
                    installationError = error.localizedDescription
                }
            }
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.fill")
                .font(.system(size: 50))
            
            Text("LightBox Desktop")
                .font(.title)
            
            Text("Version 1.0.0")
                .foregroundColor(.secondary)
            
            Text("A companion app for LightBox iOS that turns your iPhone into a professional webcam.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding()
    }
} 