//
//  LightBoxDesktopApp.swift
//  LightBoxDesktop
//
//  Created by Peter Grillet on 14/02/2025.
//

import SwiftUI
import AVFoundation
import Combine
import Network

@main
struct LightBoxDesktopApp: App {
    @StateObject private var connectionManager = ConnectionManager()
    
    var body: some Scene {
        MenuBarExtra("LightBox", systemImage: connectionManager.isConnected ? "video.fill" : "video") {
            MenuBarView()
                .environmentObject(connectionManager)
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView()
                .environmentObject(connectionManager)
        }
    }
}

// MARK: - Connection Manager
class ConnectionManager: ObservableObject {
    @Published var isConnected = false
    @Published var flashlightOn = false
    @Published var currentQuality: StreamQuality = .medium
    @Published var autoConnect = false
    @Published var connectedDevices: [ConnectedDevice] = []
    @Published var discoveredDevices: [ConnectedDevice] = []
    @Published var connectionState: NetworkConnectionState = .disconnected
    @Published var isVirtualCameraInstalled = false
    
    private let networkService = NetworkService()
    private var selectedDevice: ConnectedDevice?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var virtualCameraProcess: Process?
    private var cancellables = Set<AnyCancellable>()
    
    // Add video processing properties
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var videoQueue = DispatchQueue(label: "com.lightbox.videoqueue")
    
    init() {
        setupServices()
        checkVirtualCameraStatus()
    }
    
    func toggleFlashlight() {
        guard isConnected, let device = selectedDevice else {
            print("Cannot toggle flashlight: no active connection")
            return
        }
        
        flashlightOn.toggle()
        
        let command: [String: Any] = [
            "type": "command",
            "command": "flashlight",
            "state": flashlightOn
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: command) {
            networkService.sendData(data, to: device)
        }
    }
    
