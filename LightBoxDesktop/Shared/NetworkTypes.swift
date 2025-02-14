import Foundation

public enum NetworkConnectionState: Equatable {
    case disconnected
    case connecting
    case preparing
    case ready
    case waiting(Error)
    case failed(Error)
    case cancelled
    case connected
    
    public static func == (lhs: NetworkConnectionState, rhs: NetworkConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.preparing, .preparing),
             (.ready, .ready),
             (.cancelled, .cancelled),
             (.connected, .connected):
            return true
        case (.waiting(let lhsError), .waiting(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

public enum AuthenticationState {
    case notAuthenticated
    case authenticating
    case authenticated
    case failed(String)
}

public struct DeviceIdentifier {
    public let platform: String
    public let deviceName: String
    public let uuid: String
    
    public var formatted: String {
        return "\(platform)_\(deviceName)_\(uuid)"
    }
    
    public var displayName: String {
        return deviceName
    }
    
    public static func parse(_ identifier: String) -> DeviceIdentifier? {
        let components = identifier.split(separator: "_")
        guard components.count == 3 else { return nil }
        return DeviceIdentifier(
            platform: String(components[0]),
            deviceName: String(components[1]),
            uuid: String(components[2])
        )
    }
    
    public static func validate(_ identifier: String) -> Bool {
        return parse(identifier) != nil
    }
    
    #if os(iOS)
    public static func current() -> DeviceIdentifier {
        return DeviceIdentifier(
            platform: "iOS",
            deviceName: UIDevice.current.name,
            uuid: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        )
    }
    #elseif os(macOS)
    public static func current() -> DeviceIdentifier {
        return DeviceIdentifier(
            platform: "macOS",
            deviceName: "MacDesktop",
            uuid: UUID().uuidString
        )
    }
    #endif
}

public struct ConnectedDevice: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let platform: String
    public var isAuthenticated: Bool
    
    public var identifier: DeviceIdentifier? {
        return DeviceIdentifier.parse(id)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: ConnectedDevice, rhs: ConnectedDevice) -> Bool {
        lhs.id == rhs.id
    }
    
    public init(id: String, name: String, platform: String, isAuthenticated: Bool = false) {
        self.id = id
        self.name = name
        self.platform = platform
        self.isAuthenticated = isAuthenticated
    }
    
    public init(identifier: DeviceIdentifier, isAuthenticated: Bool = false) {
        self.id = identifier.formatted
        self.name = identifier.deviceName
        self.platform = identifier.platform
        self.isAuthenticated = isAuthenticated
    }
} 