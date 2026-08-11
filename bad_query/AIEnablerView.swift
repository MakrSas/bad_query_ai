import SwiftUI
import WebKit

private let mgPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
private let mgDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/"

struct DeviceProfile: Identifiable {
    let id: String
    let name: String
    let model: String
    let hardware: String
    let cpu: String
}

private let deviceProfiles: [DeviceProfile] = [
    DeviceProfile(id: "15pro", name: "iPhone 15 Pro", model: "iPhone16,1", hardware: "D83AP", cpu: "t8130"),
    DeviceProfile(id: "15promax", name: "iPhone 15 Pro Max", model: "iPhone16,2", hardware: "D84AP", cpu: "t8130"),
    DeviceProfile(id: "16", name: "iPhone 16", model: "iPhone17,3", hardware: "D47AP", cpu: "t8140"),
    DeviceProfile(id: "16pro", name: "iPhone 16 Pro", model: "iPhone17,1", hardware: "D93AP", cpu: "t8140"),
    DeviceProfile(id: "16promax", name: "iPhone 16 Pro Max", model: "iPhone17,2", hardware: "D94AP", cpu: "t8140"),
]

// MobileGestalt keys
private let kAICapability = "A62OafQ85EJAiiqKn4agtg"
private let kProductType = "h9jDsbgj7xIVeIQ8S3/X3Q"
private let kHardwareModel = "oYicEKzVTz4/CxxE05pEgQ"
private let kCPUChip = "5pYKlGnYYBzGvAlIU8RjEQ"

