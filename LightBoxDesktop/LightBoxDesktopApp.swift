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
    @StateObject private var connectionManager = ConnectionManager.shared
    
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
    static let shared = ConnectionManager()
    
    @Published var isConnected = false
    @Published var flashlightOn = false
    @Published var currentQuality: StreamQuality = .medium
    @Published var autoConnect = false
    @Published var connectedDevices: [ConnectedDevice] = []
    @Published var discoveredDevices: [ConnectedDevice] = []
    @Published var connectionState: NetworkConnectionState = .disconnected
    @Published var isVirtualCameraInstalled = false
    @Published var previewSession: AVCaptureSession?
    @Published var currentRotation: Int = 0 // 0, 90, 180, 270 degrees
    
    let networkService = NetworkService()
    var selectedDevice: ConnectedDevice?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var virtualCameraProcess: Process?
    private var cancellables = Set<AnyCancellable>()
    
    // Add video processing properties
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var videoQueue = DispatchQueue(label: "com.lightbox.videoqueue")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    init() {
        setupServices()
        checkVirtualCameraStatus()
        
        // Check if this is first launch or camera needs installation
        if !isVirtualCameraInstalled {
            handleFirstLaunch()
        }
    }
    
    private func handleFirstLaunch() {
        // Show first launch window with installation prompt
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Welcome to LightBox"
            alert.informativeText = "LightBox needs to install a virtual camera driver to enable video conferencing functionality. This requires administrator access.\n\nWithout this driver, video conferencing apps won't be able to use your iPhone's camera."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Install Now")
            alert.addButton(withTitle: "Install Later")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.installVirtualCamera { success, error in
                    DispatchQueue.main.async {
                        if success {
                            let successAlert = NSAlert()
                            successAlert.messageText = "Installation Successful"
                            successAlert.informativeText = "The virtual camera driver has been installed. You can now use LightBox with your favorite video conferencing apps."
                            successAlert.alertStyle = .informational
                            successAlert.addButton(withTitle: "OK")
                            successAlert.runModal()
                        } else {
                            let failureAlert = NSAlert()
                            failureAlert.messageText = "Installation Failed"
                            failureAlert.informativeText = "The virtual camera driver could not be installed. You can try again later in Settings.\n\nError: \(error ?? "Unknown error")"
                            failureAlert.alertStyle = .warning
                            failureAlert.addButton(withTitle: "OK")
                            failureAlert.runModal()
                        }
                    }
                }
            }
        }
    }
    
    private func setupServices() {
        // Start NetworkService
        networkService.startListening()
        
        // Observe NetworkService state changes
        networkService.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.connectedDevices = self.networkService.connectedDevices
                self.discoveredDevices = self.networkService.connectedDevices
                self.isConnected = self.networkService.connectionState == .connected
                self.connectionState = self.networkService.connectionState
                
                // Update selectedDevice when connection changes
                if self.networkService.connectionState == .connected {
                    // If we don't have a selectedDevice but have connected devices, select the first one
                    if self.selectedDevice == nil && !self.connectedDevices.isEmpty {
                        self.selectedDevice = self.connectedDevices[0]
                        print("Selected device updated to: \(self.connectedDevices[0].id)")
                    }
                } else if self.networkService.connectionState == .disconnected {
                    self.selectedDevice = nil
                    print("Selected device cleared due to disconnection")
                }
            }
        }.store(in: &cancellables)
        
        // Handle incoming video data
        networkService.onVideoData = { [weak self] sampleBuffer in
            self?.handleVideoData(sampleBuffer)
        }
    }
    
    private func handleVideoData(_ sampleBuffer: CMSampleBuffer) {
        guard let previewLayer = previewLayer else { return }
        
        DispatchQueue.main.async {
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let originalImage = CIImage(cvPixelBuffer: pixelBuffer)
                
                // Apply rotation transform
                let rotatedImage = originalImage.transformed(by: CGAffineTransform(translationX: originalImage.extent.width/2, y: originalImage.extent.height/2)
                    .rotated(by: CGFloat(self.currentRotation) * .pi / 180)
                    .translatedBy(x: -originalImage.extent.width/2, y: -originalImage.extent.height/2))
                
                previewLayer.contents = rotatedImage
            }
        }
    }
    
    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = layer
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
        let wasInstalled = isVirtualCameraInstalled
        isVirtualCameraInstalled = FileManager.default.fileExists(atPath: pluginPath)
        
        // If camera was installed but is now missing, alert user
        if wasInstalled && !isVirtualCameraInstalled {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Virtual Camera Missing"
                alert.informativeText = "The LightBox virtual camera driver appears to have been removed. Would you like to reinstall it?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Reinstall")
                alert.addButton(withTitle: "Later")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    self.installVirtualCamera { _, _ in }
                }
            }
        }
    }
    
    func installVirtualCamera(completion: @escaping (Bool, String?) -> Void) {
        print("Starting virtual camera installation...")
        
        // Get the plugin path from the bundle
        guard let bundlePath = Bundle.main.resourcePath else {
            completion(false, "Could not locate app bundle")
            return
        }
        
        // Use the actual plugin path (CMIOMinimalSample.plugin)
        let pluginPath = (bundlePath as NSString).appendingPathComponent("LightBoxCamera.plugin/CMIOMinimalSample.plugin")
        let targetPath = "/Library/CoreMediaIO/Plug-Ins/DAL/LightBoxCamera.plugin"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        
        // Create the command with proper escaping for AppleScript
        let shellCommand = """
        mkdir -p /Library/CoreMediaIO/Plug-Ins/DAL; \
        rm -rf \(targetPath.replacingOccurrences(of: "\"", with: "\\\"")); \
        cp -R \(pluginPath.replacingOccurrences(of: "\"", with: "\\\"")) \(targetPath.replacingOccurrences(of: "\"", with: "\\\"")); \
        chown -R root:wheel \(targetPath.replacingOccurrences(of: "\"", with: "\\\"")); \
        chmod -R 755 \(targetPath.replacingOccurrences(of: "\"", with: "\\\"")); \
        killall VDCAssistant || true
        """
        
        let osascript = """
        on run
            try
                do shell script "\(shellCommand.replacingOccurrences(of: "\"", with: "\\\""))" with administrator privileges
                return "success"
            on error errMsg
                return errMsg
            end try
        end run
        """
        
        process.arguments = ["-e", osascript]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if process.terminationStatus == 0 && output.contains("success") {
                // Add a small delay before checking installation
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.startCheckingInstallation(completion: completion)
                }
            } else {
                completion(false, "Installation failed: \(output)")
            }
        } catch {
            completion(false, "Failed to run installation: \(error.localizedDescription)")
        }
    }
    
    private func startCheckingInstallation(completion: @escaping (Bool, String?) -> Void) {
        let pluginPath = "/Library/CoreMediaIO/Plug-Ins/DAL/LightBoxCamera.plugin"
        
        // Check every second for up to 60 seconds
        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            attempts += 1
            
            if FileManager.default.fileExists(atPath: pluginPath) {
                timer.invalidate()
                DispatchQueue.main.async {
                    self.isVirtualCameraInstalled = true
                }
                completion(true, nil)
            } else if attempts >= 60 {
                timer.invalidate()
                completion(false, "Installation timed out. Please check System Settings > Privacy & Security for any pending approvals.")
            }
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
    
    func toggleFlashlight() {
        print("\n=== Attempting to Toggle Flashlight ===")
        print("Connection state: \(connectionState)")
        print("Is connected: \(isConnected)")
        print("Selected device: \(String(describing: selectedDevice))")
        print("Connected devices: \(connectedDevices)")
        
        guard isConnected, let device = selectedDevice else {
            print("Cannot toggle flashlight: no active connection")
            print("isConnected: \(isConnected)")
            print("selectedDevice: \(String(describing: selectedDevice))")
            return
        }
        
        flashlightOn.toggle()
        print("Toggling flashlight to: \(flashlightOn)")
        
        let command: [String: Any] = [
            "type": "command",
            "command": "flashlight",
            "state": flashlightOn
        ]
        
        print("Preparing to send command: \(command)")
        
        if let data = try? JSONSerialization.data(withJSONObject: command) {
            print("Sending flashlight command to device: \(device.id)")
            networkService.sendData(data, to: device)
        } else {
            print("Failed to serialize flashlight command")
        }
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
    
    func rotateCamera() {
        // Rotate 90 degrees clockwise
        currentRotation = (currentRotation + 90) % 360
        print("Rotating camera view to \(currentRotation) degrees")
    }
    
    func setFlashIntensity(_ intensity: Double) {
        print("\n=== Setting Flash Intensity ===")
        guard isConnected, let device = selectedDevice else {
            print("Cannot set flash intensity: no active connection")
            return
        }
        
        let command: [String: Any] = [
            "type": "command",
            "command": "set_flash_intensity",
            "intensity": intensity
        ]
        
        print("Sending flash intensity command: \(intensity)")
        
        if let data = try? JSONSerialization.data(withJSONObject: command) {
            networkService.sendData(data, to: device)
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

