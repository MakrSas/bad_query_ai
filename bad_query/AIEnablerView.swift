import SwiftUI
import WebKit

private let mgPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
private let mgDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/"

// MobileGestalt keys
private let kAICapability = "A62OafQ85EJAiiqKn4agtg"
private let kProductType = "h9jDsbgj7xIVeIQ8S3/X3Q"
private let kHardwareModel = "oYicEKzVTz4/CxxE05pEgQ"
private let kCPUChip = "5pYKlGnYYBzGvAlIU8RjEQ"

struct AIEnablerView: View {
    @State private var log = "AI Enabler v4 — Deep Diagnostics"
    @State private var isWorking = false
    @State private var showRespring = false
    @State private var showRevertConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    Section("Apple Intelligence") {
                        Button("Enable AI (plist + notify)") {
                            isWorking = true
                            enableAI()
                            isWorking = false
                        }
                        .disabled(isWorking)

                        Button("Diagnostics") {
                            runDiagnostics()
                        }
                    }

                    Section("Deep Scan") {
                        Button("Scan Container Metadata") {
                            isWorking = true
                            deepScanContainers()
                            isWorking = false
                        }
                        .disabled(isWorking)

                        Button("Try Eligibility XPC") {
                            tryEligibilityXPC()
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

                        HStack {
                            Button("Clear") { log = "AI Enabler v4" }
                            Spacer()
                            Button("Copy Log") {
                                UIPasteboard.general.string = log
                            }
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
                Text("Restores backup. Reboot after.")
            }
        }
    }

    func appendLog(_ msg: String) {
        log.append("\n\(msg)")
    }

    func bqErr(_ code: Int64) -> String {
        switch code {
        case -1: return "dlsym"
        case -2: return "query_create"
        case -3: return "outside sandbox"
        case -4: return "kernel rejected"
        case -5: return "asprintf"
        case -254: return "lstat"
        case -255: return "not absolute"
        default: return "err(\(code))"
        }
    }

    func sandbox(_ path: String, label: String, create: Bool = false) -> Int64 {
        var pathC = path.utf8CString.map { Int8($0) }
        let h = bad_query(&pathC, create, nil, false)
        if h >= 0 {
            appendLog("[\(label)] sandbox OK (\(h))")
        } else {
            appendLog("[\(label)] FAIL: \(bqErr(h))")
        }
        return h
    }

    // MARK: - MobileGestalt live API

    func mgStr(_ key: String) -> String? {
        guard let cfVal = mg_copy_answer(key) else { return nil }
        let val = Unmanaged<AnyObject>.fromOpaque(cfVal).takeRetainedValue()
        if let s = val as? String { return s }
        if let n = val as? NSNumber { return n.stringValue }
        return String(describing: val)
    }

    func mgBool(_ key: String) -> Bool { mg_get_bool_answer(key) }

    // MARK: - Enable AI

    func enableAI() {
        appendLog("=== ENABLE ===")
        let h = sandbox(mgDir, label: "mg")
        guard h >= 0 else { return }
        defer { bad_query_release(h) }

        let mgURL = URL(fileURLWithPath: mgPath)
        guard let dict = NSMutableDictionary(contentsOf: mgURL) else {
            appendLog("can't read plist"); return
        }

        // backup
        let backDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: backDir, withIntermediateDirectories: true)
        let saved = backDir.appendingPathComponent("SavedGestalt.plist")
        if !FileManager.default.fileExists(atPath: saved.path) {
            try? FileManager.default.copyItem(at: mgURL, to: saved)
            appendLog("backup saved")
        }

