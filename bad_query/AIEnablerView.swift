import SwiftUI
import WebKit

private let mgPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
private let mgDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/"

// eligibility paths to try (in order)
private let eligPaths: [(path: String, create: Bool, label: String)] = [
    ("/var/db/eligibilityd/eligibility.plist", true, "eligibilityd-db"),
    ("/var/containers/Data/System/com.apple.eligibilityd/Library/Caches/NeverRestore/eligibility_overrides.data", true, "eligibilityd-container"),
    ("/var/db/os_eligibility/eligibility.plist", true, "os_eligibility-db"),
]

// feature flag paths to try
private let ffPaths: [(path: String, create: Bool, label: String)] = [
    ("/var/preferences/FeatureFlags/Global.plist", true, "featureflags-preferences"),
]

// container classes to try for eligibility
private let eligContainers: [(identifier: String, cls: UInt64, label: String)] = [
    ("com.apple.eligibilityd", 10, "SystemData-10"),
    ("com.apple.eligibilityd", 12, "InternalDaemon-12"),
    ("com.apple.eligibilityd", 15, "SystemShared-15"),
    ("systemgroup.com.apple.eligibilityd", 13, "SharedSystemData-13"),
]

struct AIEnablerView: View {
    @State private var log = "Apple Intelligence Enabler\nAll-in-one: MobileGestalt + Eligibility + FeatureFlags"
    @State private var isWorking = false
    @State private var showRespring = false
    @State private var showRevertConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
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

    func acquireSandboxEx(_ path: String, identifier: String, containerClass: UInt64, label: String) -> Int64 {
        var pathC = path.utf8CString.map { Int8($0) }
        var idC = identifier.utf8CString.map { Int8($0) }
        let handle = bad_query_ex(&pathC, true, &idC, containerClass)
        if handle >= 0 {
            appendLog("[\(label)] sandbox OK via class \(containerClass) (handle: \(handle))")
        } else {
            appendLog("[\(label)] class \(containerClass) FAILED: \(bqErrorString(handle))")
        }
        return handle
    }

