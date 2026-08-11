# AI Enabler — Apple Intelligence on Unsupported Devices

## Overview

Enables Apple Intelligence features on iPhone 15 (A16 Bionic, iOS 27 beta) using the bad_query sandbox escape exploit. The device requires A17 Pro minimum for native AI support.

## Architecture

Three components must be modified for full Apple Intelligence:

| Component | Path | Access | Status |
|-----------|------|--------|--------|
| MobileGestalt | `/var/containers/.../mobilegestaltcache/.../com.apple.MobileGestalt.plist` | R/W via bad_query | Working |
| Eligibility | `/var/db/eligibilityd/eligibility.plist` | Read-only (auto-updates after MG spoof) | Working |
| Feature Flags | `/var/preferences/FeatureFlags/Global.plist` | No access (outside `/var/containers/`) | Blocked |

## How It Works

### Step 1: MobileGestalt Spoof

Writes to the MobileGestalt cache plist via bad_query class-13 sandbox extension:

```
CacheExtra keys:
  A62OafQ85EJAiiqKn4agtg = 1          (DeviceSupportsGenerativeModelSystems)
  h9jDsbgj7xIVeIQ8S3/X3Q = iPhone16,1 (ProductType → iPhone 15 Pro)
  oYicEKzVTz4/CxxE05pEgQ = D83AP      (HardwareModel)
  5pYKlGnYYBzGvAlIU8RjEQ = t8130      (CPUChip → A17 Pro)
```

After a respring (NOT reboot), `MGCopyAnswer` returns spoofed values.

### Step 2: Eligibility (Automatic)

After MG spoof + respring, `eligibilityd` re-evaluates device capabilities:
- Sees "A17 Pro" via `MGCopyAnswer`
- Sets `OS_ELIGIBILITY_INPUT_GENERATIVE_MODEL_SYSTEM` from 2 → 3
- Sets `OS_ELIGIBILITY_DOMAIN_GREYMATTER` `os_eligibility_answer_t` from 2 → 4 (ELIGIBLE)

No manual write to eligibility.plist is needed.

### Step 3: Feature Flags (Unsolved)

Required flags in `/var/preferences/FeatureFlags/Global.plist`:

```xml
<dict>
    <key>Siri</key>
    <dict>
        <key>sae_override</key>
        <dict><key>Enabled</key><true/></dict>
        <key>assistant_engine_override</key>
        <dict><key>Enabled</key><true/></dict>
    </dict>
    <key>SiriUI</key>
    <dict>
        <key>sae</key>
        <dict><key>Enabled</key><true/></dict>
    </dict>
</dict>
```

This path is outside `/var/containers/` and unreachable via bad_query. v6 attempts alternative methods:
1. dlsym into FeatureFlags framework (`_os_feature_flag_override_set`)
2. NSUserDefaults with multiple suites
3. CFPreferences global/per-domain
4. Direct plist write
5. bad_query traversal
6. Darwin notifications
7. Container scanner for alternative paths

### Step 4: Respring

WebKit crash via 500 divs with `backdrop-filter: blur(100px)` + `navigator.share` spam. Causes SpringBoard to restart without rebooting (which would wipe MG changes).

## Sandbox Boundary

The bad_query exploit can ONLY access paths under `/var/containers/`:

```
Accessible:
  /var/containers/Data/System/          (class 12, geod bypass)
  /var/containers/Shared/SystemGroup/   (class 13)
  /var/mobile/Containers/               (class 2, 7)

NOT accessible:
  /var/db/                              (eligibility, datastore)
  /var/preferences/                     (feature flags)
  /var/mobile/Library/Preferences/      (SpringBoard, system prefs)
  /var/MobileAsset/                     (AI model assets)
```

Confirmed by ACCESS MAP probe 03 (Eligibility Overrides → FAILED) and FilzaSlop testing.

## Key Findings

### Eligibility Blocking Factor
Only ONE input blocks GREYMATTER eligibility:
```
OS_ELIGIBILITY_INPUT_GENERATIVE_MODEL_SYSTEM = 2  (all others = 3)
```
This is resolved automatically when MG spoof makes the device appear as A17 Pro.

### Reboot vs Respring
- **Respring**: Safe. MG daemon re-reads cached plist, spoofed values take effect.
- **Reboot**: Destroys all changes. MG cache is regenerated from real hardware.

