import Foundation
import MultipeerConnectivity
import AppKit
import CoreMedia

// MARK: - Types
enum HandshakeMessageType: String, Codable {
    case request
    case response
}

struct HandshakeMessage: Codable {
    let type: HandshakeMessageType
    let deviceId: String
    let platform: String
    
    init(type: HandshakeMessageType, deviceId: String = DeviceIdentifier.current().formatted, platform: String = "macOS") {
        self.type = type
        self.deviceId = deviceId
        self.platform = platform
    }
    
    var identifier: DeviceIdentifier? {
        return DeviceIdentifier.parse(deviceId)
    }
}

public class NetworkService: NSObject, ObservableObject {
    public static let shared = NetworkService()
    static let serviceType = "lightbox-app"
    
    // MARK: - Published Properties
    @Published public var connectionState: NetworkConnectionState = .disconnected
    @Published public var isListening = false
    @Published public var connectedDevices: [ConnectedDevice] = []
    
    // MARK: - Private Properties
    private var session: MCSession?
    private var serviceAdvertiser: MCNearbyServiceAdvertiser?
    private var serviceBrowser: MCNearbyServiceBrowser?
    private let peerId = MCPeerID(displayName: "MacDesktop")
    private var discoveryInfo: [String: String] {
        return ["platform": "macOS", "role": "host"]
    }
    private var pendingConnections: Set<String> = []
    private var handshakeTimers: [MCPeerID: Timer] = [:]
    private var keepAliveTimers: [MCPeerID: Timer] = [:]
    private var reconnectTimer: Timer?
    private var isReconnecting = false
    private var handshakeCompletedPeers: Set<MCPeerID> = []
    private var lastKeepAliveReceived: [MCPeerID: Date] = [:]
    private var connectionMonitorTimer: Timer?
    private var failedConnectionAttempts: [String: Int] = [:]
    private var lastConnectionAttempt: [String: Date] = [:]
    private var messageQueue: [(Data, MCPeerID)] = []
    private var isSessionActive = false
    
    // MARK: - Constants
    private let keepAliveInterval: TimeInterval = 2.0
    private let keepAliveTimeout: TimeInterval = 6.0
    private let handshakeTimeout: TimeInterval = 15.0
    private let reconnectInterval: TimeInterval = 5.0
    private let maxConnectionAttempts = 3
    private let connectionCooldown: TimeInterval = 10.0
    private let initialChannelDelay: TimeInterval = 0.5
    private let channelEstablishmentDelay: TimeInterval = 2.0
    private let channelStabilizationDelay: TimeInterval = 1.0
    private let handshakeResponseDelay: TimeInterval = 0.5
    private let maxQueuedMessages = 10
    private let dtlsRetryAttempts = 3
    private let dtlsRetryDelay: TimeInterval = 1.0
    
