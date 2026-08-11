import SwiftUI
import WebKit

private let mgPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
private let mgDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/"

private let kAICapability = "A62OafQ85EJAiiqKn4agtg"
private let kProductType = "h9jDsbgj7xIVeIQ8S3/X3Q"
private let kHardwareModel = "oYicEKzVTz4/CxxE05pEgQ"
private let kCPUChip = "5pYKlGnYYBzGvAlIU8RjEQ"

// iOS 26+ exposes component-specific identity mirrors. v8 showed that the
// classic ProductType/TargetSubType spoof left these at iPhone15,4/D37AP.
private let productTypeMirrorKeys = [
    "+1TeoctsaQC55zwHZ6MESg", // ProductTypeDescForAudio
    "0+nc/Udy4WNG8S+Q7a/s1A", // ThinningProductType
    "G91h5IuJvXISeyngNFqEpg", // ProductTypeDescForUserVisibility
    "GEsznZwAYGOa1a67QU1Uew", // ProductTypeDescForPowerPerf
    "GqAdWRLnC7oYQrNYF48VYA", // SubProductType
    "MKE8hwsOxxRCtwBk2aDBZA", // ProductTypeDescForAutomatedTesting
    "myx96YOqBSDzLwljSYWBiQ", // ProductTypeDescForCamera
    "xNN67KktpWp7syTT3S1BFA", // ProductTypeDescForAnalytics
]

private let hardwareModelMirrorKeys = [
    "/YYygAofPDbhrwToVsXdeA", // HWModelStr
    "GGIIDN/ANr8X2WrgS6nBYQ", // HWModelUniqueStr
    "ZGraRMW0TsxCvONeeJ5C2w", // HWModelDescriptionForUserVisibility
    "b4e7mEbjqfewD6oXmo9U5g", // HWModelDescriptionForPowerPerf
    "dW5fpt/6HhaTbnK/UqL6cA", // HWModelDescriptionForAudio
    "oQNDePXjSD1z7W0ddqt9tg", // HWModelDescriptionForAutomatedTesting
    "uCIk6n9Am5fsV2cTjhqFQw", // HWModelDescriptionForAnalytics
    "yAfB6E2v0++rHtdW7SDg8w", // HWModelDescriptionForCamera
]

struct AIEnablerView: View {
    @State private var log = "AI Enabler v42 — probe Siri daemon control"
    @State private var isWorking = false
    @State private var showRespring = false
    @State private var showRevertConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    Section("Step 1: MobileGestalt") {
                        Button("Apply Full AI Identity Spoof") {
                            isWorking = true
                            applyMG(fullIdentity: true)
                            isWorking = false
                        }
                        .disabled(isWorking)
                    }

                    Section("Step 2: Eligibility") {
                        Button("Read Eligibility Status") {
                            fullStatus()
                        }
                    }

                    Section("Step 3: Current Siri Gate") {
                        Button("Probe Current Siri Gates") {
                            probeCurrentSiriGates()
                        }

                        Button("Refresh SAE Cache") {
                            refreshSiriCache()
                        }

                        Button("Inspect Siri Availability") {
                            inspectSiriAvailability()
                        }

                        Button("Apply SAE Availability") {
                            writeSiriPreference(operation: 1)
                        }

                        Button("Restore Siri Availability") {
                            writeSiriPreference(operation: 2)
                        }
                    }

                    Section("Assets") {
                        Button("Probe AI/Siri Assets (Safe)") {
                            probeAIAssets()
                        }
                    }

                    Section("Research") {
                        Button("Probe Siri Daemon Control") {
                            probeSiriDaemonControl()
                        }
                    }

