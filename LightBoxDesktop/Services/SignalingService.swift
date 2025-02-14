import Foundation
import Network

enum SignalingMessage: Codable {
    case offer(sdp: String)
    case answer(sdp: String)
    case iceCandidate(candidate: String, sdpMLineIndex: Int32, sdpMid: String)
    case ready
    case error(message: String)
    
    private enum CodingKeys: String, CodingKey {
        case type, sdp, candidate, sdpMLineIndex, sdpMid, message
    }
    
    private enum MessageType: String, Codable {
        case offer, answer, iceCandidate, ready, error
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        
        switch type {
        case .offer:
            let sdp = try container.decode(String.self, forKey: .sdp)
            self = .offer(sdp: sdp)
        case .answer:
            let sdp = try container.decode(String.self, forKey: .sdp)
            self = .answer(sdp: sdp)
        case .iceCandidate:
            let candidate = try container.decode(String.self, forKey: .candidate)
            let sdpMLineIndex = try container.decode(Int32.self, forKey: .sdpMLineIndex)
            let sdpMid = try container.decode(String.self, forKey: .sdpMid)
            self = .iceCandidate(candidate: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        case .ready:
            self = .ready
        case .error:
            let message = try container.decode(String.self, forKey: .message)
            self = .error(message: message)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .offer(let sdp):
            try container.encode(MessageType.offer, forKey: .type)
            try container.encode(sdp, forKey: .sdp)
        case .answer(let sdp):
            try container.encode(MessageType.answer, forKey: .type)
            try container.encode(sdp, forKey: .sdp)
        case .iceCandidate(let candidate, let sdpMLineIndex, let sdpMid):
            try container.encode(MessageType.iceCandidate, forKey: .type)
            try container.encode(candidate, forKey: .candidate)
            try container.encode(sdpMLineIndex, forKey: .sdpMLineIndex)
            try container.encode(sdpMid, forKey: .sdpMid)
        case .ready:
            try container.encode(MessageType.ready, forKey: .type)
        case .error(let message):
            try container.encode(MessageType.error, forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}

class SignalingService {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.lightbox.signaling")
    var onMessage: ((SignalingMessage) -> Void)?
    private(set) var currentEndpoint: NWEndpoint?
    
    func connect(to endpoint: NWEndpoint) {
        currentEndpoint = endpoint
        let parameters = NWParameters.tls
        parameters.includePeerToPeer = true
        
        connection = NWConnection(to: endpoint, using: parameters)
        
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Signaling connection ready")
                self?.receiveMessage()
            case .failed(let error):
                print("Signaling connection failed: \(error)")
                self?.reconnect()
            case .waiting(let error):
                print("Signaling connection waiting: \(error)")
            default:
                break
            }
        }
        
        connection?.start(queue: queue)
    }
    
    private func reconnect() {
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let endpoint = self?.currentEndpoint else { return }
            self?.connection?.cancel()
            self?.connect(to: endpoint)
        }
    }
    
    private func receiveMessage() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            if let error = error {
                print("Receive error: \(error)")
                return
            }
            
            if let content = content,
               let message = try? JSONDecoder().decode(SignalingMessage.self, from: content) {
                DispatchQueue.main.async {
                    self?.onMessage?(message)
                }
            }
            
            if !isComplete {
                self?.receiveMessage()
            }
        }
    }
    
    func send(_ message: SignalingMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            }
        })
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
        currentEndpoint = nil
    }
} 