struct AIEnablerView: View {
    @State private var log = "Apple Intelligence Enabler\nSpoofs device model + sets AI key"
    @State private var isWorking = false
    @State private var showRespring = false
    @State private var showRevertConfirm = false
    @State private var selectedProfile = "15pro"

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    Section("Device Spoof") {
                        Picker("Spoof as", selection: $selectedProfile) {
                            ForEach(deviceProfiles) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        Text("Spoofs model/hardware/CPU so eligibilityd thinks your device natively supports Apple Intelligence.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Apple Intelligence") {
                        Button("Enable Apple Intelligence") {
                            isWorking = true
                            enableAI()
                            isWorking = false
                        }
                        .disabled(isWorking)

                        Button("Check Status") {
                            checkStatus()
                        }
                    }

                    Section("Tools") {
                        Button("Respring") {
                            showRespring = true
                        }

                        Button("Revert MobileGestalt") {
                            showRevertConfirm = true
                        }
                        .foregroundStyle(.red)
                    }

                    Section("Log") {
                        ScrollView {
                            Text(log)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 280)

                        Button("Clear") {
                            log = "Apple Intelligence Enabler"
                        }
                    }
                }

                if showRespring {
                    RespringCrashView()
                        .ignoresSafeArea()
                }
            }
            .navigationTitle("AI Enabler")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Revert MobileGestalt?", isPresented: $showRevertConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Revert", role: .destructive) { revertMG() }
            } message: {
                Text("This restores MobileGestalt from backup. Reboot after reverting.")
            }
        }
    }

    // MARK: - Logging

    func appendLog(_ msg: String) {
        log.append("\n\(msg)")
    }

    // MARK: - Sandbox helpers

    func bqErrorString(_ code: Int64) -> String {
        switch code {
        case -1: return "failed to resolve functions"
        case -2: return "failed to create sandbox query"
        case -3: return "outside containermanager sandbox"
        case -4: return "kernel rejected sandbox query"
        case -5: return "asprintf failed"
        case -254: return "file not found (lstat)"
        case -255: return "not absolute path"
        default: return "unknown error \(code)"
        }
    }

    func acquireSandbox(_ path: String, label: String, create: Bool = false) -> Int64 {
        var pathC = path.utf8CString.map { Int8($0) }
        let handle = bad_query(&pathC, create, nil, false)
        if handle >= 0 {
            appendLog("[\(label)] sandbox OK (handle: \(handle))")
        } else {
            appendLog("[\(label)] sandbox FAILED: \(bqErrorString(handle))")
        }
        return handle
    }

    // MARK: - Enable AI

    func enableAI() {
        appendLog("--- enabling Apple Intelligence ---")

        guard let profile = deviceProfiles.first(where: { $0.id == selectedProfile }) else {
            appendLog("ERROR: no profile selected")
            return
        }
        appendLog("Spoofing as: \(profile.name) (\(profile.model))")

        let ok = applyMobileGestalt(profile: profile)

        appendLog("--- done ---")
        if ok {
            appendLog("MobileGestalt modified successfully!")
            appendLog("Tap Respring to apply changes.")
            appendLog("After respring, wait for AI assets to download.")
        } else {
            appendLog("Failed — check log above.")
        }
    }

    // MARK: - MobileGestalt

    func applyMobileGestalt(profile: DeviceProfile) -> Bool {
        appendLog("[gestalt] modifying MobileGestalt...")
        let handle = acquireSandbox(mgDir, label: "gestalt")
        guard handle >= 0 else { return false }
        defer { bad_query_release(handle) }

        let mgURL = URL(fileURLWithPath: mgPath)

        guard let dict = NSMutableDictionary(contentsOf: mgURL) else {
            appendLog("[gestalt] FAILED: cannot read plist")
            return false
        }

        // backup before first modification
        let backupURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        let savedPath = backupURL.appendingPathComponent("SavedGestalt.plist")
        if !FileManager.default.fileExists(atPath: savedPath.path) {
            do {
                try FileManager.default.copyItem(at: mgURL, to: savedPath)
                appendLog("[gestalt] backup saved")
            } catch {
                appendLog("[gestalt] warning: backup failed: \(error.localizedDescription)")
            }
        }

        let cacheExtra = dict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()

        // AI capability key
        cacheExtra[kAICapability] = 1
        appendLog("[gestalt] set AI key = 1")

        // Device model spoof
        cacheExtra[kProductType] = profile.model
        appendLog("[gestalt] set ProductType = \(profile.model)")

        cacheExtra[kHardwareModel] = profile.hardware
        appendLog("[gestalt] set HardwareModel = \(profile.hardware)")

        cacheExtra[kCPUChip] = profile.cpu
        appendLog("[gestalt] set CPUChip = \(profile.cpu)")

        dict["CacheExtra"] = cacheExtra

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            let tempURL = mgURL.deletingLastPathComponent()
                .appendingPathComponent(".\(mgURL.lastPathComponent).\(UUID().uuidString).tmp")
            try data.write(to: tempURL, options: [.withoutOverwriting])
            defer { try? FileManager.default.removeItem(at: tempURL) }

            if FileManager.default.fileExists(atPath: mgURL.path) {
                _ = try FileManager.default.replaceItemAt(mgURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: mgURL)
            }
            appendLog("[gestalt] plist written OK")
            return true
        } catch {
            appendLog("[gestalt] write FAILED: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Check Status

    func checkStatus() {
        appendLog("--- status ---")

        let mgHandle = acquireSandbox(mgDir, label: "gestalt")
        if mgHandle >= 0 {
            if let dict = NSDictionary(contentsOf: URL(fileURLWithPath: mgPath)),
               let ce = dict["CacheExtra"] as? NSDictionary {
                let aiKey = ce[kAICapability]
                let model = ce[kProductType] as? String ?? "not set"
                let hw = ce[kHardwareModel] as? String ?? "not set"
                let cpu = ce[kCPUChip] as? String ?? "not set"
                appendLog("[gestalt] AI key = \(aiKey ?? "not set")")
                appendLog("[gestalt] ProductType = \(model)")
                appendLog("[gestalt] HardwareModel = \(hw)")
                appendLog("[gestalt] CPUChip = \(cpu)")
            } else {
                appendLog("[gestalt] cannot read plist")
            }
            bad_query_release(mgHandle)
        }

        appendLog("--- done ---")
    }

    // MARK: - Revert MobileGestalt

    func revertMG() {
        appendLog("[revert] restoring MobileGestalt backup...")
        let backupURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("backups/SavedGestalt.plist")

        guard let backupData = try? Data(contentsOf: backupURL) else {
            appendLog("[revert] FAILED: no backup found")
            return
        }

        let handle = acquireSandbox(mgDir, label: "revert")
        guard handle >= 0 else { return }
        defer { bad_query_release(handle) }

        let mgURL = URL(fileURLWithPath: mgPath)
        let tempURL = mgURL.deletingLastPathComponent()
            .appendingPathComponent(".\(mgURL.lastPathComponent).\(UUID().uuidString).tmp")

        do {
            try backupData.write(to: tempURL, options: [.withoutOverwriting])
            defer { try? FileManager.default.removeItem(at: tempURL) }
            _ = try FileManager.default.replaceItemAt(mgURL, withItemAt: tempURL)
            appendLog("[revert] restored! Reboot to apply.")
        } catch {
            appendLog("[revert] FAILED: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    func mergeDict(base: [String: Any], overlay: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in overlay {
            if let overlayDict = value as? [String: Any],
               var baseDict = result[key] as? [String: Any] {
                for (k, v) in overlayDict { baseDict[k] = v }
                result[key] = baseDict
            } else {
                result[key] = value
            }
        }
        return result
    }
}

// MARK: - Respring (WebKit crash, from mond/jailbreak.party)

private let respringHTML = """
<!DOCTYPE html>
<html>
<body>
<iframe id="frame" srcdoc="" sandbox="allow-forms allow-modals allow-orientation-lock allow-pointer-lock allow-popups allow-presentation allow-scripts"></iframe>
<script>
const frame = document.getElementById('frame');
frame.srcdoc = `<html><body><script>
const c = document.createElement('div');
c.style.cssText = 'perspective:1px;perspective-origin:9999999% 9999999%';
document.body.appendChild(c);
for(let i=0;i<500;i++){
  let d=document.createElement('div');
  d.style.cssText='position:absolute;width:100vw;height:100vh;backdrop-filter:blur(100px);-webkit-backdrop-filter:blur(100px);transform:translate3d(100000px,100000px,'+i+'px) rotateY(90deg)';
  c.appendChild(d);
}
setInterval(()=>{
  navigator.share({title:'R',text:'R'.repeat(100000)}).catch(()=>{});
  crypto.getRandomValues(new Uint8Array(1024*1024*10));
},0);
<\\/script></body></html>`;
</script>
</body>
</html>
"""

struct RespringCrashView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        WKWebpagePreferences().allowsContentJavaScript = true
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        wv.loadHTMLString(respringHTML, baseURL: nil)
    }
}