        let ce = dict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
        ce[kAICapability] = 1
        // spoof to iPhone 15 Pro
        ce[kProductType] = "iPhone16,1"
        ce[kHardwareModel] = "D83AP"
        ce[kCPUChip] = "t8130"
        dict["CacheExtra"] = ce

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            let tmp = mgURL.deletingLastPathComponent()
                .appendingPathComponent(".\(UUID().uuidString).tmp")
            try data.write(to: tmp, options: [.withoutOverwriting])
            defer { try? FileManager.default.removeItem(at: tmp) }
            if FileManager.default.fileExists(atPath: mgURL.path) {
                _ = try FileManager.default.replaceItemAt(mgURL, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: mgURL)
            }
            appendLog("plist OK: AI=1, model=iPhone16,1")
        } catch {
            appendLog("plist FAIL: \(error.localizedDescription)")
            return
        }

        // notify
        mg_notify_cache_changed()
        appendLog("notify: cache-changed sent")

        // verify
        Thread.sleep(forTimeInterval: 0.5)
        appendLog("live AI=\(mgBool(kAICapability)) model=\(mgStr(kProductType) ?? "nil")")
        appendLog("=== DONE - tap Respring ===")
    }

    // MARK: - Diagnostics

    func runDiagnostics() {
        appendLog("=== DIAG ===")

        // plist
        let h = sandbox(mgDir, label: "mg")
        if h >= 0 {
            if let d = NSDictionary(contentsOf: URL(fileURLWithPath: mgPath)),
               let ce = d["CacheExtra"] as? NSDictionary {
                appendLog("plist AI=\(ce[kAICapability] ?? "nil") model=\(ce[kProductType] ?? "nil") hw=\(ce[kHardwareModel] ?? "nil") cpu=\(ce[kCPUChip] ?? "nil")")
            }
            bad_query_release(h)
        }

        // live
        appendLog("live AI=\(mgBool(kAICapability)) model=\(mgStr(kProductType) ?? "nil") hw=\(mgStr(kHardwareModel) ?? "nil") cpu=\(mgStr(kCPUChip) ?? "nil")")

        // eligibility file
        let eligExists = FileManager.default.fileExists(atPath: "/var/db/eligibilityd/eligibility.plist")
        appendLog("eligibility.plist exists=\(eligExists)")

        // try to READ eligibility plist (might work even without write access)
        if let eligData = try? Data(contentsOf: URL(fileURLWithPath: "/var/db/eligibilityd/eligibility.plist")),
           let eligDict = try? PropertyListSerialization.propertyList(from: eligData, format: nil) as? [String: Any] {
            appendLog("eligibility readable! keys: \(eligDict.keys.sorted().joined(separator: ", "))")
            if let gm = eligDict["OS_ELIGIBILITY_DOMAIN_GREYMATTER"] as? [String: Any] {
                appendLog("GREYMATTER: \(gm)")
            } else {
                appendLog("no GREYMATTER domain")
            }
        } else {
            appendLog("eligibility.plist not readable from sandbox")
        }

        appendLog("=== END ===")
    }

    // MARK: - Deep Container Scan

    func deepScanContainers() {
        appendLog("=== DEEP SCAN ===")
        let basePath = "/var/containers/Data/System"

        let h = sandbox(basePath, label: "sys")
        guard h >= 0 else {
            appendLog("can't access System containers")
            return
        }
        defer { bad_query_release(h) }

        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: basePath) else {
            appendLog("can't list"); return
        }

        appendLog("scanning \(entries.count) containers for metadata...")

        for entry in entries {
            let containerPath = "\(basePath)/\(entry)"
            let metaPaths = [
                "\(containerPath)/.com.apple.containermanagerd.metadata.plist",
                "\(containerPath)/.com.apple.mobile_container_manager.metadata.plist",
            ]

            for metaPath in metaPaths {
                if let metaData = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                   let meta = try? PropertyListSerialization.propertyList(from: metaData, format: nil) as? [String: Any] {
                    let bundleId = meta["MCMMetadataIdentifier"] as? String ?? "?"
                    let cls = meta["MCMMetadataContentClass"] as? Int ?? -1
                    appendLog("  \(entry.prefix(8))... = \(bundleId) (class \(cls))")

                    if bundleId.lowercased().contains("eligib") ||
                       bundleId.lowercased().contains("siri") ||
                       bundleId.lowercased().contains("intelligence") ||
                       bundleId.lowercased().contains("greymatter") ||
                       bundleId.lowercased().contains("assistant") {
                        appendLog("  >>> MATCH: \(bundleId) at \(containerPath)")
                        // try to list contents
                        if let contents = try? FileManager.default.contentsOfDirectory(atPath: containerPath) {
                            appendLog("  contents: \(contents.joined(separator: ", "))")
                        }
                    }
                    break
                }
            }
        }

        // also scan SystemGroup with bad_query_list for deeper entries
        appendLog("scanning SystemGroup for eligibility-related...")
        var sgPath = "/var/containers/Shared/SystemGroup".utf8CString.map { Int8($0) }
        if let raw = bad_query_list(&sgPath, 500000) {
            let result = String(cString: raw)
            free(raw)
            let lines = result.split(separator: "\n")
            for line in lines {
                let l = line.lowercased()
                if l.contains("eligib") || l.contains("greymatter") || l.contains("intelligence") || l.contains("assistant") || l.contains("siri") {
                    appendLog("  >>> \(line)")
                }
            }
            appendLog("SystemGroup: \(lines.count) total entries scanned")
        }

        appendLog("=== DEEP SCAN DONE ===")
    }

    // MARK: - Eligibility XPC

    func tryEligibilityXPC() {
        appendLog("=== ELIGIBILITY PROBES ===")

        // Probe 1: try to read eligibility plist with bad_query
        let eligPath = "/var/db/eligibilityd/eligibility.plist"
        appendLog("[probe1] trying bad_query for eligibility dir...")
        var eligDirC = "/var/db/eligibilityd".utf8CString.map { Int8($0) }
        let h1 = bad_query(&eligDirC, true, nil, false)
        appendLog("[probe1] result: \(h1 >= 0 ? "OK(\(h1))" : bqErr(h1))")
        if h1 >= 0 {
            bad_query_release(h1)
            // try to read/write
            if let data = try? Data(contentsOf: URL(fileURLWithPath: eligPath)) {
                appendLog("[probe1] READ OK! \(data.count) bytes")
            }
        }

        // Probe 2: try via different group identifiers
        let groupIds = [
            "com.apple.eligibilityd",
            "com.apple.os_eligibility",
            "systemgroup.com.apple.eligibilityd",
            "com.apple.daemon.eligibilityd",
            "com.apple.tridevicesetupd",
        ]

        for gid in groupIds {
            var gidC = gid.utf8CString.map { Int8($0) }
            var pathC = eligPath.utf8CString.map { Int8($0) }

            // try class 13 (SharedSystemData) with this group
            let h = bad_query_ex(&pathC, true, &gidC, 13)
            if h >= 0 {
                appendLog("[probe2] \(gid) class=13 OK! handle=\(h)")
                bad_query_release(h)
            }

            // try class 10 (SystemData)
            pathC = eligPath.utf8CString.map { Int8($0) }
            gidC = gid.utf8CString.map { Int8($0) }
            let h2 = bad_query_ex(&pathC, true, &gidC, 10)
            if h2 >= 0 {
                appendLog("[probe2] \(gid) class=10 OK! handle=\(h2)")
                bad_query_release(h2)
            }
        }

        // Probe 3: try MobileAsset eligibility paths
        let assetPaths = [
            "/var/MobileAsset/AssetsV2/com_apple_MobileAsset_OSEligibility",
            "/var/db/os_eligibility",
            "/var/root/Library/Preferences/com.apple.eligibilityd.plist",
            "/var/mobile/Library/Preferences/com.apple.eligibilityd.plist",
        ]
        for p in assetPaths {
            let exists = FileManager.default.fileExists(atPath: p)
            if exists {
                appendLog("[probe3] EXISTS: \(p)")
            }
        }

        // Probe 4: try NSUserDefaults for eligibility
        if let defaults = UserDefaults(suiteName: "com.apple.eligibilityd") {
            let keys = defaults.dictionaryRepresentation().keys
            if !keys.isEmpty {
                appendLog("[probe4] eligibilityd defaults: \(keys.joined(separator: ", "))")
            } else {
                appendLog("[probe4] eligibilityd defaults: empty")
            }
        }

        // Probe 5: try to find eligibility via inode scan of /var/db/
        appendLog("[probe5] inode scan /var/db/eligibilityd...")
        var dbPath = "/var/db/eligibilityd".utf8CString.map { Int8($0) }
        if let raw = bad_query_list(&dbPath, 200000) {
            let result = String(cString: raw)
            free(raw)
            if !result.isEmpty {
                appendLog("[probe5] found: \(result)")
            } else {
                appendLog("[probe5] empty (inode scan can't reach)")
            }
        } else {
            appendLog("[probe5] bad_query_list returned nil")
        }

        appendLog("=== PROBES DONE ===")
    }

    // MARK: - Revert

    func revertMG() {
        appendLog("[revert] restoring...")
        let backupURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("backups/SavedGestalt.plist")
        guard let data = try? Data(contentsOf: backupURL) else {
            appendLog("[revert] no backup"); return
        }
        let h = sandbox(mgDir, label: "revert")
        guard h >= 0 else { return }
        defer { bad_query_release(h) }
        let mgURL = URL(fileURLWithPath: mgPath)
        let tmp = mgURL.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            try data.write(to: tmp, options: [.withoutOverwriting])
            defer { try? FileManager.default.removeItem(at: tmp) }
            _ = try FileManager.default.replaceItemAt(mgURL, withItemAt: tmp)
            appendLog("[revert] OK! Reboot.")
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