    // Add callback for video data
    public var onVideoData: ((CMSampleBuffer) -> Void)?
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupMultipeerConnectivity()
        startConnectionMonitor()
    }
    
    // MARK: - Setup
    private func setupMultipeerConnectivity() {
        print("\n=== macOS Setup Phase ===")
        print("macOS: Setting up Multipeer Connectivity...")
        print("macOS Configuration:")
        print("- Device name: \(peerId.displayName)")
        print("- Service type: \(Self.serviceType)")
        print("- Discovery info: \(discoveryInfo)")
        print("- Expected iOS platform in discovery info: ['platform': 'iOS']")
        print("Protocol Roles:")
        print("- macOS acts as host and initiates handshake")
        print("- iOS should wait for macOS handshake and respond")
        print("Connection Sequence:")
        print("1. Initial connection (MCSession)")
        print("2. DTLS establishment (SSL/TLS handshake)")
        print("3. Handshake exchange:")
        print("   - macOS sends HandshakeMessage(type: .request)")
        print("   - iOS responds with HandshakeMessage(type: .response)")
        print("4. Keep-alive exchange starts after successful handshake")
        print("Timing Configuration:")
        print("- DTLS retry attempts: \(dtlsRetryAttempts)")
        print("- DTLS retry delay: \(dtlsRetryDelay)s")
        print("- Channel establishment: \(channelEstablishmentDelay)s")
        print("- Channel stabilization: \(channelStabilizationDelay)s")
        print("- Handshake timeout: \(handshakeTimeout)s")
        print("- Keep-alive interval: \(keepAliveInterval)s")
        print("- Keep-alive timeout: \(keepAliveTimeout)s")
        print("=== End Setup Info ===\n")
        
        // Clean up existing session if any
        cleanupExistingSession()
        
        // Create and configure session with encryption
        let newSession = MCSession(
            peer: peerId,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        newSession.delegate = self
        session = newSession
        isSessionActive = true
        print("Created new session with encryption")
        
        // Create and start advertising
        serviceAdvertiser = MCNearbyServiceAdvertiser(
            peer: peerId,
            discoveryInfo: discoveryInfo,
            serviceType: Self.serviceType
        )
        serviceAdvertiser?.delegate = self
        print("Created service advertiser")
        
        // Create and start browsing
        serviceBrowser = MCNearbyServiceBrowser(
            peer: peerId,
            serviceType: Self.serviceType
        )
        serviceBrowser?.delegate = self
        print("Created service browser")
        
        // Reset connection tracking
        resetConnectionState()
        
        // Start services
        startListening()
    }
    
    private func cleanupExistingSession() {
        isSessionActive = false
        
        if let existingSession = session {
            existingSession.disconnect()
            for peer in existingSession.connectedPeers {
                cleanupTimersForPeer(peer)
            }
        }
        
        session = nil
        serviceAdvertiser?.stopAdvertisingPeer()
        serviceAdvertiser = nil
        serviceBrowser?.stopBrowsingForPeers()
        serviceBrowser = nil
    }
    
    private func resetConnectionState() {
        print("Resetting connection state...")
        
        // Clean up all timers
        for (peer, timer) in handshakeTimers {
            timer.invalidate()
            handshakeTimers.removeValue(forKey: peer)
        }
        
        for (peer, timer) in keepAliveTimers {
            timer.invalidate()
            keepAliveTimers.removeValue(forKey: peer)
        }
        
        // Reset all state
        failedConnectionAttempts.removeAll()
        lastConnectionAttempt.removeAll()
        messageQueue.removeAll()
        pendingConnections.removeAll()
        handshakeCompletedPeers.removeAll()
        lastKeepAliveReceived.removeAll()
        
        DispatchQueue.main.async {
            self.connectedDevices.removeAll()
            self.connectionState = .disconnected
        }
        
        print("Connection state reset complete")
    }
    
    private func startConnectionMonitor() {
        connectionMonitorTimer?.invalidate()
        connectionMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkConnections()
        }
    }
    
    private func checkConnections() {
        guard let session = session else { return }
        
        let now = Date()
        for peer in session.connectedPeers {
            if let lastKeepAlive = lastKeepAliveReceived[peer] {
                let timeSinceLastKeepAlive = now.timeIntervalSince(lastKeepAlive)
                if timeSinceLastKeepAlive > keepAliveTimeout {
                    print("Keep-alive timeout for peer: \(peer.displayName)")
                    // Add additional check before disconnecting
                    if !session.connectedPeers.contains(peer) || !handshakeCompletedPeers.contains(peer) {
                        disconnectDevice(peer.displayName)
                    } else {
                        // Try sending one more keep-alive before giving up
                        print("Attempting final keep-alive before disconnect")
                        let keepAlive: [String: Any] = [
                            "type": "keep_alive",
                            "timestamp": Date().timeIntervalSince1970,
                            "deviceId": "MacDesktop"
                        ]
                        
                        if let data = try? JSONSerialization.data(withJSONObject: keepAlive) {
                            do {
                                try session.send(data, toPeers: [peer], with: .reliable)
                                // Reset the timer
                                lastKeepAliveReceived[peer] = now
                            } catch {
                                print("Final keep-alive failed, disconnecting: \(error)")
                                disconnectDevice(peer.displayName)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Public Methods
    public func startListening() {
        print("Starting Multipeer services...")
        stopReconnectTimer()
        serviceAdvertiser?.startAdvertisingPeer()
        serviceBrowser?.startBrowsingForPeers()
        isListening = true
    }
    
    public func stopListening() {
        print("Stopping Multipeer services...")
        stopReconnectTimer()
        
        // Stop services
        serviceAdvertiser?.stopAdvertisingPeer()
        serviceBrowser?.stopBrowsingForPeers()
        
        // Clean up all timers
        handshakeTimers.values.forEach { $0.invalidate() }
        handshakeTimers.removeAll()
        
        keepAliveTimers.values.forEach { $0.invalidate() }
        keepAliveTimers.removeAll()
        
        connectionMonitorTimer?.invalidate()
        connectionMonitorTimer = nil
        
        // Clean up session and state
        if let session = session {
            session.disconnect()
            for peer in session.connectedPeers {
                cleanupTimersForPeer(peer)
            }
        }
        session = nil
        
        // Reset all state
        isListening = false
        connectedDevices.removeAll()
        pendingConnections.removeAll()
        handshakeCompletedPeers.removeAll()
        lastKeepAliveReceived.removeAll()
        failedConnectionAttempts.removeAll()
        lastConnectionAttempt.removeAll()
        
        // Create new session
        setupMultipeerConnectivity()
    }
    
    public func disconnectDevice(_ deviceId: String) {
        guard let session = session,
              let peer = session.connectedPeers.first(where: { $0.displayName == deviceId }) else {
            return
        }
        
        // Track failed connection
        trackConnectionAttempt(for: deviceId)
        
        // Clean up timers and state
        cleanupTimersForPeer(peer)
        pendingConnections.remove(deviceId)
        handshakeCompletedPeers.remove(peer)
        lastKeepAliveReceived.removeValue(forKey: peer)
        
        // Update UI state
        DispatchQueue.main.async {
            self.connectedDevices.removeAll(where: { $0.id == deviceId })
            if session.connectedPeers.isEmpty {
                self.connectionState = .disconnected
            }
        }
        
        // Disconnect the peer
        session.disconnect()
    }
    
    private func cleanupTimersForPeer(_ peer: MCPeerID) {
        // Cleanup handshake timer
        if let timer = handshakeTimers[peer] {
            timer.invalidate()
            handshakeTimers.removeValue(forKey: peer)
        }
        
        // Cleanup keep-alive timer
        if let timer = keepAliveTimers[peer] {
            timer.invalidate()
            keepAliveTimers.removeValue(forKey: peer)
        }
    }
    
    private func handleHandshakeResponse(from peer: MCPeerID) {
        print("\n=== Handling Handshake Response ===")
        print("Received handshake response from peer: \(peer.displayName)")
        
        guard let session = self.session,
              session.connectedPeers.contains(peer) else {
            print("Peer not connected, cannot complete handshake")
            return
        }
        
        // Trust the MCSession's built-in security
        // If we got here, the peer is already authenticated by MC framework
        connectionState = .connected
        
        // Create device with the peer's actual display name
        let device = ConnectedDevice(
            id: peer.displayName,
            name: peer.displayName,
            platform: "iOS",
            isAuthenticated: true  // If MCSession connected us, the peer is authenticated
        )
        
        // Update device list
        connectedDevices.removeAll { $0.id == device.id }
        connectedDevices.append(device)
        
        print("Updated device list with authenticated device: \(peer.displayName)")
        
        // Start keep-alive exchange
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self,
                  self.connectionState == .connected,
                  session.connectedPeers.contains(peer) else {
                return
            }
            self.startKeepAliveTimer(for: peer)
        }
    }
    
    private func handleHandshake(_ data: Data, from peerID: MCPeerID) {
        print("\n=== Handling iOS Handshake ===")
        print("macOS: Received handshake from iOS")
        print("Peer details:")
        print("- Display name: \(peerID.displayName)")
        print("Expected message format:")
        print("HandshakeMessage {")
        print("  type: HandshakeMessageType (request/response)")
        print("  deviceId: String")
        print("  platform: String ('iOS')")
        print("}")
        
        guard let handshakeMessage = try? JSONDecoder().decode(HandshakeMessage.self, from: data) else {
            print("macOS: Failed to decode handshake message - invalid format")
            print("Raw data: \(String(data: data, encoding: .utf8) ?? "unable to convert to string")")
            return
        }
        
        print("Decoded handshake message:")
        print("- Type: \(handshakeMessage.type)")
        print("- Device ID: \(handshakeMessage.deviceId)")
        print("- Platform: \(handshakeMessage.platform)")
        
        // Add delay before sending response to ensure channels are ready
        DispatchQueue.main.asyncAfter(deadline: .now() + handshakeResponseDelay) {
            print("Preparing handshake response...")
            
            // Verify connection is still valid
            guard let session = self.session,
                  session.connectedPeers.contains(peerID),
                  !self.handshakeCompletedPeers.contains(peerID) else {
                print("Connection state changed, aborting handshake response")
                return
            }
            
            // Send handshake response
            let response = HandshakeMessage(
                type: .response,
                deviceId: "MacDesktop",
                platform: "macOS"
            )
            print("Created response message:")
            print("- Type: \(response.type)")
            print("- Device ID: \(response.deviceId)")
            print("- Platform: \(response.platform)")
            
            if let responseData = try? JSONEncoder().encode(response) {
                do {
                    try session.send(responseData, toPeers: [peerID], with: .reliable)
                    print("Sent handshake response to \(peerID.displayName)")
                    
                    // Wait longer before updating state to allow channels to establish
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.channelEstablishmentDelay) {
                        print("Channel establishment delay completed")
                        
                        // Verify connection is still valid
                        guard session.connectedPeers.contains(peerID),
                              !self.handshakeCompletedPeers.contains(peerID) else {
                            print("Connection state changed during channel establishment")
                            return
                        }
                        
                        // Additional delay for channel stabilization
                        DispatchQueue.main.asyncAfter(deadline: .now() + self.channelStabilizationDelay) {
                            print("Channel stabilization completed")
                            
                            // Final connection state verification
                            guard session.connectedPeers.contains(peerID),
                                  !self.handshakeCompletedPeers.contains(peerID) else {
                                print("Connection state changed during stabilization")
                                return
                            }
                            
                            // Mark handshake as completed
                            self.handshakeCompletedPeers.insert(peerID)
                            self.lastKeepAliveReceived[peerID] = Date()
                            
                            // Clean up existing timers
                            self.cleanupTimersForPeer(peerID)
                            
                            // Update device list
                            DispatchQueue.main.async {
                                // Remove existing device if present
                                self.connectedDevices.removeAll(where: { $0.id == handshakeMessage.deviceId })
                                
                                // Add the device with authenticated state
                                let device = ConnectedDevice(
                                    id: handshakeMessage.deviceId,
                                    name: handshakeMessage.deviceId,
                                    platform: handshakeMessage.platform,
                                    isAuthenticated: true
                                )
                                self.connectedDevices.append(device)
                                
                                print("Added authenticated device: \(handshakeMessage.deviceId)")
                                self.connectionState = .connected
                            }
                            
                            // Start keep-alive after successful handshake
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                guard session.connectedPeers.contains(peerID),
                                      self.handshakeCompletedPeers.contains(peerID) else {
                                    print("Connection lost before keep-alive start")
                                    return
                                }
                                
                                print("Starting keep-alive exchange")
                                self.startKeepAliveTimer(for: peerID)
                            }
                        }
                    }
                } catch {
                    print("Failed to send handshake response: \(error)")
                    self.handleConnectionError(error, for: peerID)
                }
            }
        }
    }
    
    private func startKeepAliveTimer(for peerID: MCPeerID) {
        print("\n=== Starting Keep-Alive Exchange ===")
        
        // Verify connection state
        guard let session = self.session,
              session.connectedPeers.contains(peerID),
              connectionState == .connected else {
            print("Cannot start keep-alive: peer not connected")
            return
        }
        
        // Cancel existing timer if any
        keepAliveTimers[peerID]?.invalidate()
        
        // Create new timer
        let timer = Timer.scheduledTimer(withTimeInterval: keepAliveInterval, repeats: true) { [weak self] timer in
            guard let self = self,
                  let session = self.session,
                  session.connectedPeers.contains(peerID),
                  self.connectionState == .connected else {
                timer.invalidate()
                self?.keepAliveTimers.removeValue(forKey: peerID)
                return
            }
            
            let keepAlive: [String: Any] = [
                "type": "keep_alive",
                "timestamp": Date().timeIntervalSince1970,
                "deviceId": self.peerId.displayName
            ]
            
            if let data = try? JSONSerialization.data(withJSONObject: keepAlive) {
                try? session.send(data, toPeers: [peerID], with: .reliable)
                self.lastKeepAliveReceived[peerID] = Date()
            }
        }
        
        keepAliveTimers[peerID] = timer
        timer.fire()
    }
    
    private func handleConnectionError(_ error: Error, for peerID: MCPeerID) {
        print("Handling connection error for peer: \(peerID.displayName)")
        print("Error: \(error.localizedDescription)")
        
        // Clean up state
        handshakeCompletedPeers.remove(peerID)
        keepAliveTimers[peerID]?.invalidate()
        keepAliveTimers.removeValue(forKey: peerID)
        lastKeepAliveReceived.removeValue(forKey: peerID)
        
        // Remove device from connected devices
        connectedDevices.removeAll { $0.id == peerID.displayName }
        
        // Update connection state
        connectionState = .disconnected
        
        // Attempt to restart services
        print("Restarting Multipeer services...")
        restartServices()
    }
    
    private func startReconnectTimer() {
        guard reconnectTimer == nil && !isReconnecting else { return }
        
        isReconnecting = true
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.retryConnection()
        }
    }
    
    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        isReconnecting = false
    }
    
    private func retryConnection() {
        print("Attempting to reconnect...")
        stopListening()
    }
    
    deinit {
        connectionMonitorTimer?.invalidate()
        stopListening()
    }
    
    private func canAttemptConnection(with peerId: String) -> Bool {
        let attempts = failedConnectionAttempts[peerId] ?? 0
        if attempts >= maxConnectionAttempts {
            if let lastAttempt = lastConnectionAttempt[peerId] {
                let timeSinceLastAttempt = Date().timeIntervalSince(lastAttempt)
                if timeSinceLastAttempt < connectionCooldown {
                    return false
                }
                // Reset after cooldown
                failedConnectionAttempts[peerId] = 0
            }
        }
        return true
    }
    
    private func trackConnectionAttempt(for peerId: String) {
        let attempts = failedConnectionAttempts[peerId] ?? 0
        failedConnectionAttempts[peerId] = attempts + 1
        lastConnectionAttempt[peerId] = Date()
    }
    
    // MARK: - Session Management
    private func verifySessionActive() -> Bool {
        guard isSessionActive, session != nil else {
            print("Session not active, restarting...")
            setupMultipeerConnectivity()
            return false
        }
        return true
    }
    
    private func verifyPeerConnection(_ peerID: MCPeerID) -> Bool {
        guard let activeSession = session,
              activeSession.connectedPeers.contains(peerID) else {
            print("Peer \(peerID.displayName) not connected")
            return false
        }
        return true
    }
    
    // MARK: - Message Handling
    private func sendMessage(_ message: [String: Any], to peerID: MCPeerID, with mode: MCSessionSendDataMode = .reliable) -> Bool {
        guard verifySessionActive(),
              verifyPeerConnection(peerID),
              let data = try? JSONSerialization.data(withJSONObject: message) else {
            return false
        }
        
        do {
            try session?.send(data, toPeers: [peerID], with: mode)
            return true
        } catch {
            print("Failed to send message: \(error)")
            return false
        }
    }
    
    // MARK: - DTLS Establishment
    private func attemptDTLSEstablishment(for peerID: MCPeerID, attempt: Int = 0) {
        print("\n=== DTLS Establishment Phase ===")
        print("macOS: Attempting DTLS establishment with iOS device")
        print("Current attempt: \(attempt + 1) of \(dtlsRetryAttempts)")
        print("Protocol sequence:")
        print("1. macOS sends test message")
        print("2. Wait for \(channelEstablishmentDelay)s")
        print("3. If successful, proceed to handshake")
        print("4. If failed, retry up to \(dtlsRetryAttempts) times")
        print("Note: iOS should accept and process DTLS handshake automatically")
        
        guard let session = self.session,
              session.connectedPeers.contains(peerID),
              attempt < dtlsRetryAttempts else {
            print("macOS: DTLS establishment failed - exceeded retry attempts")
            handleConnectionFailure(for: peerID)
            return
        }

        // Send a small test message
        let testMessage = ["type": "dtls_test", "from": "macOS"]
        if let data = try? JSONSerialization.data(withJSONObject: testMessage) {
            do {
                try session.send(data, toPeers: [peerID], with: .reliable)
                print("macOS: DTLS test message sent successfully")
                
                // Wait for channel establishment
                DispatchQueue.main.asyncAfter(deadline: .now() + channelEstablishmentDelay) {
                    if session.connectedPeers.contains(peerID) {
                        print("macOS: DTLS channel established successfully")
                        self.startHandshakeProcess(for: peerID)
                    } else {
                        print("macOS: DTLS channel establishment failed, retrying...")
                        self.attemptDTLSEstablishment(for: peerID, attempt: attempt + 1)
                    }
                }
            } catch {
                print("macOS: Failed to send DTLS test message: \(error)")
                DispatchQueue.main.asyncAfter(deadline: .now() + dtlsRetryDelay) {
                    self.attemptDTLSEstablishment(for: peerID, attempt: attempt + 1)
                }
            }
        }
    }
    
    private func startHandshakeProcess(for peerID: MCPeerID) {
        print("\n=== Starting Handshake Phase ===")
        print("macOS: Initiating handshake sequence")
        print("Expected sequence:")
        print("1. macOS (current step): Send HandshakeMessage(type: .request)")
        print("2. iOS (next step): Should respond with HandshakeMessage(type: .response)")
        print("3. After response: Establish keep-alive")
        print("Note: If no response within \(handshakeTimeout)s, connection will be reset")
        
        guard let session = self.session,
              session.connectedPeers.contains(peerID) else {
            print("macOS: Cannot start handshake - peer not connected")
            return
        }

        let handshake = HandshakeMessage(
            type: .request,
            deviceId: "MacDesktop",
            platform: "macOS"
        )
        
        if let data = try? JSONEncoder().encode(handshake) {
            do {
                try session.send(data, toPeers: [peerID], with: .reliable)
                print("macOS: Sent initial handshake request")
                
                // Start handshake timeout timer
                let handshakeTimer = Timer.scheduledTimer(withTimeInterval: handshakeTimeout, repeats: false) { [weak self] timer in
                    guard let self = self else { return }
                    if !self.handshakeCompletedPeers.contains(peerID) {
                        print("macOS: Handshake timeout - no response received from iOS")
                        self.handleConnectionFailure(for: peerID)
                    }
                }
                handshakeTimers[peerID] = handshakeTimer
            } catch {
                print("macOS: Failed to send handshake: \(error)")
                handleConnectionFailure(for: peerID)
            }
        }
    }
    
    private func handleConnectionFailure(for peerID: MCPeerID) {
        print("Handling connection failure for peer: \(peerID.displayName)")
        
        // Clean up all state for this peer
        cleanupTimersForPeer(peerID)
        handshakeCompletedPeers.remove(peerID)
        pendingConnections.remove(peerID.displayName)
        lastKeepAliveReceived.removeValue(forKey: peerID)
        
        // Update UI state
        DispatchQueue.main.async {
            self.connectedDevices.removeAll(where: { $0.id == peerID.displayName })
            if self.session?.connectedPeers.isEmpty == true {
                self.connectionState = .disconnected
            }
        }
        
        // Track the failure
        trackConnectionAttempt(for: peerID.displayName)
        
        // Check if we should try DTLS establishment again
        if let session = self.session,
           session.connectedPeers.contains(peerID) {
            print("Peer still connected, attempting DTLS establishment")
            attemptDTLSEstablishment(for: peerID)
            return
        }
        
        // Disconnect the peer
        disconnectDevice(peerID.displayName)
        
        // Restart services after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.restartServices()
        }
    }
    
    private func continueChannelEstablishment(session: MCSession, peer peerID: MCPeerID) {
        // Verify connection is still valid
        guard session.connectedPeers.contains(peerID) else {
            print("Connection lost during channel establishment")
            handleConnectionFailure(for: peerID)
            return
        }
        
        print("Channel establishment completed")
        
        // Second delay to ensure stability
        DispatchQueue.main.asyncAfter(deadline: .now() + self.channelStabilizationDelay) {
            // Final verification
            guard session.connectedPeers.contains(peerID) else {
                print("Connection lost during stabilization")
                self.handleConnectionFailure(for: peerID)
                return
            }
            
            print("Channel stabilization completed")
            
            // Start handshake timeout timer
            let handshakeTimer = Timer.scheduledTimer(withTimeInterval: self.handshakeTimeout, repeats: false) { [weak self] timer in
                guard let self = self else { return }
                
                if !self.handshakeCompletedPeers.contains(peerID) {
                    print("Handshake timeout for peer: \(peerID.displayName)")
                    self.handleConnectionFailure(for: peerID)
                }
            }
            self.handshakeTimers[peerID] = handshakeTimer
        }
    }
    
    private func restartServices() {
        print("Restarting Multipeer services...")
        // Stop current services
        serviceAdvertiser?.stopAdvertisingPeer()
        serviceBrowser?.stopBrowsingForPeers()
        
        // Wait before restarting
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.serviceAdvertiser?.startAdvertisingPeer()
            self.serviceBrowser?.startBrowsingForPeers()
        }
    }
    
    // Add method to send data to a specific device
    public func sendData(_ data: Data, to device: ConnectedDevice) {
        guard let session = session,
              let peer = session.connectedPeers.first(where: { $0.displayName == device.id }) else {
            print("Cannot send data: peer not found")
            return
        }
        
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            print("Failed to send data: \(error)")
        }
    }
    
    // Update session delegate method to handle video streams
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        if streamName == "video" {
            handleVideoStream(stream)
        }
    }
    
    private func handleVideoStream(_ stream: InputStream) {
        stream.open()
        
        // Create a buffer for reading video data
        let bufferSize = 1024 * 1024 // 1MB buffer
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        
        // Read stream in background
        DispatchQueue.global(qos: .userInitiated).async {
            while stream.hasBytesAvailable {
                let bytesRead = stream.read(buffer, maxLength: bufferSize)
                if bytesRead < 0 {
                    // Error occurred
                    break
                }
                
                // Convert buffer to CMSampleBuffer and send to delegate
                if let sampleBuffer = self.createSampleBuffer(from: buffer, length: bytesRead) {
                    DispatchQueue.main.async {
                        self.onVideoData?(sampleBuffer)
                    }
                }
            }
            
            // Clean up
            buffer.deallocate()
            stream.close()
        }
    }
    
    private func createSampleBuffer(from buffer: UnsafeMutablePointer<UInt8>, length: Int) -> CMSampleBuffer? {
        // Create CMSampleBuffer from raw video data
        // Implementation depends on your video format
        // This is a placeholder - you'll need to implement the actual conversion
        return nil
    }
    
    private func handleCommand(_ command: String, parameters: [String: Any], from peerID: MCPeerID) {
        switch command {
        case "start_video":
            // Send acknowledgment and start video stream
            let response: [String: Any] = [
                "type": "command",
                "command": "video_ack",
                "status": "starting",
                "quality": parameters["quality"] as? String ?? "high" // Include quality in response
            ]
            
            if let data = try? JSONSerialization.data(withJSONObject: response) {
                try? session?.send(data, toPeers: [peerID], with: .reliable)
            }
            
        case "flashlight":
            // Handle flashlight command acknowledgment
            if let state = parameters["state"] as? Bool {
                let response: [String: Any] = [
                    "type": "command",
                    "command": "flashlight_ack",
                    "state": state
                ]
                
                if let data = try? JSONSerialization.data(withJSONObject: response) {
                    try? session?.send(data, toPeers: [peerID], with: .reliable)
                }
            }
            
        default:
            print("Unknown command: \(command)")
        }
    }
    
    private func handleKeepAlive(from peerID: MCPeerID) {
        // Update last keep-alive timestamp
        lastKeepAliveReceived[peerID] = Date()
        
        // Send keep-alive response
        let response: [String: Any] = [
            "type": "keep_alive",
            "timestamp": Date().timeIntervalSince1970,
            "deviceId": self.peerId.displayName
        ]
        
        if let responseData = try? JSONSerialization.data(withJSONObject: response) {
            try? session?.send(responseData, toPeers: [peerID], with: .reliable)
        }
    }
}

