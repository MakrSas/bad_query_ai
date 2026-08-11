import SwiftUI
import WebKit

private let mgPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
private let mgDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/"

private let kAICapability = "A62OafQ85EJAiiqKn4agtg"
private let kProductType = "h9jDsbgj7xIVeIQ8S3/X3Q"
private let kHardwareModel = "oYicEKzVTz4/CxxE05pEgQ"
private let kCPUChip = "5pYKlGnYYBzGvAlIU8RjEQ"

struct AIEnablerView: View {
    @State private var log = "AI Enabler v6 — Feature Flag Attack"
    @State private var isWorking = false
    @State private var showRespring = false
    @State private var showRevertConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    Section("Step 1: MobileGestalt") {
                        Button("Apply MG Spoof") {
                            isWorking = true
                            applyMG()
                            isWorking = false
                        }
                        .disabled(isWorking)
                    }

                    Section("Step 2: Feature Flags") {
                        Button("Probe Private APIs") {
                            probeAPIs()
                        }

                        Button("Set Feature Flags (all methods)") {
                            isWorking = true
                            setFeatureFlags()
                            isWorking = false
                        }
                        .disabled(isWorking)
                    }

                    Section("Step 3: Container Scanner") {
                        Button("Scan System Containers") {
                            isWorking = true
                            scanContainers()
                            isWorking = false
                        }
                        .disabled(isWorking)
                    }

                    Section("Step 4: Apply") {
                        Button("Respring") {
                            showRespring = true
                        }
                    }

                    Section("Diagnostics") {
                        Button("Full Status") {
                            fullStatus()
                        }
                    }