### geod Path Traversal (class 12)
The `com.apple.geod` identifier is in ContainerManagerCommon's built-in bypass list. From geod's container, `../../../../../../` reaches `/var/`, then can traverse back into `/var/containers/`. Cannot escape to `/var/db/` or `/var/preferences/` — containermanagerd blocks resolved paths outside `/var/containers/`.

## Build

GitHub Actions with an `xcode-27` runner. Produces unsigned IPA/TIPA; the current device workflow installs the IPA through iLoader.

```
Repository: MakrSas/bad_query_ai
Workflow: .github/workflows/build.yml
```

## Version History

| Version | Focus | Result |
|---------|-------|--------|
| v1-v3 | MobileGestalt spoof | Partial success with Nugget residual state |
| v4 | Eligibility diagnostics | Found GREYMATTER blocking factor (GMS=2) |
| v5 | Eligibility write attempts | All 5 methods failed, but verified eligibility auto-updates |
| v6 | Feature flag attack + container scanner | No set API in FeatureFlags framework; Global.plist absent; container scan empty |
| v7 | Eligibility API attack + MG key probe | CRASH: wrong API signatures; MG key hashes wrong for iOS 27 |
| v8 | FeatureFlags ABI + process-boundary strategy | Strategy documented; daemon injection is the primary feasibility gate |
| v9 | Full iOS 27 MobileGestalt identity spoof | Device-confirmed: all tested identity mirrors changed, but required Siri flags stayed disabled |
| v10 | Complete Siri gate diagnostics | Unsafe private-function calls crashed on 24A5390f; removed in v11 |
| v11 | Siri app-group discovery | Resolves known Siri/Assistant group containers through the class-7 primitive |
| v12 | Siri asset diagnostics | Read-only MobileAsset inventory after partial Apple Intelligence activation |
| v13 | Isolated Siri predicates | Separately invokes two no-argument gates whose calling convention is supported by recovered callsites |
| v14 | Composite Siri gate split | Isolates combined SAE, Siri-UOD, GMS hardware, and full UOD asset status predicates |
| v15 | SAE locale diagnosis + UI cleanup | Removes obsolete/unsafe buttons and adds one consolidated current-gate report |
| v16 | Exact-build SAE code dump | Reads the first 256 bytes of two exported gates for 24A5390f call-graph recovery |
| v17 | Follow SAE branch targets | Decodes export-stub tail branches and dumps their actual destination code |
| v18 | Hidden SAE selector recovery | Resolves Objective-C receiver and selector names behind the iOS 27 export stubs |

## v7 Results

### MG Key Probe
Extra MobileGestalt key hashes (sourced from internet) are WRONG for iOS 27. Returned values from different properties:
- `AlwaysOnAssistant` hash → returned `<type18>` (wrong key, probably a dict)
- `DeviceClassNumber` hash → returned `27.0` (OS version, not device class)
- `HeySiriSupport` hash → returned `LL/A` (region code)
- `NeuralEngine` hash → returned `iPhone` (device marketing name)
- Spoofed keys (AI, ProductType, HardwareModel, CPUChip) all read back correctly

### Eligibility API Crash
Both `os_eligibility_get_domain_answer` and `os_eligibility_set_input` crash the app. The guessed signatures `(int) → int` and `(int, int, int) → int` are wrong. These functions likely take pointer/struct arguments (e.g. `xpc_object_t`, output pointers, or ObjC objects).

### Remaining Blocker
Feature flags `Siri.sae_override` and `Siri.assistant_engine_override` remain DISABLED. No known write path exists within the sandbox boundary.

## Untried Approaches

1. **Reverse-engineer eligibility API** — use `nm -g` on device framework binaries to get real exported symbol signatures
2. **Configuration profile (.mobileconfig)** — may contain payload for feature flags
3. **Geod writable prefs** — `com.apple.geod/Library/Preferences/` is writable; test if any plist there can influence Siri
4. **Trial/experiment system** — Apple's CloudKit A/B testing; could fake a trial enrollment
5. **XPC to eligibilityd** — direct daemon communication with correct entitlements
6. **Find correct MG key hashes** — dump all CacheExtra keys from current plist to find real AI-related keys
7. **NSProcessInfo environment** — some feature flags check env vars at runtime
8. **Swizzle _os_feature_enabled_impl** — first prove the exact ABI in-process, then establish a loader for the actual Siri evaluator; an app-local hook is diagnostic only

