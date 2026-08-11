import SwiftUI
import WebKit

private let mgPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
private let mgDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/"

private let kAICapability = "A62OafQ85EJAiiqKn4agtg"
private let kProductType = "h9jDsbgj7xIVeIQ8S3/X3Q"
private let kHardwareModel = "oYicEKzVTz4/CxxE05pEgQ"
private let kCPUChip = "5pYKlGnYYBzGvAlIU8RjEQ"

struct AIEnablerView: View {
    @State private var log = "AI Enabler v5 — Eligibility Attack"
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

                    Section("Step 2: Eligibility") {
                        Button("Read Eligibility (full)") {
                            readEligibility()
                        }

                        Button("Write Eligibility (all methods)") {
                            isWorking = true
                            writeEligibility()
                            isWorking = false
                        }
                        .disabled(isWorking)

                        Button("Set GMS Defaults") {
                            setGMSDefaults()
                        }
                    }

                    Section("Step 3: Apply") {
                        Button("Respring") {
                            showRespring = true
                        }
                    }

                    Section("Diagnostics") {
                        Button("Quick Status") {
                            quickStatus()
                        }

                        Button("Deep Scan") {
                            isWorking = true
                            deepScan()
                            isWorking = false
                        }
                        .disabled(isWorking)
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
                            Button("Clear") { log = "AI Enabler v5" }
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

        // backup once
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

    // MARK: - Step 2: Read Eligibility

    func readEligibility() {
        appendLog("=== ELIGIBILITY READ ===")

        let eligPath = "/var/db/eligibilityd/eligibility.plist"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: eligPath)),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            appendLog("can't read eligibility.plist")
            return
        }

        for key in dict.keys.sorted() {
            guard let domain = dict[key] as? [String: Any] else { continue }
            let answer = domain["os_eligibility_answer_t"] as? Int ?? -1
            let answerStr = answer == 4 ? "ELIGIBLE" : answer == 2 ? "NOT ELIGIBLE" : "\(answer)"
            appendLog("\(key): \(answerStr)")

            if let status = domain["status"] as? [String: Any] {
                for (sk, sv) in status.sorted(by: { $0.key < $1.key }) {
                    let val = sv as? Int ?? -1
                    let marker = val == 2 ? " <<< BLOCKING" : ""
                    appendLog("  \(sk) = \(val)\(marker)")
                }
            }
            if let ctx = domain["context"] as? [String: Any] {
                for (ck, cv) in ctx {
                    appendLog("  ctx.\(ck) = \(cv)")
                }
            }
        }

        appendLog("=== END ===")
    }

    // MARK: - Step 2: Write Eligibility

    func writeEligibility() {
        appendLog("=== ELIGIBILITY WRITE ===")

        let eligPath = "/var/db/eligibilityd/eligibility.plist"

        // First read existing
        var existingDict: [String: Any] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: eligPath)),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            existingDict = dict
            appendLog("read existing: \(dict.keys.count) domains")
        }

        // Modify GREYMATTER to be eligible
        let greymatter: [String: Any] = [
            "context": [
                "OS_ELIGIBILITY_CONTEXT_ELIGIBLE_DEVICE_LANGUAGES": ["en"],
                "OS_ELIGIBILITY_CONTEXT_ELIGIBLE_SIRI_LANGUAGE": "en-US"
            ],
            "os_eligibility_answer_source_t": 1,
            "os_eligibility_answer_t": 4,  // ELIGIBLE
            "status": [
                "OS_ELIGIBILITY_INPUT_COUNTRY_BILLING": 3,
                "OS_ELIGIBILITY_INPUT_COUNTRY_LOCATION": 3,
                "OS_ELIGIBILITY_INPUT_DEVICE_AND_SIRI_LANGUAGE_MATCH": 3,
                "OS_ELIGIBILITY_INPUT_DEVICE_CLASS": 3,
                "OS_ELIGIBILITY_INPUT_DEVICE_LANGUAGE": 3,
                "OS_ELIGIBILITY_INPUT_DEVICE_REGION_CODE": 3,
                "OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE": 3,
                "OS_ELIGIBILITY_INPUT_GENERATIVE_MODEL_SYSTEM": 3,  // was 2!
                "OS_ELIGIBILITY_INPUT_SHARED_IPAD": 3,
                "OS_ELIGIBILITY_INPUT_SIRI_LANGUAGE": 3,
            ]
        ]

        // Also set FOUNDATION_MODELS to eligible
        let foundationModels: [String: Any] = [
            "os_eligibility_answer_source_t": 1,
            "os_eligibility_answer_t": 4,
            "status": [
                "OS_ELIGIBILITY_INPUT_DEVICE_CLASS": 3,
                "OS_ELIGIBILITY_INPUT_GENERATIVE_MODEL_SYSTEM": 3,
            ]
        ]

        existingDict["OS_ELIGIBILITY_DOMAIN_GREYMATTER"] = greymatter
        existingDict["OS_ELIGIBILITY_DOMAIN_FOUNDATION_MODELS"] = foundationModels

        guard let writeData = try? PropertyListSerialization.data(fromPropertyList: existingDict, format: .xml, options: 0) else {
            appendLog("serialize failed"); return
        }

        appendLog("prepared \(writeData.count) bytes, \(existingDict.keys.count) domains")

        // Method 1: Direct write (might work if we have read access)
        appendLog("[method1] direct write...")
        do {
            try writeData.write(to: URL(fileURLWithPath: eligPath))
            appendLog("[method1] SUCCESS! wrote \(writeData.count) bytes")
        } catch {
            appendLog("[method1] \(error.localizedDescription)")
        }

        // Method 2: via bad_query sandbox extension
        appendLog("[method2] bad_query /var/db/eligibilityd...")
        var dirC = "/var/db/eligibilityd".utf8CString.map { Int8($0) }
        let h = bad_query(&dirC, true, nil, false)
        if h >= 0 {
            appendLog("[method2] sandbox OK!")
            do {
                try writeData.write(to: URL(fileURLWithPath: eligPath))
                appendLog("[method2] SUCCESS!")
            } catch {
                appendLog("[method2] write failed: \(error.localizedDescription)")
            }
            bad_query_release(h)
        } else {
            appendLog("[method2] \(bqErr(h))")
        }

        // Method 3: try writing to alternative location
        let altPaths = [
            "/var/db/os_eligibility/eligibility.plist",
            "/var/root/Library/Preferences/com.apple.eligibilityd.plist",
        ]
        for (i, p) in altPaths.enumerated() {
            appendLog("[method\(3+i)] trying \(p)...")
            do {
                let dir = URL(fileURLWithPath: p).deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try writeData.write(to: URL(fileURLWithPath: p))
                appendLog("[method\(3+i)] SUCCESS!")
            } catch {
                appendLog("[method\(3+i)] \(error.localizedDescription)")
            }
        }

        // Method 4: try writing to SQLite datastore
        appendLog("[method5] trying datastore.data...")
        let dsPath = "/var/db/eligibilityd/datastore.data"
        if let dsData = try? Data(contentsOf: URL(fileURLWithPath: dsPath)) {
            appendLog("[method5] datastore readable, \(dsData.count) bytes")
            // Check if it looks like SQLite
            if dsData.count >= 16 {
                let header = String(data: dsData.prefix(16), encoding: .ascii) ?? ""
                appendLog("[method5] header: \(header.prefix(15))")
            }
        } else {
            appendLog("[method5] datastore not readable")
        }

        // Verify
        appendLog("[verify] re-reading eligibility...")
        if let vData = try? Data(contentsOf: URL(fileURLWithPath: eligPath)),
           let vDict = try? PropertyListSerialization.propertyList(from: vData, format: nil) as? [String: Any],
           let gm = vDict["OS_ELIGIBILITY_DOMAIN_GREYMATTER"] as? [String: Any] {
            let answer = gm["os_eligibility_answer_t"] as? Int ?? -1
            appendLog("[verify] GREYMATTER answer=\(answer) \(answer == 4 ? "ELIGIBLE!" : "still blocked")")
            if let status = gm["status"] as? [String: Int] {
                let gms = status["OS_ELIGIBILITY_INPUT_GENERATIVE_MODEL_SYSTEM"] ?? -1
                appendLog("[verify] GMS=\(gms)")
            }
        }

        appendLog("=== WRITE DONE ===")
    }

    // MARK: - GMS Defaults

    func setGMSDefaults() {
        appendLog("=== GMS DEFAULTS ===")

        // Try to write GMS availability via NSUserDefaults
        let suites = [
            "com.apple.eligibilityd",
            "com.apple.gms",
            "com.apple.Preferences",
        ]

        for suite in suites {
            guard let defaults = UserDefaults(suiteName: suite) else {
                appendLog("[\(suite)] can't open"); continue
            }

            // Read current GMS values
            let gmsKey = defaults.object(forKey: "com.apple.gms.availability.key")
            appendLog("[\(suite)] gms.availability.key = \(gmsKey ?? "nil")")

            // Try to set GMS as available
            defaults.set(true, forKey: "com.apple.gms.availability.key")
            defaults.set(["granted"], forKey: "com.apple.gms.availability.unifiedReasons")
            defaults.set([:] as [String: Any], forKey: "com.apple.gms.availability.accessNotGrantedUseCases")
            defaults.set(["ready"], forKey: "com.apple.gms.availability.useCaseReadiness")

            let ok = defaults.synchronize()
            appendLog("[\(suite)] wrote GMS defaults, sync=\(ok)")

            // Verify
            let after = defaults.object(forKey: "com.apple.gms.availability.key")
            appendLog("[\(suite)] after: gms.key = \(after ?? "nil")")
        }

        appendLog("=== GMS DONE ===")
    }

    // MARK: - Quick Status

    func quickStatus() {
        appendLog("=== STATUS ===")
        appendLog("live: AI=\(mg_get_bool_answer(kAICapability)) model=\(mgStr(kProductType) ?? "?") cpu=\(mgStr(kCPUChip) ?? "?")")

        if let data = try? Data(contentsOf: URL(fileURLWithPath: "/var/db/eligibilityd/eligibility.plist")),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let gm = dict["OS_ELIGIBILITY_DOMAIN_GREYMATTER"] as? [String: Any] {
            let answer = gm["os_eligibility_answer_t"] as? Int ?? -1
            let gms = (gm["status"] as? [String: Int])?["OS_ELIGIBILITY_INPUT_GENERATIVE_MODEL_SYSTEM"] ?? -1
            appendLog("GREYMATTER: answer=\(answer)\(answer == 4 ? " ELIGIBLE" : " blocked") GMS=\(gms)")
        }

        if let data = try? Data(contentsOf: URL(fileURLWithPath: "/var/db/eligibilityd/eligibility.plist")),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let fm = dict["OS_ELIGIBILITY_DOMAIN_FOUNDATION_MODELS"] as? [String: Any] {
            let answer = fm["os_eligibility_answer_t"] as? Int ?? -1
            appendLog("FOUNDATION_MODELS: answer=\(answer)")
        }

        appendLog("=== END ===")
    }

    // MARK: - Deep Scan

    func deepScan() {
        appendLog("=== DEEP SCAN ===")

        let basePath = "/var/containers/Data/System"
        let h = sandbox(basePath, label: "sys")
        guard h >= 0 else { return }
        defer { bad_query_release(h) }

        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: basePath) else {
            appendLog("can't list"); return
        }

        for entry in entries {
            let cpath = "\(basePath)/\(entry)"
            let metas = [
                "\(cpath)/.com.apple.containermanagerd.metadata.plist",
                "\(cpath)/.com.apple.mobile_container_manager.metadata.plist",
            ]
            for mp in metas {
                if let md = try? Data(contentsOf: URL(fileURLWithPath: mp)),
                   let m = try? PropertyListSerialization.propertyList(from: md, format: nil) as? [String: Any] {
                    let bid = m["MCMMetadataIdentifier"] as? String ?? "?"
                    appendLog("\(entry.prefix(8)).. = \(bid)")
                    break
                }
            }

            // also try to list subdirs for hints
            if let subs = try? FileManager.default.contentsOfDirectory(atPath: cpath) {
                let interesting = subs.filter { !$0.hasPrefix(".") && $0 != "Library" && $0 != "tmp" && $0 != "Documents" }
                if !interesting.isEmpty {
                    appendLog("  subs: \(interesting.joined(separator: ", "))")
                }
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
