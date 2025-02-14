import Foundation
import AVFoundation
import Network

protocol WebRTCServiceDelegate: AnyObject {
    func webRTCService(_ service: WebRTCService, didReceiveVideoTrack videoTrack: AVCaptureVideoDataOutput)
    func webRTCService(_ service: WebRTCService, didChangeConnectionState state: ConnectionState)
    func webRTCService(_ service: WebRTCService, didReceiveData data: Data)
}

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case failed(Error)
}

class WebRTCService {
    weak var delegate: WebRTCServiceDelegate?
    private let signalingService: SignalingService
    private var dataConnection: URLSessionWebSocketTask?
    private var session: URLSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    
    init(signalingService: SignalingService) {
        self.signalingService = signalingService
        setupSignalingHandlers()
    }
    
    private func setupSignalingHandlers() {
        signalingService.onMessage = { [weak self] message in
            self?.handle(signalingMessage: message)
        }
    }
    
    private func handle(signalingMessage message: SignalingMessage) {
        switch message {
        case .offer(let sdp):
            handleRemoteOffer(sdp)
        case .answer(let sdp):
            handleRemoteAnswer(sdp)
        case .iceCandidate(_, _, _):
            // ICE candidates will be handled through direct WebSocket connection
            break
        case .ready:
            setupConnection()
        case .error(let message):
            print("Signaling error: \(message)")
            delegate?.webRTCService(self, didChangeConnectionState: .failed(NSError(domain: "com.lightbox", code: -1, userInfo: [NSLocalizedDescriptionKey: message])))
        }
    }
    
    private func setupConnection() {
        guard let endpoint = signalingService.currentEndpoint,
              case .service(let name, let type, let domain, _) = endpoint else {
            delegate?.webRTCService(self, didChangeConnectionState: .failed(NSError(domain: "com.lightbox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid endpoint"])))
            return
        }
        
        // Construct WebSocket URL using the service information
        let urlString = "ws://\(name).\(type).\(domain):8080/video"
        guard let url = URL(string: urlString) else {
            delegate?.webRTCService(self, didChangeConnectionState: .failed(NSError(domain: "com.lightbox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid WebSocket URL"])))
            return
        }
        
        session = URLSession(configuration: .default)
        dataConnection = session?.webSocketTask(with: url)
        dataConnection?.resume()
        
        receiveData()
        delegate?.webRTCService(self, didChangeConnectionState: .connecting)
    }
    
    private func receiveData() {
        dataConnection?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.delegate?.webRTCService(self, didReceiveData: data)
                case .string(let string):
                    if let data = string.data(using: .utf8) {
                        self.delegate?.webRTCService(self, didReceiveData: data)
                    }
                @unknown default:
                    break
                }
                self.receiveData()
                
            case .failure(let error):
                self.delegate?.webRTCService(self, didChangeConnectionState: .failed(error))
            }
        }
    }
    
    private func handleRemoteOffer(_ sdp: String) {
        // In this simplified version, we'll just acknowledge the offer
        signalingService.send(.answer(sdp: "accepted"))
        delegate?.webRTCService(self, didChangeConnectionState: .connected)
    }
    
    private func handleRemoteAnswer(_ sdp: String) {
        // Connection is established
        delegate?.webRTCService(self, didChangeConnectionState: .connected)
    }
    
    func sendData(_ data: Data) {
        dataConnection?.send(.data(data)) { [weak self] error in
            if let error = error {
                self?.delegate?.webRTCService(self!, didChangeConnectionState: .failed(error))
            }
        }
    }
    
    func disconnect() {
        dataConnection?.cancel()
        dataConnection = nil
        session?.invalidateAndCancel()
        session = nil
        delegate?.webRTCService(self, didChangeConnectionState: .disconnected)
    }
} 