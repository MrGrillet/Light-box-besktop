import Foundation

class LightBoxDesktopApp: ObservableObject {
    @Published var isVirtualCameraInstalled: Bool = false

    func installVirtualCamera(completion: @escaping (Bool, String?) -> Void) {
        print("Starting virtual camera installation...")
        
        // Get the installer package from the bundle
        guard let bundlePath = Bundle.main.resourcePath else {
            completion(false, "Could not locate app bundle")
            return
        }
        
        let installerPath = (bundlePath as NSString).appendingPathComponent("LightBoxCamera.pkg")
        let installerURL = URL(fileURLWithPath: installerPath)
        
        if !FileManager.default.fileExists(atPath: installerPath) {
            print("Installer not found at path: \(installerPath)")
            completion(false, "Installation package not found at \(installerPath)")
            return
        }
        
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/installer")
            process.arguments = [
                "-pkg",
                installerURL.path,
                "-target", "/"
            ]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            let success = process.terminationStatus == 0
            if success {
                DispatchQueue.main.async {
                    self.isVirtualCameraInstalled = true
                }
                completion(true, nil)
            } else {
                completion(false, "Installation failed: \(output)")
            }
        } catch {
            completion(false, error.localizedDescription)
        }
    }
} 