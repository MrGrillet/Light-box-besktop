import SwiftUI
import AVFoundation

struct CameraPreviewView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var isPreviewActive = false
    
    var body: some View {
        VStack(spacing: 16) {
            if isPreviewActive {
                PreviewRepresentable(connectionManager: connectionManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Button("Stop Preview") {
                    stopPreview()
                }
                .padding(.bottom)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("Camera Preview")
                        .font(.title)
                    
                    Button("Start Preview") {
                        startPreview()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(Color(.windowBackgroundColor))
    }
    
    private func startPreview() {
        guard let device = connectionManager.selectedDevice else { return }
        
        // Request video preview from iOS device
        let request: [String: Any] = [
            "type": "command",
            "command": "start_preview",
            "quality": connectionManager.currentQuality.rawValue
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: request) {
            connectionManager.networkService.sendData(data, to: device)
            isPreviewActive = true
        }
    }
    
    private func stopPreview() {
        guard let device = connectionManager.selectedDevice else { return }
        
        // Send stop preview command to iOS device
        let request: [String: Any] = [
            "type": "command",
            "command": "stop_preview"
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: request) {
            connectionManager.networkService.sendData(data, to: device)
            isPreviewActive = false
        }
    }
}

// SwiftUI wrapper for AVCaptureVideoPreviewLayer
struct PreviewRepresentable: NSViewRepresentable {
    let connectionManager: ConnectionManager
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        
        let previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        
        view.layer = previewLayer
        connectionManager.setPreviewLayer(previewLayer)
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.frame = nsView.bounds
    }
} 