## v8 Strategy

The complete v8 plan, priority order, experiments, stop conditions, and success definition are documented in [AI_ENABLER_V8_STRATEGY.md](AI_ENABLER_V8_STRATEGY.md).

The key conclusion is that feature-flag interception is a process-boundary problem. A hook inside `bad_query` cannot change checks made by `siriknowledged`, `assistantd`, or SpringBoard. The first implementation task is therefore ABI-safe, observational FeatureFlags instrumentation; the first production gate is proving that a test image can actually load into the evaluator process on this device. If that gate fails, the remaining realistic writable-surface investigation is exact-build MobileGestalt discovery, not more guessed eligibility or out-of-container plist writes.

### v8 Implementation Progress

- Confirmed `_os_feature_enabled_impl` as `bool(const char *domain, const char *feature)` from open-source WebKit SPI declarations.
- Corrected `ff_check` to use the two-argument ABI.
- Removed the crash-prone eligibility calls from the v8 UI and made their native entry points inert pending exact ABI recovery.
- Added a complete `CacheExtra` snapshot action that logs sorted key/type/value rows and saves XML/text copies in the app's Documents directory.

### v8 Build Verification

- Commit: `af9b0a7` (`v8: safe feature flag diagnostics and CacheExtra dump`)
- GitHub Actions run: [31521456172](https://github.com/MakrSas/bad_query_ai/actions/runs/31521456172)
- Result: successful unsigned iPhoneOS build, IPA/TIPA packaging, and artifact upload.
- Artifacts: `bad_query_ai.ipa` and `bad_query_ai.tipa`, 85,467 bytes each.

## v9 Device-Dump Analysis

The v8 device dump contained 82 `CacheExtra` keys. It proved that the original four-key spoof was internally inconsistent:

- `h9jDsbgj7xIVeIQ8S3/X3Q` (`ProductType`) was spoofed to `iPhone16,1`.
- `oYicEKzVTz4/CxxE05pEgQ` is `TargetSubType`, not the primary hardware-model string.
- `/YYygAofPDbhrwToVsXdeA` (`HWModelStr`) remained `D37AP`.
- `GGIIDN/ANr8X2WrgS6nBYQ` (`HWModelUniqueStr`) remained `D37AP`.
- Eight iOS 26+ ProductType component mirrors remained `iPhone15,4`.
- Eight iOS 26+ HWModel component mirrors remained `D37AP`.

This creates a plausible iOS 27 hard-gate path: eligibility reads the classic spoofed keys and becomes eligible, while a Siri consumer can read a newer component-specific identity and still see the unsupported device.

v9 adds a separate **Apply Full Identity Spoof** action. It preserves the existing backup, writes `iPhone16,1` to the confirmed ProductType mirrors and `D83AP` to the confirmed HWModel mirrors, then requires a respring. Camera/audio-specific mirrors are included, so temporary subsystem instability is possible; reboot remains the hardware-cache rollback path.

Device testing confirmed `HWModelStr=D83AP`, `HWModelUniqueStr=D83AP`, and the tested ProductType mirrors as `iPhone16,1`. `GREYMATTER` and `FOUNDATION_MODELS` remained eligible, while `Siri.sae_override` and `Siri.assistant_engine_override` remained disabled. Therefore inconsistent MobileGestalt identity is no longer the leading blocker.

## v10 Gate Probe

The raw FeatureFlags result does not reveal which combined Siri predicate fails. v10 attempted to call several exported AssistantServices predicates as `bool(void)`.

- `AFDeviceSupportsSystemAssistantExperience`
- `AFDeviceSupportsSAEByDeviceCapabilityAndFeatureFlags`
- `AFLocaleSupportsSAE`
- `AFDeviceSupportsSAE`
- `AFHasGMSCapability` and `AFHasGMSCapabilityUnembargoed`
- `AFDeviceSupportsSiriUOD` and `AFUODStatusSupportedFull`

On 24A5390f, pressing **Probe Complete Siri Gate** terminated the app before producing a report. At least one assumed prototype is therefore invalid or unsafe before framework initialization. This is the same failure class as the v7 eligibility crash: export presence does not establish an ABI.

v11 replaces the action with **Probe Siri Gate Symbols (Safe)**. It only loads the frameworks and reports `PRESENT_NOT_CALLED` or `NO_SYMBOL`; it does not invoke unknown-ABI AssistantServices or MobileGestalt functions. The expanded `_os_feature_enabled_impl(const char *, const char *)` checks remain because that ABI is independently confirmed and already device-tested.

## v11 Siri Container Probe

Build `24A5390f` entitlement diffs identify new and existing Siri application groups under `/var/mobile/Containers/Shared/AppGroup`, which remains inside the broad `/var/containers` filesystem family reachable by the current exploit primitives. v11 performs read-only class-7 lookups for:

- `group.com.apple.assistant.shared` and `.backedup`
- `group.com.apple.siri.inference`
- `group.com.apple.siri.sirisuggestions`
- Siri ASR, recorded-audio, reference-resolution, user-feedback, remembers, and GMS SELF groups

The probe uses `container_copy_path(container, errorOut)` to report the resolved container root and does not alter files. A returned `PATH:` result would establish a new candidate surface for subsequent targeted preference/trial-state inspection; `NO_RESULT` across all groups rules out this class-7 route under the current iLoader-signed identity.

- Commit: `8c53da0` (`v11: make Siri gate probe safe and discover app groups`)
- GitHub Actions run: [31523101781](https://github.com/MakrSas/bad_query_ai/actions/runs/31523101781)
- Result: successful unsigned iPhoneOS build and IPA/TIPA artifact upload.

### v11 device result

All ten Siri/Assistant class-7 app-group queries returned `NO_RESULT`, including `group.com.apple.siri.inference` and `group.com.apple.siri.sirisuggestions`. The iLoader-signed app therefore cannot resolve those foreign app groups through the tested primitive.

The safe symbol inventory completed without a crash. All eight tested AssistantServices gates were exported. The public MobileGestalt Siri-UOD export was present, while its underscore-prefixed form was absent. Expanded FeatureFlags results were:

- disabled: `Siri.sae_override`, `Siri.assistant_engine_override`, `Siri.force_uod_enabled_for_device`, `SiriUI.sae_use_container`
- enabled: `Siri.assistant_engine`, `SiriUI.sae`, `SiriNL.NLRouter`, `GenerativeModels.GenerativeModelsAvailability`, `IntelligenceFlow.IntelligenceFlow`

Device screenshots materially change the diagnosis: the system Writing Tools UI appears, Image Playground reaches its generation UI, the ChatGPT extension is exposed, and Settings describes Siri as powered by Apple Intelligence. However, a long English Writing Tools request returns “Certain capabilities are unavailable at this time,” Image Playground generation fails, and Siri remains on the old experience. Only the UI and routing surfaces are partially enabled; no tested generative operation is confirmed functional. This points to shared model assets/runtime readiness or another downstream policy gate in addition to the narrower SAE/Siri-UOD flags.

## v12 Asset Diagnostics

v12 adds **Probe AI/Siri Assets (Safe)**. It performs no downloads or writes. It checks canonical system and mobile `AssetsV2` roots, distinguishes an absent/invisible path from a readable path and an existing-but-denied directory, and inventories visible Siri, Intelligence, Eligibility, Speech, and Generative asset types. Known Siri/AI asset directories are also queried individually with errors reported by domain and code.

### v12 device result

Both `/var/MobileAsset/AssetsV2` spellings exist but directory enumeration fails with `NSCocoaErrorDomain` code 257 (sandbox denial). Only the OSEligibility child leaks existence; all other child probes are `NOT_VISIBLE`, which cannot distinguish absence from sandbox concealment. Settings reports approximately 7 GB used by Apple Intelligence, so missing all model assets is no longer the leading hypothesis. v12 cannot inspect their composition through the current sandbox.

## v13 Isolated Siri Gates

Recovered iOS 26.1 callsites invoke `AFDeviceSupportsSystemAssistantExperience()` and `AFDeviceSupportsSAEByDeviceCapabilityAndFeatureFlags()` with no arguments. v13 exposes one button per function and never batches them with the six unverified v10 predicates. Each attempt is persisted before invocation so a crash can be attributed to one exact export. Return value `0` or `1` distinguishes the broad System Assistant Experience decision from its device-capability-plus-FeatureFlags sub-gate.

### v13 device result

`AFDeviceSupportsSystemAssistantExperience()` returned `false`, while `AFDeviceSupportsSAEByDeviceCapabilityAndFeatureFlags()` returned `true`. The spoofed device identity and effective FeatureFlags therefore pass the dedicated SAE capability-plus-flags sub-gate. The two disabled override flags are not required when the normal capability path succeeds. The remaining blocker is a higher-level condition inside the composite System Assistant Experience decision.

## v14 Composite Gate Split

v14 added isolated calls for `AFDeviceSupportsSAE`, `AFDeviceSupportsSiriUOD`, `AFHasGMSCapabilityUnembargoed`, and an experimental `AFUODStatusSupportedFull` probe. This separated the combined SAE decision, Siri understanding-on-device support, and unembargoed GMS hardware capability. The UOD-status experiment later proved unsafe on the target build and was removed in v15.

### v14 device result

`AFDeviceSupportsSAE()` returned `false`, while `AFDeviceSupportsSiriUOD()` and `AFHasGMSCapabilityUnembargoed()` returned `true`. Together with v13's capability-plus-flags `true`, the failure is inside an additional combined-SAE condition rather than hardware, GMS embargo, FeatureFlags, or Siri UOD support. Calling `AFUODStatusSupportedFull` terminated the app, so that action is removed and the function is no longer treated as a confirmed Boolean ABI.

## v15 Locale Gate and UI Cleanup

VoiceTriggerUI diagnostics explicitly reference `AFLocaleSupportsSAE()` with no arguments, confirming its calling convention. v15 replaces the unsafe UOD-assets slot with this locale predicate and reports `Locale.current`, preferred languages, and region alongside all previously safe gate results. The UI now keeps only the full identity spoof, eligibility/full status, consolidated current Siri gates, research dumps, safe asset probe, respring, and revert; obsolete partial spoof and completed one-off gate buttons are removed.

### v15 device result

The device reports `en_US`, preferred language `en-US`, region `US`, and `AFLocaleSupportsSAE()=true`. Every isolated known sub-gate is now true: capability-plus-FeatureFlags, Siri UOD, unembargoed GMS hardware, and locale. Nevertheless, both `AFDeviceSupportsSAE()` and `AFDeviceSupportsSystemAssistantExperience()` remain false. The iOS 27 implementation therefore contains at least one additional condition not represented by the recovered iOS 26.1 call graph.

## v16 Exact-Build Code Recovery

v16 adds **Dump SAE Gate Code (Safe)**. It resolves but does not invoke `AFDeviceSupportsSAE` and `AFDeviceSupportsSystemAssistantExperience`, strips arm64e function-pointer authentication when required, reports image-relative addresses, and copies the first 256 executable bytes as hex. The dump is intended for offline ARM64 disassembly to identify exact 24A5390f branch targets and the unknown additional predicate without another guessed private call.

### v16 device result

ARM64 disassembly proved both exports begin with resolver/dispatch stubs rather than their Boolean implementation. Their non-local tail branches target `0x1a8fc88d0` and `0x1a8fcd3e0` in that launch. Bytes after the short stubs belong to unrelated adjacent functions, so the initial 256-byte snapshots cannot reveal the composite gate.

## v17 Branch-Target Recovery

v17 adds **Dump SAE Branch Targets (Safe)**. It decodes direct ARM64 unconditional branch instructions in each stub, skips local control-flow edges, uses `dladdr` to identify every non-local destination, and copies 512 bytes from each destination for offline disassembly. No destination is invoked.

### v17 device result

The common branch resolves to exported `AFDeviceSupportsSAEDeprecated`. The active branches land in stripped 16-byte Objective-C message-send stubs: each loads a selector address, tail-calls a common dispatch function, and ends in trap padding. They are not Boolean implementations and explain why `dladdr` had no name.

## v18 Hidden Selector Recovery

v18 decodes the active export stubs directly: the receiver GOT entry from `ADRP/LDR`, the message stub from the direct branch, and the selector C string from its `ADRP/ADD`. It reports `receiver class + selector` for both false gates without sending either message. The obsolete raw code-dump buttons are removed from the UI.

## Device

- iPhone 15 (iPhone15,4)
- A16 Bionic (t8120, D37AP)
- iOS 27.0 beta (Build 24A5390f)
- iLoader sideloading (no TrollStore on iOS 27)