                    Section("Tools") {
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
                            Button("Clear") { log = "AI Enabler v6" }
                            Spacer()
                            Button("Copy") { UIPasteboard.general.string = log }
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
            .alert("Revert?", isPresented: $showRevertConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Revert", role: .destructive) { revertMG() }
            } message: { Text("Reboot after reverting.") }
        }
    }

    func appendLog(_ msg: String) { log.append("\n\(msg)") }

    func bqErr(_ c: Int64) -> String {
        switch c {
        case -1: return "dlsym"; case -2: return "query_create"; case -3: return "outside sandbox"
        case -4: return "kernel rejected"; case -254: return "lstat"; case -255: return "bad path"
        default: return "err(\(c))"
        }
    }

    func sandbox(_ path: String, label: String, create: Bool = false) -> Int64 {
        var p = path.utf8CString.map { Int8($0) }
        let h = bad_query(&p, create, nil, false)
        if h >= 0 { appendLog("[\(label)] sandbox OK") }
        else { appendLog("[\(label)] \(bqErr(h))") }
        return h
    }

    func mgStr(_ key: String) -> String? {
        guard let v = mg_copy_answer(key) else { return nil }
        let o = Unmanaged<AnyObject>.fromOpaque(v).takeRetainedValue()
        if let s = o as? String { return s }
        if let n = o as? NSNumber { return n.stringValue }
        return String(describing: o)
    }

    // MARK: - Step 1: MobileGestalt

    func applyMG() {
        appendLog("=== MG SPOOF ===")
        let h = sandbox(mgDir, label: "mg")
        guard h >= 0 else { return }
        defer { bad_query_release(h) }

        let mgURL = URL(fileURLWithPath: mgPath)
        guard let dict = NSMutableDictionary(contentsOf: mgURL) else {
            appendLog("can't read"); return
        }

        let bdir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: bdir, withIntermediateDirectories: true)
        let saved = bdir.appendingPathComponent("SavedGestalt.plist")
        if !FileManager.default.fileExists(atPath: saved.path) {
            try? FileManager.default.copyItem(at: mgURL, to: saved)
            appendLog("backup saved")
        }

        let ce = dict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
        ce[kAICapability] = 1
        ce[kProductType] = "iPhone16,1"
        ce[kHardwareModel] = "D83AP"
        ce[kCPUChip] = "t8130"
        dict["CacheExtra"] = ce

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            let tmp = mgURL.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
            try data.write(to: tmp, options: [.withoutOverwriting])
            defer { try? FileManager.default.removeItem(at: tmp) }
            if FileManager.default.fileExists(atPath: mgURL.path) {
                _ = try FileManager.default.replaceItemAt(mgURL, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: mgURL)
            }
            appendLog("plist OK: AI=1, iPhone16,1/D83AP/t8130")
        } catch {
            appendLog("FAIL: \(error.localizedDescription)"); return
        }

        mg_notify_cache_changed()
        appendLog("cache notify sent")
        appendLog("live: AI=\(mg_get_bool_answer(kAICapability)) model=\(mgStr(kProductType) ?? "?")")
    }

    // MARK: - Step 2: Feature Flags

    func probeAPIs() {
        appendLog("=== API PROBE ===")
        if let cStr = probe_private_apis() {
            let str = String(cString: cStr)
            for line in str.split(separator: "\n") where !line.isEmpty {
                appendLog(String(line))
            }
            free(cStr)
        } else {
            appendLog("probe returned nil")
        }
        appendLog("=== END ===")
    }

    func setFeatureFlags() {
        appendLog("=== SET FEATURE FLAGS ===")

        let flags: [(String, String)] = [
            ("Siri", "sae_override"),
            ("Siri", "assistant_engine_override"),
            ("SiriUI", "sae"),
        ]

        // Method 1: dlsym override API
        appendLog("[M1] dlsym override...")
        for (sub, flag) in flags {
            let r = ff_try_set(sub, flag, true)
            appendLog("  \(sub).\(flag): \(r == 0 ? "called" : "err(\(r))")")
        }

        // Check after set
        appendLog("[M1] verify...")
        for (sub, flag) in flags {
            let r = ff_check(sub, flag)
            appendLog("  \(sub).\(flag) = \(r == 1 ? "ENABLED" : r == 0 ? "disabled" : "err(\(r))")")
        }

        // Method 2: NSUserDefaults - multiple suites
        appendLog("[M2] NSUserDefaults...")
        let suites = [
            "com.apple.FeatureFlags",
            "com.apple.featureflags",
            ".GlobalPreferences",
            "com.apple.siri",
            "com.apple.Siri",
            "com.apple.assistant.support",
            "com.apple.assistant",
            "com.apple.SiriUI",
            "com.apple.Preferences",
            "com.apple.siriactionsd",
        ]
        for suite in suites {
            guard let d = UserDefaults(suiteName: suite) else { continue }
            for (_, flag) in flags {
                d.set(["Enabled": true], forKey: flag)
                d.set(true, forKey: flag)
            }
            d.set(true, forKey: "SiriCanAccessServerModels")
            d.set(true, forKey: "AssistantEnabled")
            let ok = d.synchronize()
            appendLog("  \(suite): sync=\(ok)")
        }

        // Method 3: CFPreferences global domain
        appendLog("[M3] CFPreferences global domain...")
        for (_, flag) in flags {
            let key = flag as CFString
            CFPreferencesSetValue(key, kCFBooleanTrue, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        appendLog("  global domain synced")

        // Method 4: CFPreferences per-domain
        appendLog("[M4] CFPreferences per-domain...")
        let cfDomains: [CFString] = ["com.apple.siri" as CFString, "com.apple.assistant" as CFString, "com.apple.SiriUI" as CFString]
        for domain in cfDomains {
            for (_, flag) in flags {
                CFPreferencesSetValue(flag as CFString, kCFBooleanTrue, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            }
            CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        appendLog("  3 domains synced")

        // Method 5: Try writing Global.plist directly
        appendLog("[M5] direct plist write...")
        let ffPlist: [String: Any] = [
            "Siri": [
                "sae_override": ["Enabled": true],
                "assistant_engine_override": ["Enabled": true],
            ],
            "SiriUI": [
                "sae": ["Enabled": true],
            ],
        ]
        let ffPaths = [
            "/var/preferences/FeatureFlags/Global.plist",
            "/private/var/preferences/FeatureFlags/Global.plist",
        ]
        for path in ffPaths {
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: ffPlist, format: .xml, options: 0)
                try data.write(to: URL(fileURLWithPath: path))
                appendLog("  \(path): WRITTEN!")
            } catch {
                appendLog("  \(path): \(error.localizedDescription)")
            }
        }

        // Method 6: bad_query traversal to FeatureFlags
        appendLog("[M6] bad_query /var/preferences/FeatureFlags...")
        var ffPathC = "/var/preferences/FeatureFlags".utf8CString.map { Int8($0) }
        let hff = bad_query(&ffPathC, true, nil, false)
        if hff >= 0 {
            appendLog("  sandbox OK! writing...")
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: ffPlist, format: .xml, options: 0)
                try data.write(to: URL(fileURLWithPath: "/var/preferences/FeatureFlags/Global.plist"))
                appendLog("  Global.plist WRITTEN!")
            } catch {
                appendLog("  write failed: \(error.localizedDescription)")
            }
            bad_query_release(hff)
        } else {
            appendLog("  \(bqErr(hff))")
        }

        // Method 7: Darwin notifications
        appendLog("[M7] notifications...")
        let notifs = [
            "com.apple.FeatureFlags.changed",
            "com.apple.siri.configurationChanged",
            "com.apple.assistant.configurationChanged",
            "com.apple.eligibility.inputChanged",
        ]
        for n in notifs {
            post_darwin_notification(n)
        }
        appendLog("  \(notifs.count) notifications posted")

        appendLog("=== FF DONE ===")
    }

    // MARK: - Step 3: Container Scanner

    func scanContainers() {
        appendLog("=== CONTAINER SCAN ===")

        let class12ids = [
            "com.apple.geod",
            "com.apple.siri",
            "com.apple.Siri",
            "com.apple.assistant",
            "com.apple.SiriUI",
            "com.apple.intelligenceplatformd",
            "com.apple.IntelligencePlatform",
            "com.apple.eligibilityd",
            "com.apple.featureflagsd",
            "com.apple.FeatureFlags",
            "com.apple.Preferences",
            "com.apple.mobileassetd",
            "com.apple.triald",
            "com.apple.parsec",
            "com.apple.springboard",
            "com.apple.languageassetd",
            "com.apple.gms",
            "com.apple.siriknowledged",
            "com.apple.coreduetd",
            "com.apple.suggestions",
        ]

        appendLog("[C12] system data:")
        for id in class12ids {
            var pathC = "/var/containers/Data/System".utf8CString.map { Int8($0) }
            var idC = id.utf8CString.map { Int8($0) }
            let h = bad_query_ex(&pathC, true, &idC, 12)
            if h >= 0 {
                appendLog("  \(id): ACCESS")
                bad_query_release(h)
            }
        }

        let class13ids = [
            "systemgroup.com.apple.siri",
            "systemgroup.com.apple.assistant",
            "systemgroup.com.apple.intelligenceplatform",
            "systemgroup.com.apple.IntelligencePlatform",
            "systemgroup.com.apple.featureflags",
            "systemgroup.com.apple.FeatureFlags",
            "systemgroup.com.apple.eligibilityd",
            "systemgroup.com.apple.gms",
            "systemgroup.com.apple.triald",
            "systemgroup.com.apple.parsec",
            "systemgroup.com.apple.siriknowledged",
            "systemgroup.com.apple.lsd.iconscache",
            "systemgroup.com.apple.mobilegestaltcache",
        ]

        appendLog("[C13] system groups:")
        for id in class13ids {
            var pathC = "/var/containers/Shared/SystemGroup".utf8CString.map { Int8($0) }
            var idC = id.utf8CString.map { Int8($0) }
            let h = bad_query_ex(&pathC, true, &idC, 13)
            if h >= 0 {
                appendLog("  \(id): ACCESS")
                bad_query_release(h)
            }
        }

        appendLog("=== END ===")
    }

    // MARK: - Diagnostics

    func fullStatus() {
        appendLog("=== FULL STATUS ===")

        // MobileGestalt
        appendLog("[MG] AI=\(mg_get_bool_answer(kAICapability)) model=\(mgStr(kProductType) ?? "?") hw=\(mgStr(kHardwareModel) ?? "?") cpu=\(mgStr(kCPUChip) ?? "?")")

        // Eligibility
        if let data = try? Data(contentsOf: URL(fileURLWithPath: "/var/db/eligibilityd/eligibility.plist")),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            appendLog("[ELIG] \(dict.keys.count) domains")
            for key in ["OS_ELIGIBILITY_DOMAIN_GREYMATTER", "OS_ELIGIBILITY_DOMAIN_FOUNDATION_MODELS"] {
                if let domain = dict[key] as? [String: Any] {
                    let answer = domain["os_eligibility_answer_t"] as? Int ?? -1
                    let short = key.replacingOccurrences(of: "OS_ELIGIBILITY_DOMAIN_", with: "")
                    appendLog("  \(short): answer=\(answer) \(answer == 4 ? "ELIGIBLE" : "BLOCKED")")
                    if let status = domain["status"] as? [String: Int] {
                        for (sk, sv) in status.sorted(by: { $0.key < $1.key }) where sv != 3 {
                            let name = sk.replacingOccurrences(of: "OS_ELIGIBILITY_INPUT_", with: "")
                            appendLog("    \(name) = \(sv) BLOCKING")
                        }
                    }
                }
            }
        } else {
            appendLog("[ELIG] can't read eligibility.plist")
        }

        // Feature flags via dlsym
        let flags: [(String, String)] = [
            ("Siri", "sae_override"),
            ("Siri", "assistant_engine_override"),
            ("SiriUI", "sae"),
        ]
        for (sub, flag) in flags {
            let r = ff_check(sub, flag)
            appendLog("[FF] \(sub).\(flag) = \(r == 1 ? "ENABLED" : r == 0 ? "disabled" : "err(\(r))")")
        }

        // Feature flags plist readable?
        for path in ["/var/preferences/FeatureFlags/Global.plist", "/private/var/preferences/FeatureFlags/Global.plist"] {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                appendLog("[FF] \(path) READABLE: \(dict.keys.sorted().joined(separator: ", "))")
                for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                    appendLog("  \(k): \(v)")
                }
                break
            }
        }

        // Asset paths
        let assetDirs = [
            "/var/MobileAsset/AssetsV2/com_apple_MobileAsset_OSEligibility",
            "/var/MobileAsset/AssetsV2/com_apple_MobileAsset_Trial_Siri",
            "/var/MobileAsset/AssetsV2/com_apple_MobileAsset_UAF_Siri",
            "/var/MobileAsset/AssetsV2/com_apple_MobileAsset_Trial_IntelligencePlatform",
        ]
        for p in assetDirs {
            if FileManager.default.fileExists(atPath: p) {
                let name = (p as NSString).lastPathComponent
                appendLog("[ASSET] \(name): exists")
            }
        }

        appendLog("=== END ===")
    }

    // MARK: - Revert

    func revertMG() {
        let backupURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("backups/SavedGestalt.plist")
        guard let data = try? Data(contentsOf: backupURL) else {
            appendLog("no backup"); return
        }
        let h = sandbox(mgDir, label: "rv")
        guard h >= 0 else { return }
        defer { bad_query_release(h) }
        let mgURL = URL(fileURLWithPath: mgPath)
        let tmp = mgURL.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            try data.write(to: tmp, options: [.withoutOverwriting])
            defer { try? FileManager.default.removeItem(at: tmp) }
            _ = try FileManager.default.replaceItemAt(mgURL, withItemAt: tmp)
            appendLog("reverted! Reboot.")
        } catch {
            appendLog("FAIL: \(error.localizedDescription)")
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
