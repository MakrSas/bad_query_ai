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
    @State private var log = "Apple Intelligence Enabler v3\nPlist + MGNotify + Diagnostics"
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
                    }

                    Section("Apple Intelligence") {
                        Button("Enable AI + Notify") {
                            isWorking = true
                            enableAI()
                            isWorking = false
                        }
                        .disabled(isWorking)

                        Button("Diagnostics") {
                            runDiagnostics()
                        }

                        Button("Scan Containers") {
                            scanContainers()
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
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 320)

                        Button("Clear") {
                            log = "Apple Intelligence Enabler v3"
                        }

                        Button("Copy Log") {
                            UIPasteboard.general.string = log
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
                Text("Restores MobileGestalt from backup. Reboot after.")
            }
        }
    }

    func appendLog(_ msg: String) {
        log.append("\n\(msg)")
    }

    func bqErrorString(_ code: Int64) -> String {
        switch code {
        case -1: return "dlsym failed"
        case -2: return "query_create failed"
        case -3: return "outside container sandbox"
        case -4: return "kernel rejected"
        case -5: return "asprintf failed"
        case -254: return "lstat failed"
        case -255: return "not absolute path"
        default: return "error \(code)"
        }
    }

    func acquireSandbox(_ path: String, label: String, create: Bool = false) -> Int64 {
        var pathC = path.utf8CString.map { Int8($0) }
        let handle = bad_query(&pathC, create, nil, false)
        if handle >= 0 {
            appendLog("[\(label)] sandbox OK (\(handle))")
        } else {
            appendLog("[\(label)] FAIL: \(bqErrorString(handle))")
        }
        return handle
    }

    // MARK: - MGCopyAnswer wrapper

    func mgReadString(_ key: String) -> String? {
        guard let cfVal = mg_copy_answer(key) else { return nil }
        let val = Unmanaged<AnyObject>.fromOpaque(cfVal).takeRetainedValue()
        if let str = val as? String { return str }
        if let num = val as? NSNumber { return num.stringValue }
        return String(describing: val)
    }

    func mgReadBool(_ key: String) -> Bool {
        return mg_get_bool_answer(key)
    }

    // MARK: - Enable AI

    func enableAI() {
        appendLog("=== ENABLE AI ===")

        guard let profile = deviceProfiles.first(where: { $0.id == selectedProfile }) else {
            appendLog("ERROR: no profile")
            return
        }
        appendLog("Target: \(profile.name) (\(profile.model))")

        // Step 1: modify plist
        let plistOK = applyMobileGestalt(profile: profile)
        if !plistOK {
            appendLog("Plist write failed, aborting")
            return
        }

        // Step 2: post Darwin notification to force cache re-read
        appendLog("[notify] posting cache-changed...")
        mg_notify_cache_changed()
        appendLog("[notify] sent com.apple.MobileGestalt.cache-changed")

        // Step 3: verify via MGCopyAnswer
        Thread.sleep(forTimeInterval: 0.5)
        appendLog("[verify] checking MGCopyAnswer...")
        let liveAI = mgReadBool(kAICapability)
        let liveModel = mgReadString(kProductType) ?? "nil"
        let liveCPU = mgReadString(kCPUChip) ?? "nil"
        appendLog("[verify] MGCopyAnswer AI=\(liveAI) model=\(liveModel) cpu=\(liveCPU)")

        appendLog("=== DONE ===")
        appendLog("Tap Respring to apply.")
    }

    // MARK: - MobileGestalt plist

    func applyMobileGestalt(profile: DeviceProfile) -> Bool {
        appendLog("[plist] modifying...")
        let handle = acquireSandbox(mgDir, label: "gestalt")
        guard handle >= 0 else { return false }
        defer { bad_query_release(handle) }

        let mgURL = URL(fileURLWithPath: mgPath)
        guard let dict = NSMutableDictionary(contentsOf: mgURL) else {
            appendLog("[plist] FAIL: can't read")
            return false
        }

        // backup
        let backupURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        let savedPath = backupURL.appendingPathComponent("SavedGestalt.plist")
        if !FileManager.default.fileExists(atPath: savedPath.path) {
            do {
                try FileManager.default.copyItem(at: mgURL, to: savedPath)
                appendLog("[plist] backup saved")
            } catch {
                appendLog("[plist] backup warn: \(error.localizedDescription)")
            }
        }

        let cacheExtra = dict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()

        cacheExtra[kAICapability] = 1
        cacheExtra[kProductType] = profile.model
        cacheExtra[kHardwareModel] = profile.hardware
        cacheExtra[kCPUChip] = profile.cpu

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
            appendLog("[plist] written OK (AI=1, model=\(profile.model), hw=\(profile.hardware), cpu=\(profile.cpu))")
            return true
        } catch {
            appendLog("[plist] FAIL: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Diagnostics

    func runDiagnostics() {
        appendLog("=== DIAGNOSTICS ===")

        // 1. Read plist values
        let mgHandle = acquireSandbox(mgDir, label: "diag")
        if mgHandle >= 0 {
            if let dict = NSDictionary(contentsOf: URL(fileURLWithPath: mgPath)),
               let ce = dict["CacheExtra"] as? NSDictionary {
                appendLog("[plist] AI = \(ce[kAICapability] ?? "nil")")
                appendLog("[plist] ProductType = \(ce[kProductType] ?? "nil")")
                appendLog("[plist] HardwareModel = \(ce[kHardwareModel] ?? "nil")")
                appendLog("[plist] CPUChip = \(ce[kCPUChip] ?? "nil")")
            } else {
                appendLog("[plist] can't read")
            }
            bad_query_release(mgHandle)
        }

        // 2. Read LIVE values via MGCopyAnswer (what the system actually sees)
        appendLog("[live] MGCopyAnswer values:")
        appendLog("[live] AI = \(mgReadBool(kAICapability))")
        appendLog("[live] ProductType = \(mgReadString(kProductType) ?? "nil")")
        appendLog("[live] HardwareModel = \(mgReadString(kHardwareModel) ?? "nil")")
        appendLog("[live] CPUChip = \(mgReadString(kCPUChip) ?? "nil")")

        // 3. Check some other useful keys
        appendLog("[live] DeviceName = \(mgReadString("N/URBF2a9HRr6F0UD3Avhg") ?? "nil")")
        appendLog("[live] BuildVersion = \(mgReadString("qNNddlUK7ByiSMrsapkXDA") ?? "nil")")

        // 4. Check eligibility-related paths
        let eligPaths = [
            "/var/db/eligibilityd/eligibility.plist",
            "/var/db/os_eligibility/eligibility.plist",
            "/var/containers/Data/System/com.apple.eligibilityd/",
        ]
        for p in eligPaths {
            let exists = FileManager.default.fileExists(atPath: p)
            appendLog("[path] \(p) exists=\(exists)")
        }

        appendLog("=== END ===")
    }

    // MARK: - Container Scanner

    func scanContainers() {
        appendLog("=== SCANNING CONTAINERS ===")

        let searchPaths = [
            ("/var/containers/Data/System", "System containers"),
            ("/var/containers/Shared/SystemGroup", "SystemGroup containers"),
        ]

        for (path, label) in searchPaths {
            appendLog("[\(label)] scanning \(path)...")

            let handle = acquireSandbox(path, label: label)
            if handle < 0 {
                // try with create=true
                var pathC = path.utf8CString.map { Int8($0) }
                let h2 = bad_query(&pathC, true, nil, false)
                if h2 >= 0 {
                    appendLog("[\(label)] sandbox OK via create (\(h2))")
                    scanDir(path, label: label)
                    bad_query_release(h2)
                } else {
                    appendLog("[\(label)] can't access, trying bad_query_list...")
                    scanViaList(path, label: label)
                }
            } else {
                scanDir(path, label: label)
                bad_query_release(handle)
            }
        }

        appendLog("=== SCAN DONE ===")
    }

    func scanDir(_ path: String, label: String) {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            appendLog("[\(label)] can't list dir")
            return
        }
        let eligEntries = entries.filter {
            $0.lowercased().contains("eligib") ||
            $0.lowercased().contains("greymatter") ||
            $0.lowercased().contains("intelligence") ||
            $0.lowercased().contains("siri") ||
            $0.lowercased().contains("tridevice")
        }
        if eligEntries.isEmpty {
            appendLog("[\(label)] \(entries.count) entries, none match eligibility/AI")
            // show all for analysis
            for e in entries.prefix(30) {
                appendLog("  \(e)")
            }
            if entries.count > 30 {
                appendLog("  ... and \(entries.count - 30) more")
            }
        } else {
            appendLog("[\(label)] FOUND matches:")
            for e in eligEntries {
                appendLog("  >>> \(e)")
            }
        }
    }

    func scanViaList(_ path: String, label: String) {
        var pathC = path.utf8CString.map { Int8($0) }
        guard let raw = bad_query_list(&pathC, 500000) else {
            appendLog("[\(label)] bad_query_list returned nil")
            return
        }
        let result = String(cString: raw)
        free(raw)
        if result.isEmpty {
            appendLog("[\(label)] no entries found via inode scan")
            return
        }
        let lines = result.split(separator: "\n")
        let eligLines = lines.filter {
            $0.lowercased().contains("eligib") ||
            $0.lowercased().contains("greymatter") ||
            $0.lowercased().contains("intelligence") ||
            $0.lowercased().contains("siri")
        }
        if eligLines.isEmpty {
            appendLog("[\(label)] \(lines.count) entries via inode, none match")
            for l in lines.prefix(20) {
                appendLog("  \(l)")
            }
            if lines.count > 20 {
                appendLog("  ... and \(lines.count - 20) more")
            }
        } else {
            appendLog("[\(label)] FOUND:")
            for l in eligLines {
                appendLog("  >>> \(l)")
            }
        }
    }

    // MARK: - Revert

    func revertMG() {
        appendLog("[revert] restoring backup...")
        let backupURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("backups/SavedGestalt.plist")

        guard let backupData = try? Data(contentsOf: backupURL) else {
            appendLog("[revert] FAIL: no backup")
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
            appendLog("[revert] OK! Reboot to apply.")
        } catch {
            appendLog("[revert] FAIL: \(error.localizedDescription)")
        }
    }
}

// MARK: - Respring

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