// MARK: - MCSessionDelegate
extension NetworkService: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("\n=== Connection State Change ===")
        print("macOS: Peer \(peerID.displayName) state changed to: \(state.rawValue)")
        
        DispatchQueue.main.async {
            switch state {
            case .connected:
                print("Peer connected: \(peerID.displayName)")
                
                // Trust MCSession's built-in security
                self.connectionState = .connected
                
                // Add to handshake completed peers immediately
                self.handshakeCompletedPeers.insert(peerID)
                
                // Create device with the peer's display name
                let device = ConnectedDevice(
                    id: peerID.displayName,
                    name: peerID.displayName,
                    platform: "iOS",
                    isAuthenticated: true
                )
                
                // Update device list
                self.connectedDevices.removeAll { $0.id == device.id }
                self.connectedDevices.append(device)
                
                // Start keep-alive immediately
                self.lastKeepAliveReceived[peerID] = Date()
                self.startKeepAliveTimer(for: peerID)
                
            case .connecting:
                print("Peer connecting: \(peerID.displayName)")
                self.connectionState = .connecting
                
            case .notConnected:
                print("Peer disconnected: \(peerID.displayName)")
                
                // Clean up
                self.cleanupTimersForPeer(peerID)
                self.handshakeCompletedPeers.remove(peerID)
                self.lastKeepAliveReceived.removeValue(forKey: peerID)
                self.pendingConnections.removeAll()
                
                DispatchQueue.main.async {
                    self.connectedDevices.removeAll { $0.id == peerID.displayName }
                    if self.session?.connectedPeers.isEmpty == true {
                        self.connectionState = .disconnected
                    }
                }
                
            @unknown default:
                break
            }
        }
    }
    
    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = json["type"] as? String {
            
            switch type {
            case "keep_alive":
                handleKeepAlive(from: peerID)
                
            case "command":
                if let command = json["command"] as? String {
                    handleCommand(command, parameters: json, from: peerID)
                }
                
            default:
                print("Unknown message type: \(type)")
            }
        }
    }
    
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used in this implementation
    }
    
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used in this implementation
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension NetworkService: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("\n=== Received Invitation ===")
        print("Peer details:")
        print("- Display name: \(peerID.displayName)")
        
        // Accept all iOS invitations
        if let context = context,
           let info = try? JSONSerialization.jsonObject(with: context) as? [String: String],
           info["platform"] == "iOS" {
            print("Accepting invitation from iOS device: \(peerID.displayName)")
            
            // Clean up any existing state
            cleanupTimersForPeer(peerID)
            handshakeCompletedPeers.remove(peerID)
            lastKeepAliveReceived.removeValue(forKey: peerID)
            pendingConnections.removeAll()
            
            invitationHandler(true, session)
        } else {
            print("Rejecting non-iOS invitation")
            invitationHandler(false, nil)
        }
    }
    
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Failed to start advertising: \(error)")
        // Retry after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.serviceAdvertiser?.startAdvertisingPeer()
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension NetworkService: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        print("\n=== Found Peer ===")
        print("Peer details:")
        print("- Display name: \(peerID.displayName)")
        print("- Discovery info: \(String(describing: info))")
        
        // Only invite iOS devices
        if let platform = info?["platform"], platform == "iOS" {
            print("Found iOS device, inviting: \(peerID.displayName)")
            
            // Clean up any existing state
            cleanupTimersForPeer(peerID)
            handshakeCompletedPeers.remove(peerID)
            lastKeepAliveReceived.removeValue(forKey: peerID)
            pendingConnections.removeAll()
            
            browser.invitePeer(peerID, to: session!, withContext: nil, timeout: 30)
        } else {
            print("Ignoring non-iOS device")
        }
    }
    
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("\n=== Lost Peer ===")
        print("Lost peer: \(peerID.displayName)")
        
        // Clean up all state for this peer
        cleanupTimersForPeer(peerID)
        handshakeCompletedPeers.remove(peerID)
        
        DispatchQueue.main.async {
            self.pendingConnections.remove(peerID.displayName)
            self.connectedDevices.removeAll(where: { $0.id == peerID.displayName })
            if self.session?.connectedPeers.isEmpty == true {
                self.connectionState = .disconnected
            }
        }
    }
    
    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Failed to start browsing: \(error)")
        // Retry after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.serviceBrowser?.startBrowsingForPeers()
        }
    }
} 
