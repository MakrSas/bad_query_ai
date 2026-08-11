import SwiftUI

struct AIEnablerView: View {
    @State private var log = "Apple Intelligence Enabler"
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Actions") {
                    Button("Enable Apple Intelligence") {
                        isWorking = true
                        enableAI()
                        isWorking = false
                    }
                    .disabled(isWorking)

                    Button("Check Current Status") {
                        checkStatus()
                    }
                }

                Section("Log") {
                    ScrollView {
                        Text(log)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 300)

                    Button("Clear Log") {
                        log = "Apple Intelligence Enabler"
                    }
                }

                Section("Info") {
                    Text("This writes eligibility + feature flags via bad_query sandbox escape. Use mond separately to set the MobileGestalt key.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AI Enabler")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    func appendLog(_ msg: String) {
        log.append("\n\(msg)")
    }

    func writeFileViaBQ(path: String, data: Data, label: String) -> Bool {
        appendLog("[\(label)] getting sandbox extension for \(path)...")
        var pathC = path.utf8CString.map { Int8($0) }
        let handle = bad_query(&pathC, false, nil, false)
        guard handle >= 0 else {
            let reason: String
            switch handle {
            case -1: reason = "failed to resolve functions"
            case -2: reason = "failed to create sandbox query"
            case -3: reason = "outside containermanager sandbox"
            case -4: reason = "kernel rejected sandbox query"
            default: reason = "unknown error \(handle)"
            }
            appendLog("[\(label)] FAILED: \(reason)")
            return false
        }
        appendLog("[\(label)] sandbox extension acquired (handle: \(handle))")

        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            appendLog("[\(label)] warning: could not create directory: \(error.localizedDescription)")
        }

        do {
            try data.write(to: url)
            appendLog("[\(label)] wrote \(data.count) bytes OK")
            bad_query_release(handle)
            return true
        } catch {
            appendLog("[\(label)] write FAILED: \(error.localizedDescription)")
            bad_query_release(handle)
            return false
        }
    }

    func enableAI() {
        appendLog("--- starting AI enablement ---")

        // 1. Write eligibility.plist
        let eligPlist = buildEligibilityPlist()
        guard let eligData = try? PropertyListSerialization.data(fromPropertyList: eligPlist, format: .xml, options: 0) else {
            appendLog("[eligibility] failed to serialize plist")
            return
        }

        let eligOK = writeFileViaBQ(
            path: "/var/db/eligibilityd/eligibility.plist",
            data: eligData,
            label: "eligibility"
        )

        // 2. Write feature flags
        let ffPlist = buildFeatureFlagsPlist()
        guard let ffData = try? PropertyListSerialization.data(fromPropertyList: ffPlist, format: .xml, options: 0) else {
            appendLog("[featureflags] failed to serialize plist")
            return
        }

        let ffPath = "/var/preferences/FeatureFlags/Global.plist"

        // try to read existing Global.plist and merge
        var mergedFF = ffPlist
        let ffReadPath = ffPath
        var ffReadPathC = ffReadPath.utf8CString.map { Int8($0) }
        let ffReadHandle = bad_query(&ffReadPathC, false, nil, false)
        if ffReadHandle >= 0 {
            if let existingData = try? Data(contentsOf: URL(fileURLWithPath: ffPath)),
               let existing = try? PropertyListSerialization.propertyList(from: existingData, format: nil) as? [String: Any] {
                appendLog("[featureflags] found existing Global.plist, merging...")
                mergedFF = mergeFeatureFlags(existing: existing, new: ffPlist)
            }
            bad_query_release(ffReadHandle)
        }

        guard let mergedData = try? PropertyListSerialization.data(fromPropertyList: mergedFF, format: .xml, options: 0) else {
            appendLog("[featureflags] failed to serialize merged plist")
            return
        }

        let ffOK = writeFileViaBQ(
            path: ffPath,
            data: mergedData,
            label: "featureflags"
        )

        appendLog("--- done ---")
        if eligOK && ffOK {
            appendLog("Both files written. Now:")
            appendLog("1. Open mond and enable Apple Intelligence toggle")
            appendLog("2. Respring or reboot")
        } else {
            appendLog("Some writes failed — check errors above.")
        }
    }

    func checkStatus() {
        appendLog("--- checking status ---")

        let eligPath = "/var/db/eligibilityd/eligibility.plist"
        var eligPathC = eligPath.utf8CString.map { Int8($0) }
        let eligHandle = bad_query(&eligPathC, false, nil, false)
        if eligHandle >= 0 {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: eligPath)),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                if let gm = plist["OS_ELIGIBILITY_DOMAIN_GREYMATTER"] as? [String: Any],
                   let answer = gm["os_eligibility_answer_t"] as? Int {
                    appendLog("[eligibility] GREYMATTER answer = \(answer) \(answer == 4 ? "(eligible)" : "(NOT eligible)")")
                } else {
                    appendLog("[eligibility] GREYMATTER domain not found")
                }
            } else {
                appendLog("[eligibility] file not found or unreadable")
            }
            bad_query_release(eligHandle)
        } else {
            appendLog("[eligibility] cannot get sandbox extension")
        }

        let ffPath = "/var/preferences/FeatureFlags/Global.plist"
        var ffPathC = ffPath.utf8CString.map { Int8($0) }
        let ffHandle = bad_query(&ffPathC, false, nil, false)
        if ffHandle >= 0 {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: ffPath)),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                if let siri = plist["Siri"] as? [String: Any] {
                    let saeOverride = (siri["sae_override"] as? [String: Any])?["Enabled"] as? Bool
                    let engineOverride = (siri["assistant_engine_override"] as? [String: Any])?["Enabled"] as? Bool
                    appendLog("[featureflags] Siri.sae_override = \(saeOverride.map(String.init(describing:)) ?? "missing")")
                    appendLog("[featureflags] Siri.assistant_engine_override = \(engineOverride.map(String.init(describing:)) ?? "missing")")
                } else {
                    appendLog("[featureflags] Siri category not found")
                }
                if let siriUI = plist["SiriUI"] as? [String: Any] {
                    let sae = (siriUI["sae"] as? [String: Any])?["Enabled"] as? Bool
                    appendLog("[featureflags] SiriUI.sae = \(sae.map(String.init(describing:)) ?? "missing")")
                } else {
                    appendLog("[featureflags] SiriUI category not found")
                }
            } else {
                appendLog("[featureflags] file not found or unreadable")
            }
            bad_query_release(ffHandle)
        } else {
            appendLog("[featureflags] cannot get sandbox extension")
        }

        appendLog("--- status check done ---")
    }

    func buildEligibilityPlist() -> [String: Any] {
        return [
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
    }

    func buildFeatureFlagsPlist() -> [String: Any] {
        return [
            "Siri": [
                "sae_override": ["Enabled": true],
                "assistant_engine_override": ["Enabled": true]
            ],
            "SiriUI": [
                "sae": ["Enabled": true]
            ]
        ]
    }

    func mergeFeatureFlags(existing: [String: Any], new: [String: Any]) -> [String: Any] {
        var result = existing
        for (category, flags) in new {
            guard let newFlags = flags as? [String: Any] else { continue }
            if var existingFlags = result[category] as? [String: Any] {
                for (flag, value) in newFlags {
                    existingFlags[flag] = value
                }
                result[category] = existingFlags
            } else {
                result[category] = newFlags
            }
        }
        return result
    }
}