                    Section("Apply") {
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
                            Button("Clear") { log = "AI Enabler v42" }
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

    func plistValueDescription(_ value: Any) -> String {
        if let value = value as? Bool { return "bool:\(value)" }
        if let value = value as? NSNumber { return "number:\(value)" }
        if let value = value as? String { return "string:\(value)" }
        if let value = value as? Data { return "data:\(value.count)b:\(value.base64EncodedString())" }
        if let value = value as? Date { return "date:\(ISO8601DateFormatter().string(from: value))" }
        if let value = value as? [Any] { return "array[\(value.count)]:\(value)" }
        if let value = value as? [String: Any] { return "dict[\(value.count)]:\(value)" }
        return "\(type(of: value)):\(String(describing: value))"
    }

    // MARK: - Step 1: MobileGestalt

    func applyMG(fullIdentity: Bool = false) {
        appendLog(fullIdentity ? "=== FULL IDENTITY SPOOF v9 ===" : "=== MG SPOOF ===")
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
        if fullIdentity {
            for key in productTypeMirrorKeys { ce[key] = "iPhone16,1" }
            for key in hardwareModelMirrorKeys { ce[key] = "D83AP" }
        }
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
            if fullIdentity {
                appendLog("identity mirrors: product=\(productTypeMirrorKeys.count), hardware=\(hardwareModelMirrorKeys.count)")
            }
        } catch {
            appendLog("FAIL: \(error.localizedDescription)"); return
        }

        mg_notify_cache_changed()
        appendLog("cache notify sent")
        appendLog("live: AI=\(mg_get_bool_answer(kAICapability)) model=\(mgStr(kProductType) ?? "?")")
        if fullIdentity {
            appendLog("live HWModelStr=\(mgStr("/YYygAofPDbhrwToVsXdeA") ?? "?")")
            appendLog("live ProductTypeDescForAnalytics=\(mgStr("xNN67KktpWp7syTT3S1BFA") ?? "?")")
            appendLog("respring required; reboot restores hardware-generated cache")
        }
    }

    // MARK: - Step 2: Eligibility API

    func probeEligDomains() {
        appendLog("=== ELIGIBILITY DOMAINS ===")
        if let cStr = elig_probe_domains() {
            let str = String(cString: cStr)
            for line in str.split(separator: "\n") where !line.isEmpty {
                let s = String(line)
                if s.contains("=4") {
                    appendLog("\(s) ELIGIBLE")
                } else if s.contains("=2") {
                    appendLog("\(s) NOT ELIGIBLE")
                } else {
                    appendLog(s)
                }
            }
            free(cStr)
        } else {
            appendLog("probe returned nil")
        }
        appendLog("=== END ===")
    }

