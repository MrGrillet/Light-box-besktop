import SwiftUI
import AVFoundation

class VideoPreviewView: NSView {
    private var imageView: NSImageView
    
    override init(frame: NSRect) {
        imageView = NSImageView(frame: frame)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        
        super.init(frame: frame)
        addSubview(imageView)
        
        // Add autoresizing mask to maintain proper sizing
        imageView.autoresizingMask = [.width, .height]
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        
        // Adjust frame based on rotation
        let rotation = ConnectionManager.shared.currentRotation
        if rotation == 90 || rotation == 270 {
            // For 90/270 degree rotations, swap width and height while maintaining aspect ratio
            let aspectRatio = bounds.width / bounds.height
            let newWidth = bounds.height
            let newHeight = bounds.width
            
            if aspectRatio > 1 {
                imageView.frame = NSRect(
                    x: (bounds.width - newWidth) / 2,
                    y: (bounds.height - newHeight) / 2,
                    width: newWidth,
                    height: newHeight
                )
            } else {
                imageView.frame = bounds
            }
        } else {
            imageView.frame = bounds
        }
    }
    
    func updateImage(_ image: NSImage?) {
        imageView.image = image
        needsLayout = true
    }
}

struct VideoPreviewRepresentable: NSViewRepresentable {
    @ObservedObject var networkService: NetworkService
    
    func makeNSView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView(frame: .zero)
        return view
    }
    
    func updateNSView(_ nsView: VideoPreviewView, context: Context) {
        nsView.updateImage(networkService.currentFrame)
    }
}

struct CameraPreviewView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var isPreviewActive = false
    
    var body: some View {
        VStack(spacing: 16) {
            if isPreviewActive {
                VideoPreviewRepresentable(networkService: connectionManager.networkService)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                HStack {
                    Button("Stop Preview") {
                        stopPreview()
                    }
                    
                    Button(action: { connectionManager.rotateCamera() }) {
                        Image(systemName: "rotate.right")
                        Text("Rotate")
                    }
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