    private func setupServices() {
        // Start NetworkService
        networkService.startListening()
        
        // Observe NetworkService state changes
        networkService.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.connectedDevices = self?.networkService.connectedDevices ?? []
                self?.discoveredDevices = self?.networkService.connectedDevices ?? []
                self?.isConnected = self?.networkService.connectionState == .connected
                self?.connectionState = self?.networkService.connectionState ?? .disconnected
                
                // Start video stream when connected
                if self?.networkService.connectionState == .connected {
                    self?.startVideoStream()
                }
            }
        }.store(in: &cancellables)
        
        // Handle incoming video data
        networkService.onVideoData = { [weak self] sampleBuffer in
            self?.handleVideoData(sampleBuffer)
        }
    }
    
    private func startVideoStream() {
        guard connectionState == .connected, let device = selectedDevice else { return }
        
        // Request video stream from iOS device
        let request: [String: Any] = [
            "type": "command",
            "command": "start_video",
            "quality": currentQuality.rawValue
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: request) {
            networkService.sendData(data, to: device)
        }
    }
    
    private func handleVideoData(_ sampleBuffer: CMSampleBuffer) {
        // Process video data and send to virtual camera
        guard isVirtualCameraInstalled else { return }
        
        // Convert sample buffer to video frame and send to virtual camera
        // Implementation depends on your virtual camera interface
    }
    
    func disconnect() {
        connectionState = .disconnected
        networkService.stopListening()
        videoDataOutput = nil
        isConnected = false
        selectedDevice = nil
        flashlightOn = false
    }
    
    private func checkVirtualCameraStatus() {
        // Check if virtual camera plugin exists
        let pluginPath = "/Library/CoreMediaIO/Plug-Ins/DAL/LightBoxCamera.plugin"
        isVirtualCameraInstalled = FileManager.default.fileExists(atPath: pluginPath)
    }
    
    func connect(to device: ConnectedDevice) {
        guard !isConnected else { return }
        selectedDevice = device
        connectionState = .connecting
        
        // Start handshake sequence
        let handshake = HandshakeMessage(
            type: .request,
            deviceId: DeviceIdentifier.current().formatted,
            platform: "macOS"
        )
        
        if let data = try? JSONEncoder().encode(handshake) {
            networkService.sendData(data, to: device)
        }
    }
    
    func installVirtualCamera(completion: @escaping (Bool, String?) -> Void) {
        print("Starting virtual camera installation...")
        
        guard !isVirtualCameraInstalled else {
            print("Camera already installed, proceeding with uninstall...")
            // Uninstall if already installed
            uninstallVirtualCamera(completion: completion)
            return
        }
        
        // Get the script path from the bundle's Resources directory
        print("Looking for install script in bundle...")
        guard let scriptURL = Bundle.main.url(forResource: "install_camera", withExtension: "sh") else {
            print("Failed to find script in bundle")
            print("Bundle path: \(Bundle.main.bundlePath)")
            if let resourcePath = Bundle.main.resourcePath {
                print("Resource path: \(resourcePath)")
                try? FileManager.default.contentsOfDirectory(atPath: resourcePath).forEach { print($0) }
            }
            completion(false, "Installation script not found in Resources")
            return
        }
        print("Script URL: \(scriptURL)")
        
        do {
            // Read the script content
            print("Reading script content...")
            let scriptContent = try String(contentsOf: scriptURL, encoding: .utf8)
            print("Script content length: \(scriptContent.count) characters")
            
            // Create a temporary directory in a non-sandboxed location
            let tempScriptURL = URL(fileURLWithPath: "/private/tmp/install_camera.sh")
            print("Temporary script location: \(tempScriptURL.path)")
            
            // Write to temporary location with shebang
            print("Writing script to temporary location...")
            let fullScript = "#!/bin/bash\n" + scriptContent
            try fullScript.write(to: tempScriptURL, atomically: true, encoding: .utf8)
            
            // Make the temporary script executable
            print("Setting script permissions...")
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptURL.path)
            
            print("Creating process...")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            
            // Create the AppleScript command with explicit paths
            print("Setting up installation command...")
            let appleScript = """
            with timeout of 300 seconds
                try
                    do shell script "chmod +x '\(tempScriptURL.path)' && '\(tempScriptURL.path)'" with administrator privileges with prompt "LightBox needs administrator privileges to install the virtual camera."
                    return "Installation completed successfully"
                on error errMsg
                    return "Installation failed: " & errMsg
                end try
            end timeout
            """
            
            process.arguments = ["-e", appleScript]
            
            print("Setting up pipes...")
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            print("Running process...")
            try process.run()
            print("Waiting for process to complete...")
            process.waitUntilExit()
            
            print("Process completed with status: \(process.terminationStatus)")
            
            // Read output and error
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            print("Process output: \(output)")
            if !error.isEmpty {
                print("Process error: \(error)")
            }
            
            // Clean up temporary file
            print("Cleaning up temporary file...")
            try? FileManager.default.removeItem(at: tempScriptURL)
            
            let success = process.terminationStatus == 0 && !output.contains("Installation failed:")
            if success {
                print("Installation successful!")
                DispatchQueue.main.async {
                    self.isVirtualCameraInstalled = true
                }
                completion(true, nil)
            } else {
                print("Installation failed!")
                let errorMessage = output.contains("Installation failed:") ? output : error
                completion(false, errorMessage)
            }
        } catch {
            print("Installation error: \(error.localizedDescription)")
            completion(false, error.localizedDescription)
        }
    }
    
    private func uninstallVirtualCamera(completion: @escaping (Bool, String?) -> Void) {
        // Get the script path from the bundle's Resources directory
        guard let scriptURL = Bundle.main.url(forResource: "uninstall_camera", withExtension: "sh") else {
            completion(false, "Uninstallation script not found in Resources")
            return
        }
        
        // Create a temporary directory for the script
        let tempDir = FileManager.default.temporaryDirectory
        let tempScriptURL = tempDir.appendingPathComponent("uninstall_camera.sh")
        
        do {
            // Read the script content
            let scriptContent = try String(contentsOf: scriptURL, encoding: .utf8)
            
            // Write to temporary location with shebang
            let fullScript = "#!/bin/bash\n" + scriptContent
            try fullScript.write(to: tempScriptURL, atomically: true, encoding: .utf8)
            
            // Make the temporary script executable
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptURL.path)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            
            // Create the AppleScript command to request sudo privileges
            let appleScript = """
            do shell script "\(tempScriptURL.path)" with administrator privileges
            """
            
            process.arguments = ["-e", appleScript]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempScriptURL)
            
            let success = process.terminationStatus == 0
            if success {
                DispatchQueue.main.async {
                    self.isVirtualCameraInstalled = false
                }
                completion(true, nil)
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let error = String(data: data, encoding: .utf8) ?? "Unknown error"
                completion(false, error)
            }
        } catch {
            completion(false, error.localizedDescription)
        }
    }
}

// MARK: - Stream Quality Settings
enum StreamQuality: String, CaseIterable {
    case low = "Low (480p)"
    case medium = "Medium (720p)"
    case high = "High (1080p)"
    
    var resolution: (width: Int, height: Int) {
        switch self {
        case .low: return (640, 480)
        case .medium: return (1280, 720)
        case .high: return (1920, 1080)
        }
    }
    
    var frameRate: Int {
        switch self {
        case .low: return 15
        case .medium: return 24
        case .high: return 30
        }
    }
}