    func forceEligInputs() {
        appendLog("=== FORCE ELIGIBILITY INPUTS ===")

        // Try os_eligibility_set_input with various parameter combinations
        // Unknown signature: could be (input, value) or (domain, input, value)
        // We try both by setting p3 = 0 for 2-arg interpretation

        // First try: (input_id, value, 0) — 2-arg style
        appendLog("[2-arg] trying set_input(input, 3, 0)...")
        for input in 0..<20 {
            let r = elig_set_input_try(Int32(input), 3, 0)
            if r == 0 {
                appendLog("  input \(input) -> OK (ret=0)")
            } else if r != -1 && r != -100 && r != -101 {
                appendLog("  input \(input) -> ret=\(r)")
            }
        }

        // Second try: (domain, input, value) — 3-arg style
        // Try setting GMS (guessed input ~7-15) for various domains (0-20)
        appendLog("[3-arg] trying set_input(domain, input, 3)...")
        for domain in 0..<20 {
            for input in 0..<15 {
                let r = elig_set_input_try(Int32(domain), Int32(input), 3)
                if r == 0 {
                    appendLog("  D\(domain) I\(input) -> OK")
                }
            }
        }

        // Post notification to trigger re-evaluation
        post_darwin_notification("com.apple.eligibility.inputChanged")
        post_darwin_notification("com.apple.MobileGestalt.cache-changed")
        appendLog("[notify] eligibility + MG notifications posted")

        // Check result
        appendLog("[verify] checking eligibility...")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: "/var/db/eligibilityd/eligibility.plist")),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for key in dict.keys.sorted() {
                guard let domain = dict[key] as? [String: Any] else { continue }
                let answer = domain["os_eligibility_answer_t"] as? Int ?? -1
                let short = key.replacingOccurrences(of: "OS_ELIGIBILITY_DOMAIN_", with: "")
                if answer == 4 {
                    appendLog("  \(short): ELIGIBLE")
                } else {
                    appendLog("  \(short): answer=\(answer)")
                    if let status = domain["status"] as? [String: Int] {
                        for (sk, sv) in status where sv != 3 {
                            let name = sk.replacingOccurrences(of: "OS_ELIGIBILITY_INPUT_", with: "")
                            appendLog("    \(name)=\(sv) BLOCKING")
                        }
                    }
                }
            }
        }

        // Re-check feature flags after eligibility changes
        appendLog("[ff] feature flags after:")
        let flags: [(String, String)] = [
            ("Siri", "sae_override"),
            ("Siri", "assistant_engine_override"),
            ("SiriUI", "sae"),
        ]
        for (sub, flag) in flags {
            let r = ff_check(sub, flag)
            appendLog("  \(sub).\(flag) = \(r == 1 ? "ENABLED" : r == 0 ? "disabled" : "err(\(r))")")
        }

        appendLog("=== END ===")
    }

    // MARK: - Step 3: Feature Flags

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

        // Method 2: NSUserDefaults
        appendLog("[M2] NSUserDefaults...")
        let suites = [
            "com.apple.FeatureFlags",
            ".GlobalPreferences",
            "com.apple.siri",
            "com.apple.assistant.support",
            "com.apple.SiriUI",
            "com.apple.Preferences",
        ]
        for suite in suites {
            guard let d = UserDefaults(suiteName: suite) else { continue }
            for (_, flag) in flags {
                d.set(["Enabled": true], forKey: flag)
                d.set(true, forKey: flag)
            }
            d.set(true, forKey: "SiriCanAccessServerModels")
            d.set(true, forKey: "AssistantEnabled")
            d.synchronize()
        }
        appendLog("  \(suites.count) suites written")

        // Method 3: CFPreferences
        appendLog("[M3] CFPreferences...")
        for (_, flag) in flags {
            let key = flag as CFString
            CFPreferencesSetValue(key, kCFBooleanTrue, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        let cfDomains: [CFString] = ["com.apple.siri" as CFString, "com.apple.assistant" as CFString, "com.apple.SiriUI" as CFString]
        for domain in cfDomains {
            for (_, flag) in flags {
                CFPreferencesSetValue(flag as CFString, kCFBooleanTrue, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            }
            CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        appendLog("  global + 3 domains synced")

        // Method 4: Write Global.plist via bad_query + direct
        appendLog("[M4] Global.plist...")
        let ffPlist: [String: Any] = [
            "Siri": ["sae_override": ["Enabled": true], "assistant_engine_override": ["Enabled": true]],
            "SiriUI": ["sae": ["Enabled": true]],
        ]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: ffPlist, format: .xml, options: 0)
            // Try direct write
            try? data.write(to: URL(fileURLWithPath: "/var/preferences/FeatureFlags/Global.plist"))
            // Try bad_query
            var pp = "/var/preferences/FeatureFlags".utf8CString.map { Int8($0) }
            let hff = bad_query(&pp, true, nil, false)
            if hff >= 0 {
                try? data.write(to: URL(fileURLWithPath: "/var/preferences/FeatureFlags/Global.plist"))
                appendLog("  bad_query OK, wrote!")
                bad_query_release(hff)
            } else {
                appendLog("  bad_query: \(bqErr(hff))")
            }
        } catch {
            appendLog("  serialize: \(error.localizedDescription)")
        }

        // Method 5: Notifications
        appendLog("[M5] notifications...")
        for n in ["com.apple.FeatureFlags.changed", "com.apple.siri.configurationChanged", "com.apple.assistant.configurationChanged"] {
            post_darwin_notification(n)
        }

        // Verify
        appendLog("[verify]")
        for (sub, flag) in flags {
            let r = ff_check(sub, flag)
            appendLog("  \(sub).\(flag) = \(r == 1 ? "ENABLED" : r == 0 ? "disabled" : "err(\(r))")")
        }

        appendLog("=== FF DONE ===")
    }

    // MARK: - Step 4: Extra MG Keys

    func dumpCacheExtra() {
        appendLog("=== CACHEEXTRA SNAPSHOT ===")
        let h = sandbox(mgDir, label: "mg-dump")
        guard h >= 0 else { return }
        defer { bad_query_release(h) }

        let mgURL = URL(fileURLWithPath: mgPath)
        guard let root = NSDictionary(contentsOf: mgURL) as? [String: Any],
              let cacheExtra = root["CacheExtra"] as? [String: Any] else {
            appendLog("can't parse CacheExtra")
            return
        }

        let sortedKeys = cacheExtra.keys.sorted()
        let lines = sortedKeys.map { key in
            "\(key)\t\(plistValueDescription(cacheExtra[key]!))"
        }

        appendLog("keys=\(sortedKeys.count)")
        for line in lines { appendLog(line) }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let plistURL = documents.appendingPathComponent("CacheExtra-latest.plist")
        let textURL = documents.appendingPathComponent("CacheExtra-latest.txt")
        do {
            let plist = try PropertyListSerialization.data(
                fromPropertyList: cacheExtra,
                format: .xml,
                options: 0
            )
            try plist.write(to: plistURL, options: .atomic)
            try (lines.joined(separator: "\n") + "\n").write(
                to: textURL,
                atomically: true,
                encoding: .utf8
            )
            appendLog("saved: Documents/\(plistURL.lastPathComponent)")
            appendLog("saved: Documents/\(textURL.lastPathComponent)")
        } catch {
            appendLog("snapshot save FAIL: \(error.localizedDescription)")
        }
        appendLog("=== END SNAPSHOT ===")
    }

    func probeMGKeys() {
        appendLog("=== MG KEY PROBE ===")
        if let cStr = mg_probe_extra_keys() {
            let str = String(cString: cStr)
            for line in str.split(separator: "\n") where !line.isEmpty {
                appendLog(String(line))
            }
            free(cStr)
        } else {
            appendLog("probe returned nil")
        }

        // Also check our spoofed keys
        appendLog("[spoofed]")
        appendLog("  AI=\(mg_get_bool_answer(kAICapability))")
        appendLog("  ProductType=\(mgStr(kProductType) ?? "nil")")
        appendLog("  HardwareModel=\(mgStr(kHardwareModel) ?? "nil")")
        appendLog("  CPUChip=\(mgStr(kCPUChip) ?? "nil")")

        appendLog("=== END ===")
    }

    // MARK: - Diagnostics

    func checkRequiredFlags() {
        appendLog("=== REQUIRED FEATURE FLAGS ===")
        let flags: [(String, String)] = [
            ("Siri", "sae_override"),
            ("Siri", "assistant_engine_override"),
            ("SiriUI", "sae"),
        ]
        for (domain, feature) in flags {
            let result = ff_check(domain, feature)
            let value = result == 1 ? "ENABLED" : result == 0 ? "disabled" : "err(\(result))"
            appendLog("\(domain).\(feature)=\(value)")
        }
        appendLog("ABI=bool(const char *, const char *)")
        appendLog("scope=current process only")
        appendLog("=== END FLAGS ===")
    }

    func probeSiriGate() {
        appendLog("=== SIRI GATE SYMBOLS (NO PRIVATE CALLS) ===")
        guard let cString = siri_gate_probe() else {
            appendLog("probe returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") {
            appendLog(String(line))
        }
        appendLog("unknown-ABI symbols are presence-tested only")
        appendLog("=== END SIRI GATE SYMBOLS ===")
    }

    func callConfirmedSiriGate(_ index: Int32, name: String) {
        appendLog("=== ISOLATED SIRI GATE ===")
        appendLog("calling \(name) only")
        UserDefaults.standard.set(name, forKey: "LastSiriGateAttempt")
        UserDefaults.standard.synchronize()
        let result = siri_gate_call_confirmed(index)
        UserDefaults.standard.set("\(name)=\(result)", forKey: "LastSiriGateAttempt")
        UserDefaults.standard.synchronize()
        appendLog("\(name)=\(result == 1 ? "TRUE" : result == 0 ? "false" : "err(\(result))")")
        appendLog("=== END ISOLATED SIRI GATE ===")
    }

    func probeCurrentSiriGates() {
        appendLog("=== CURRENT SIRI GATES ===")
        appendLog("locale.current=\(Locale.current.identifier)")
        appendLog("locale.preferred=\(Locale.preferredLanguages.joined(separator: ","))")
        if let region = Locale.current.region?.identifier {
            appendLog("locale.region=\(region)")
        }
        let gates: [(Int32, String)] = [
            (0, "SystemAssistantExperience"),
            (1, "SAEByDeviceCapabilityAndFeatureFlags"),
            (2, "DeviceSupportsSAE"),
            (3, "DeviceSupportsSiriUOD"),
            (4, "HasGMSCapabilityUnembargoed"),
            (5, "LocaleSupportsSAE"),
            (6, "DeviceSupportsSAEDeprecated"),
        ]
        for (index, name) in gates {
            UserDefaults.standard.set(name, forKey: "LastSiriGateAttempt")
            UserDefaults.standard.synchronize()
            let result = siri_gate_call_confirmed(index)
            UserDefaults.standard.set("\(name)=\(result)", forKey: "LastSiriGateAttempt")
            UserDefaults.standard.synchronize()
            appendLog("\(name)=\(result == 1 ? "TRUE" : result == 0 ? "false" : "err(\(result))")")
        }
        appendLog("=== END CURRENT SIRI GATES ===")
    }

    func dumpSiriGateCode() {
        appendLog("=== EXACT-BUILD SAE CODE ===")
        guard let cString = siri_gate_code_dump() else {
            appendLog("dump returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") {
            appendLog(String(line))
        }
        appendLog("read-only memory snapshot; no gates invoked")
        appendLog("=== END EXACT-BUILD SAE CODE ===")
    }

    func dumpSiriGateTargets() {
        appendLog("=== SAE BRANCH TARGETS ===")
        guard let cString = siri_gate_target_dump() else {
            appendLog("dump returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") {
            appendLog(String(line))
        }
        appendLog("read-only; branch targets not invoked")
        appendLog("=== END SAE BRANCH TARGETS ===")
    }

    func identifySiriGateSelectors() {
        appendLog("=== HIDDEN SAE SELECTORS ===")
        guard let cString = siri_gate_selector_probe() else {
            appendLog("probe returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") {
            appendLog(String(line))
        }
        appendLog("read-only; selectors not invoked")
        appendLog("=== END HIDDEN SAE SELECTORS ===")
    }

    func identifyDeprecatedSiriDependencies() {
        appendLog("=== DEPRECATED SAE DEPENDENCIES ===")
        guard let cString = siri_deprecated_dependency_probe() else {
            appendLog("probe returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") {
            appendLog(String(line))
        }
        appendLog("read-only; dependencies not invoked")
        appendLog("=== END DEPRECATED SAE DEPENDENCIES ===")
    }

    func refreshSiriCache() {
        appendLog("=== REFRESH SAE CACHE ===")
        guard let cString = siri_refresh_sae_cache() else {
            appendLog("refresh returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") {
            appendLog(String(line))
        }
        appendLog("if after values are TRUE, respring next")
        appendLog("=== END REFRESH SAE CACHE ===")
    }

    func dumpSiriRefreshMethod() {
        appendLog("=== SAE REFRESH METHOD CODE ===")
        guard let cString = siri_refresh_method_dump() else {
            appendLog("dump returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") {
            appendLog(String(line))
        }
        appendLog("read-only; IMP not invoked by dump")
        appendLog("=== END SAE REFRESH METHOD CODE ===")
    }

    func mapSiriRefreshCalls() {
        appendLog("=== SAE REFRESH CALL MAP ===")
        guard let cString = siri_refresh_call_map() else {
            appendLog("map returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") {
            appendLog(String(line))
        }
        appendLog("read-only; calls not invoked")
        appendLog("=== END SAE REFRESH CALL MAP ===")
    }

    func inspectSiriAvailability() {
        appendLog("=== SIRI AVAILABILITY ===")
        guard let cString = siri_availability_probe() else {
            appendLog("probe returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") {
            appendLog(String(line))
        }
        appendLog("=== END SIRI AVAILABILITY ===")
    }

    func mapSiriAvailabilityRuntime() {
        appendLog("=== SIRI AVAILABILITY RUNTIME ===")
        guard let cString = siri_availability_runtime_map() else {
            appendLog("map returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") {
            appendLog(String(line))
        }
        appendLog("read-only runtime metadata")
        appendLog("=== END SIRI AVAILABILITY RUNTIME ===")
    }

    func inspectSiriAvailabilitySources() {
        appendLog("=== AVAILABILITY SOURCES ===")
        guard let cString = siri_availability_detail_probe() else {
            appendLog("probe returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") {
            appendLog(String(line))
        }
        appendLog("read-only; live and preference objects unchanged")
        appendLog("=== END AVAILABILITY SOURCES ===")
    }

    func mapSiriPreferenceSource() {
        appendLog("=== SIRI PREFERENCE SOURCE ===")
        guard let cString = siri_preferences_source_map() else {
            appendLog("map returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") {
            appendLog(String(line))
        }
        appendLog("read-only; preferences unchanged")
        appendLog("=== END SIRI PREFERENCE SOURCE ===")
    }

    func identifySiriPreferenceKey() {
        appendLog("=== SIRI PREFERENCE KEY ===")
        guard let cString = siri_preferences_key_probe() else {
            appendLog("probe returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") {
            appendLog(String(line))
        }
        appendLog("read-only; setter symbols not called")
        appendLog("=== END SIRI PREFERENCE KEY ===")
    }

    func writeSiriPreference(operation: Int32) {
        appendLog("=== SIRI PREFERENCE WRITE op=\(operation) ===")
        guard let cString = siri_preferences_write(operation) else {
            appendLog("write returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") { appendLog(String(line)) }
        appendLog("=== END SIRI PREFERENCE WRITE ===")
    }

    func inventorySiriAvailabilityWriters() {
        appendLog("=== SIRI AVAILABILITY WRITER INVENTORY ===")
        guard let cString = siri_availability_writer_inventory() else {
            appendLog("inventory returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") { appendLog(String(line)) }
        appendLog("=== END SIRI AVAILABILITY WRITER INVENTORY ===")
    }

    func inspectSiriCapabilityClients() {
        appendLog("=== SIRI CAPABILITY CLIENT RUNTIME ===")
        guard let cString = siri_capabilities_client_runtime() else {
            appendLog("runtime probe returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") { appendLog(String(line)) }
        appendLog("=== END SIRI CAPABILITY CLIENT RUNTIME ===")
    }

    func querySiriCapabilityService() {
        appendLog("=== SIRI CAPABILITY SERVICE SYNC ===")
        guard let cString = siri_capabilities_service_sync_probe() else {
            appendLog("service probe returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") { appendLog(String(line)) }
        appendLog("read-only synchronous service query")
        appendLog("=== END SIRI CAPABILITY SERVICE SYNC ===")
    }

    func mapSiriCapabilityServiceCalls() {
        appendLog("=== SIRI CAPABILITY CLIENT CALL MAP ===")
        guard let cString = siri_capabilities_client_call_map() else {
            appendLog("call map returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") { appendLog(String(line)) }
        appendLog("=== END SIRI CAPABILITY CLIENT CALL MAP ===")
    }

    func refreshSiriCapabilityService() {
        appendLog("=== SIRI CAPABILITY SERVICE UPDATE ===")
        guard let cString = siri_capabilities_service_update() else {
            appendLog("service update returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") { appendLog(String(line)) }
        appendLog("=== END SIRI CAPABILITY SERVICE UPDATE ===")
    }

    func scanSiriCapabilityServiceBinary() {
        appendLog("=== SIRI CAPABILITY SERVICE BINARY ===")
        guard let cString = siri_capability_service_binary_probe() else {
            appendLog("binary probe returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") { appendLog(String(line)) }
        appendLog("=== END SIRI CAPABILITY SERVICE BINARY ===")
    }

    func locateSiriCapabilityService() {
        appendLog("=== SIRI CAPABILITY SERVICE REGISTRATION ===")
        guard let cString = siri_capability_service_registration_probe() else {
            appendLog("registration probe returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") { appendLog(String(line)) }
        appendLog("=== END SIRI CAPABILITY SERVICE REGISTRATION ===")
    }

    func inspectSiriCapabilityDaemons() {
        appendLog("=== SIRI CAPABILITY DAEMON DETAILS ===")
        guard let cString = siri_capability_daemon_details() else {
            appendLog("daemon probe returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") { appendLog(String(line)) }
        appendLog("=== END SIRI CAPABILITY DAEMON DETAILS ===")
    }

    func mapDedicatedSiriSetter() {
        appendLog("=== DEDICATED SIRI AVAILABILITY SETTER ===")
        guard let cString = siri_dedicated_setter_map() else {
            appendLog("setter map returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") { appendLog(String(line)) }
        appendLog("=== END DEDICATED SIRI AVAILABILITY SETTER ===")
    }

    func applyDedicatedSiriSetter() {
        appendLog("=== DEDICATED SIRI AVAILABILITY APPLY ===")
        guard let cString = siri_dedicated_setter_apply() else {
            appendLog("dedicated apply returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") { appendLog(String(line)) }
        appendLog("=== END DEDICATED SIRI AVAILABILITY APPLY ===")
    }

    func inspectSiriFeatureInputs() {
        appendLog("=== SIRI FEATURE INPUT RUNTIME ===")
        guard let cString = siri_feature_input_runtime_map() else {
            appendLog("feature runtime map returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") { appendLog(String(line)) }
        appendLog("=== END SIRI FEATURE INPUT RUNTIME ===")
    }

    func readSiriFeatureInputs() {
        appendLog("=== SIRI FEATURE INPUT VALUES ===")
        guard let cString = siri_feature_input_values() else {
            appendLog("feature value probe returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") { appendLog(String(line)) }
        appendLog("=== END SIRI FEATURE INPUT VALUES ===")
    }

    func probeSiriDaemonControl() {
        appendLog("=== SIRI DAEMON CONTROL PROBE ===")
        guard let cString = siri_daemon_control_probe() else {
            appendLog("daemon probe returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") { appendLog(String(line)) }
        appendLog("=== END SIRI DAEMON CONTROL PROBE ===")
    }

    func probeSiriGroups() {
        appendLog("=== SIRI APP GROUPS ===")
        guard let cString = siri_group_probe() else {
            appendLog("probe returned nil")
            return
        }
        let result = String(cString: cString)
        free(cString)
        for line in result.split(separator: "\n") {
            appendLog(String(line))
        }
        appendLog("read-only discovery; no files changed")
        appendLog("=== END SIRI APP GROUPS ===")
    }

    func probeAIAssets() {
        appendLog("=== AI/SIRI ASSET INVENTORY ===")
        let roots = [
            "/var/MobileAsset/AssetsV2",
            "/private/var/MobileAsset/AssetsV2",
            "/var/mobile/Library/AssetsV2",
            "/private/var/mobile/Library/AssetsV2",
        ]
        let assetTypes = [
            "com_apple_MobileAsset_OSEligibility",
            "com_apple_MobileAsset_Trial_Siri",
            "com_apple_MobileAsset_UAF_Siri",
            "com_apple_MobileAsset_Trial_IntelligencePlatform",
            "com_apple_MobileAsset_EmbeddedSpeech",
            "com_apple_MobileAsset_VoiceServicesVocalizerVoice",
        ]
        let fm = FileManager.default

        for root in roots {
            var isDirectory: ObjCBool = false
            let exists = fm.fileExists(atPath: root, isDirectory: &isDirectory)
            guard exists else {
                appendLog("[ROOT] \(root)=NOT_VISIBLE")
                continue
            }
            do {
                let children = try fm.contentsOfDirectory(atPath: root).sorted()
                appendLog("[ROOT] \(root)=READABLE count=\(children.count)")
                let relevant = children.filter {
                    let s = $0.lowercased()
                    return s.contains("siri") || s.contains("intelligence") ||
                           s.contains("eligibility") || s.contains("speech") ||
                           s.contains("generative")
                }
                for child in relevant.prefix(80) {
                    appendLog("  type:\(child)")
                }
                if relevant.count > 80 {
                    appendLog("  ... \(relevant.count - 80) more relevant types")
                }
            } catch {
                let e = error as NSError
                appendLog("[ROOT] \(root)=EXISTS_DENIED domain=\(e.domain) code=\(e.code)")
            }
        }

        appendLog("[KNOWN TYPES]")
        for type in assetTypes {
            let path = "/var/MobileAsset/AssetsV2/\(type)"
            var isDirectory: ObjCBool = false
            if !fm.fileExists(atPath: path, isDirectory: &isDirectory) {
                appendLog("\(type)=NOT_VISIBLE")
                continue
            }
            do {
                let children = try fm.contentsOfDirectory(atPath: path).sorted()
                appendLog("\(type)=READABLE entries=\(children.count)")
                for child in children.prefix(20) {
                    appendLog("  \(child)")
                }
            } catch {
                let e = error as NSError
                appendLog("\(type)=EXISTS_DENIED domain=\(e.domain) code=\(e.code)")
            }
        }
        appendLog("read-only; no assets requested or changed")
        appendLog("=== END AI/SIRI ASSET INVENTORY ===")
    }

    func fullStatus() {
        appendLog("=== FULL STATUS ===")

        appendLog("[MG] AI=\(mg_get_bool_answer(kAICapability)) model=\(mgStr(kProductType) ?? "?") hw=\(mgStr(kHardwareModel) ?? "?") cpu=\(mgStr(kCPUChip) ?? "?")")
        appendLog("[MG-ID] HWModelStr=\(mgStr("/YYygAofPDbhrwToVsXdeA") ?? "?") HWUnique=\(mgStr("GGIIDN/ANr8X2WrgS6nBYQ") ?? "?")")
        appendLog("[MG-ID] ProductAnalytics=\(mgStr("xNN67KktpWp7syTT3S1BFA") ?? "?") ProductUser=\(mgStr("G91h5IuJvXISeyngNFqEpg") ?? "?")")

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
            appendLog("[ELIG] can't read")
        }

        let flags: [(String, String)] = [
            ("Siri", "sae_override"),
            ("Siri", "assistant_engine_override"),
            ("SiriUI", "sae"),
        ]
        for (sub, flag) in flags {
            let r = ff_check(sub, flag)
            appendLog("[FF] \(sub).\(flag) = \(r == 1 ? "ENABLED" : r == 0 ? "disabled" : "err(\(r))")")
        }

        for path in ["/var/preferences/FeatureFlags/Global.plist"] {
            let exists = FileManager.default.fileExists(atPath: path)
            if exists {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                    appendLog("[FF] Global.plist: \(dict.keys.sorted().joined(separator: ", "))")
                } else {
                    appendLog("[FF] Global.plist: exists, can't parse")
                }
            } else {
                appendLog("[FF] Global.plist: NOT FOUND")
            }
        }

        let assetDirs = [
            "/var/MobileAsset/AssetsV2/com_apple_MobileAsset_OSEligibility",
            "/var/MobileAsset/AssetsV2/com_apple_MobileAsset_Trial_Siri",
            "/var/MobileAsset/AssetsV2/com_apple_MobileAsset_UAF_Siri",
            "/var/MobileAsset/AssetsV2/com_apple_MobileAsset_Trial_IntelligencePlatform",
        ]
        for p in assetDirs {
            if FileManager.default.fileExists(atPath: p) {
                appendLog("[ASSET] \((p as NSString).lastPathComponent): exists")
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