    func writeToPath(_ path: String, data: Data, label: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        do {
            try data.write(to: url)
            appendLog("[\(label)] wrote \(data.count) bytes to \(path)")
            return true
        } catch {
            appendLog("[\(label)] write FAILED: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Enable AI (all 3 steps)

    func enableAI() {
        appendLog("--- enabling Apple Intelligence ---")

        let mgOK = applyMobileGestalt()
        let eligOK = applyEligibility()
        let ffOK = applyFeatureFlags()

        appendLog("--- done ---")
        if mgOK && eligOK && ffOK {
            appendLog("All 3 components written successfully!")
            appendLog("Tap Respring to apply changes.")
        } else {
            appendLog("Some steps failed — check log above.")
        }
    }

    // MARK: - Step 1: MobileGestalt

    func applyMobileGestalt() -> Bool {
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

        // Apple Intelligence key
        cacheExtra["A62OafQ85EJAiiqKn4agtg"] = 1
        dict["CacheExtra"] = cacheExtra

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            // atomic write via temp file (same as mond)
            let tempURL = mgURL.deletingLastPathComponent()
                .appendingPathComponent(".\(mgURL.lastPathComponent).\(UUID().uuidString).tmp")
            try data.write(to: tempURL, options: [.withoutOverwriting])
            defer { try? FileManager.default.removeItem(at: tempURL) }

            if FileManager.default.fileExists(atPath: mgURL.path) {
                _ = try FileManager.default.replaceItemAt(mgURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: mgURL)
            }
            appendLog("[gestalt] AI key set (A62OafQ85EJAiiqKn4agtg = 1)")
            return true
        } catch {
            appendLog("[gestalt] write FAILED: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Step 2: Eligibility

    func applyEligibility() -> Bool {
        let plist: [String: Any] = [
            "OS_ELIGIBILITY_DOMAIN_GREYMATTER": [
                "context": [
                    "OS_ELIGIBILITY_CONTEXT_ELIGIBLE_DEVICE_LANGUAGES": [["en"]]
                ],
                "os_eligibility_answer_source_t": 1,
                "os_eligibility_answer_t": 4,
                "status": [
                    "OS_ELIGIBILITY_INPUT_DEVICE_LANGUAGE": 3,
                    "OS_ELIGIBILITY_INPUT_DEVICE_REGION_CODE": 3,
                    "OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE": 3,
                    "OS_ELIGIBILITY_INPUT_GENERATIVE_MODEL_SYSTEM": 3,
                    "OS_ELIGIBILITY_INPUT_SHARED_IPAD": 3,
                    "OS_ELIGIBILITY_INPUT_SIRI_LANGUAGE": 3
                ]
            ] as [String: Any],
            "OS_ELIGIBILITY_DOMAIN_CALCIUM": [
                "os_eligibility_answer_source_t": 1,
                "os_eligibility_answer_t": 2,
                "status": [
                    "OS_ELIGIBILITY_INPUT_CHINA_CELLULAR": 2
                ]
            ] as [String: Any]
        ]

        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            appendLog("[eligibility] failed to serialize")
            return false
        }

        appendLog("[eligibility] trying path traversal strategies...")

        // Strategy 1: try standard bad_query with create=true for each path
        for entry in eligPaths {
            let handle = acquireSandbox(entry.path, label: entry.label, create: entry.create)
            if handle >= 0 {
                let ok = writeToPath(entry.path, data: data, label: entry.label)
                bad_query_release(handle)
                if ok { return true }
            }
        }

        // Strategy 2: try different container classes via bad_query_ex
        appendLog("[eligibility] trying container class strategies...")
        for container in eligContainers {
            for entry in eligPaths {
                let handle = acquireSandboxEx(entry.path, identifier: container.identifier, containerClass: container.cls, label: "\(entry.label)/\(container.label)")
                if handle >= 0 {
                    let ok = writeToPath(entry.path, data: data, label: "\(entry.label)/\(container.label)")
                    bad_query_release(handle)
                    if ok { return true }
                }
            }
        }

        appendLog("[eligibility] all strategies failed")
        return false
    }

    // MARK: - Step 3: Feature Flags

    func applyFeatureFlags() -> Bool {
        let newFlags: [String: Any] = [
            "Siri": [
                "sae_override": ["Enabled": true],
                "assistant_engine_override": ["Enabled": true]
            ],
            "SiriUI": [
                "sae": ["Enabled": true]
            ]
        ]

        guard let data = try? PropertyListSerialization.data(fromPropertyList: newFlags, format: .xml, options: 0) else {
            appendLog("[featureflags] failed to serialize")
            return false
        }

        appendLog("[featureflags] trying strategies...")

        // Strategy 1: standard bad_query with create=true
        for entry in ffPaths {
            let handle = acquireSandbox(entry.path, label: entry.label, create: entry.create)
            if handle >= 0 {
                // try to merge with existing
                var writeData = data
                if let existingData = try? Data(contentsOf: URL(fileURLWithPath: entry.path)),
                   let existing = try? PropertyListSerialization.propertyList(from: existingData, format: nil) as? [String: Any] {
                    appendLog("[\(entry.label)] merging with existing")
                    let merged = mergeDict(base: existing, overlay: newFlags)
                    writeData = (try? PropertyListSerialization.data(fromPropertyList: merged, format: .xml, options: 0)) ?? data
                }
                let ok = writeToPath(entry.path, data: writeData, label: entry.label)
                bad_query_release(handle)
                if ok { return true }
            }
        }

        // Strategy 2: try via container classes
        for entry in ffPaths {
            for cls: UInt64 in [10, 12, 13, 15] {
                let handle = acquireSandboxEx(entry.path, identifier: "com.apple.preferences", containerClass: cls, label: "ff-class\(cls)")
                if handle >= 0 {
                    let ok = writeToPath(entry.path, data: data, label: "ff-class\(cls)")
                    bad_query_release(handle)
                    if ok { return true }
                }
            }
        }

        appendLog("[featureflags] all strategies failed")
        return false
    }

    // MARK: - Check Status

    func checkStatus() {
        appendLog("--- status ---")

        // MobileGestalt
        let mgHandle = acquireSandbox(mgDir, label: "gestalt")
        if mgHandle >= 0 {
            if let dict = NSDictionary(contentsOf: URL(fileURLWithPath: mgPath)),
               let ce = dict["CacheExtra"] as? NSDictionary {
                let aiKey = ce["A62OafQ85EJAiiqKn4agtg"]
                appendLog("[gestalt] AI key = \(aiKey ?? "not set")")
            } else {
                appendLog("[gestalt] cannot read plist")
            }
            bad_query_release(mgHandle)
        }

        // Eligibility — try all known paths
        var eligFound = false
        for entry in eligPaths {
            let handle = acquireSandbox(entry.path, label: entry.label, create: true)
            if handle >= 0 {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: entry.path)),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let gm = plist["OS_ELIGIBILITY_DOMAIN_GREYMATTER"] as? [String: Any],
                   let answer = gm["os_eligibility_answer_t"] as? Int {
                    appendLog("[eligibility] GREYMATTER = \(answer) \(answer == 4 ? "(eligible)" : "(NOT eligible)") at \(entry.path)")
                    eligFound = true
                }
                bad_query_release(handle)
                if eligFound { break }
            }
        }
        if !eligFound {
            appendLog("[eligibility] not accessible via any known path")
        }

        // Feature Flags
        for entry in ffPaths {
            let handle = acquireSandbox(entry.path, label: entry.label, create: true)
            if handle >= 0 {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: entry.path)),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                    let saeOverride = ((plist["Siri"] as? [String: Any])?["sae_override"] as? [String: Any])?["Enabled"] as? Bool
                    appendLog("[featureflags] Siri.sae_override = \(saeOverride.map(String.init(describing:)) ?? "missing")")
                } else {
                    appendLog("[featureflags] not found or unreadable at \(entry.path)")
                }
                bad_query_release(handle)
            }
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
