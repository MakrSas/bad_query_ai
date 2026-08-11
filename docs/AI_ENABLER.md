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
| v19 | Deprecated SAE dependency recovery | Decomposes the cached device-support source into its three internal predicates |
| v20 | Refresh stale SAE cache | Calls the known cache refresh method and posts its three observed Darwin notifications |
| v21 | Exact SAE refresh IMP dump | Captures the iOS 27 manager refresh implementation for offline disassembly |
| v22 | SAE refresh call map | Resolves every direct call and Objective-C selector used by the iOS 27 refresh IMP |
| v23 | Siri availability inspection | Reads the live capability structure and names its missing SAE bits |
| v24 | Siri availability runtime map | Enumerates the new availability object's methods, properties, and ivars |
| v25 | Availability source details | Compares live and preference-backed objects, reasons, modes, and missing capabilities |
| v26 | Siri preference source map | Recovers the preference API and storage-facing selectors behind `fromPreferences` |
| v27 | Siri preference key recovery | Decodes key/context objects, reads the raw value, and inventories setter exports |
| v44 | Siri lifecycle-surface map | Read-only inventory of AssistantServices selectors potentially reached by a system Settings action; no daemon, XPC, or preference operation is invoked |
| v45 | Siri Settings lifecycle chain | Read-only call map for exact Siri enablement/language setters and their notification handlers; no selector is invoked |

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

### v18 device result

`AFDeviceSupportsSAE` dispatches to `+[AFSystemAssistantExperienceStatusManager deviceSupportsSAE]`; `AFDeviceSupportsSystemAssistantExperience` dispatches to `+[AFSystemAssistantExperienceStatusManager isSAEEnabled]`. Recovered iOS 26.1 implementation shows both are cached fields. Cache refresh sources `deviceSupportsSAE` from `AFDeviceSupportsSAEDeprecated()` and derives `saeEnabled` by ANDing that value with the System Assistant Experience feature flag. The successful newer capability-plus-flags predicate is therefore not the value currently feeding this cache.

## v19 Deprecated Gate Dependencies

Exact-build v17 bytes show `AFDeviceSupportsSAEDeprecated()` computes the AND of three internal calls before logging. v19 reports the three direct branch targets, their nearest exported symbols, and the static string passed to the third dependency. It also adds the deprecated gate itself to the consolidated Boolean report. No dependency is invoked by the identification action.

### v19 device result

`AFDeviceSupportsSAEDeprecated()` returned `true`. Its first two dependencies resolve exactly to the already-true `AFDeviceSupportsSAEByDeviceCapabilityAndFeatureFlags` and `AFLocaleSupportsSAE`; the third stripped function also returned true as part of the final AND. Despite this, cached `AFDeviceSupportsSAE` and System Assistant Experience remained false. The blocker is therefore stale manager state, not a failed capability predicate.

## v20 SAE Cache Refresh

v20 calls the recovered instance method `-[AFSystemAssistantExperienceStatusManager fetchGenerativeModelsAvailability]` in the app process, records `AFDeviceSupportsSAE` and System Assistant Experience before and after, and posts the three Darwin notifications observed in the manager implementation: Siri orchestration capabilities, GMS availability, and GreyMatter eligibility change. This tests whether the now-true deprecated gate can update the cache and asks listening Siri processes to perform the same refresh. The completed selector/dependency research buttons are removed from the UI.

### v20 device result

The method was present and called, and all three `notify_post` operations returned success. Nevertheless, both cached values stayed false before and after refresh. The target iOS 27 implementation therefore does not populate the cache exactly like the recovered iOS 26.1 method, or it incorporates an additional availability input. Notification delivery is not the immediate blocker.

## v21 Exact Refresh Implementation

v21 resolves the Objective-C instance method at runtime with `class_getInstanceMethod`, strips arm64e authentication from its IMP, reports its exact image-relative address and type encoding, and copies 1536 bytes for offline ARM64 disassembly. This is read-only and does not invoke the IMP. The goal is to recover the exact values written by 24A5390f rather than continue from the older implementation.

### v21 analysis

The captured IMP confirms a structural change in iOS 27. It first obtains a generative-models availability object, reads status enums and two packed bit fields, compares them with six cached manager properties, and then calls six setters. The cached device-support value is derived from one packed field equaling `0x27`, not directly from `AFDeviceSupportsSAEDeprecated`. This explains why the deprecated gate is true while the refreshed cache remains false.

## v22 Refresh Call Map

v22 scans the exact IMP through its return instruction, decodes every direct `BL`, recognizes stripped Objective-C message-send stubs, and reconstructs their selector strings. It reports a compact offset-to-selector/symbol map and removes the obsolete 1536-byte dump action from the UI. This should identify the availability provider, field getters, and the setter receiving the failing bitmask.

### v22 device result

The refresh obtains `fetchSiriAvailability`, reads `allCapabilities`, `desiredOrchestrationMode`, and `isAvailable`, then writes six cache fields. Disassembly and selector mapping establish the exact device-support formula: the system-assistant capability word must contain every bit in `0x27`; visual intelligence independently requires `0x1f`. The current device fails the former comparison.

## v23 Live Availability Structure

v23 invokes the now-identified safe getters, captures the five-word `allCapabilities` structure using the arm64 large-structure return convention, reports orchestration mode and availability, and uses exported `NSStringFromAFSiriSystemAssistantExperienceCapabilities` / `NSStringFromAFSiriVisualIntelligenceCapabilities` formatters to name present and missing bits. The completed call-map action is removed from the UI.

### v23 device result

The live system-assistant word is `0x34`; required mask `0x27` is missing `0x3`. Apple's formatter names those missing bits `DeviceCapable` and `GrayMatterFeatureFlagEnabled`. Language support, GMS availability, and the user setting are present. Visual intelligence is `0x1e` of required `0x1f`, independently missing only `DeviceCapable`. Desired orchestration mode is `2`, while availability itself reports true.

## v24 Availability Runtime Metadata

v24 enumerates all methods, class methods, properties, and ivars of the exact-build `AFSiriAvailability` object, including Objective-C type encodings and ivar offsets. This determines whether the two missing bits have direct getters/setters or whether their source must be recovered from the manager's `fetchSiriAvailability` implementation. The action is read-only.

### v24 device result

`AFSiriAvailability` is an immutable 120-byte value object. Its `AFSiriAllCapabilities` ivar begins at offset 80 and names the five words as full-UOD, hybrid, SAE, Linwood, and visual-intelligence capabilities. It exposes no setters, but it does expose detailed reason/mode getters, `toDictionary`, `dumpDescription`, `missingDesiredCapabilitiesFor:`, and a class factory `fromPreferences`.

## v25 Live vs Preferences

v25 compares the manager's live `fetchSiriAvailability` object with `+[AFSiriAvailability fromPreferences]`. It reports status, restriction and unavailability masks, all orchestration modes, boot freshness, Linwood predicates, all five capability words, serialized dictionaries, dump descriptions, and missing-capability objects for modes 2 through 5. This is read-only and determines whether a persistent preference representation can carry the required `0x3` bits.

### v25 device result

Live and preference-backed objects are byte-for-field equivalent and from the current boot. Status is Enabled with no restriction or unavailability reason, but desired/current mode is FullUOD (`2`), not SAE (`4`). Mode 2 has no missing capabilities; mode 4 is missing only `DeviceCapable` and `GrayMatterFeatureFlagEnabled`. The system is therefore persistently selecting the old orchestration mode rather than failing global availability.

## v26 Preference Source Recovery

v26 maps the exact `+[AFSiriAvailability fromPreferences]` implementation, resolves Objective-C selectors and direct symbols, and enumerates availability/orchestration/capability-related methods on `AFPreferences`-family classes. It is read-only. The goal is to identify the actual persisted key/domain and whether a supported setter exists before attempting any mutation.

### v26 device result

`fromPreferences` calls `_AFPreferencesValueForKeyWithContext(key, context, 0)` and passes the returned dictionary to `+[AFSiriAvailability fromDictionary:]`. No availability setter is exposed by `AFPreferences`; `setCompanionDesiredOrchestrationMode:` is a separate companion-device preference and is not the capability dictionary.

## v27 Key, Context, and Setter Inventory

v27 decodes the two static CF/Objective-C objects loaded into `x0` and `x1` before `_AFPreferencesValueForKeyWithContext`, prints their descriptions, invokes only the confirmed reader with the same arguments to show the raw dictionary, and checks likely symmetric setter symbol names with `dlsym` without calling them. This establishes the exact preference identity and whether a direct private setter exists.

### v27 device result

The persistent object is `SiriAvailability` in context `com.apple.assistant.backedup`. Its dictionary exactly matches the v25 preference object. Both `_AFPreferencesSetValueForKeyWithContext` and the shorter `_AFPreferencesSetValueForKey` are exported on build 24A5390f.

## v28 Controlled Availability Write

v28 adds three focused actions. **Verify Siri Preference Setter** writes the current dictionary unchanged and reads it back, isolating the private setter ABI before any semantic change. **Apply SAE Availability** saves a durable backup in the app preferences, changes SAE capabilities from `0x34` to `0x37`, visual capabilities from `0x1e` to `0x1f`, and changes desired/current orchestration mode from FullUOD (`2`) to SAE (`4`). **Restore Siri Availability** writes the saved dictionary back. Every operation reports complete before/after dictionaries and `readbackEqual`; Verify must be run first, and Apply must not be run if verification crashes or fails equality.

### v28 setter verification result

The unchanged-write test completed without a crash and returned `readbackEqual=1`. The before and after dictionaries are identical, confirming the argument order and callable ABI of `_AFPreferencesSetValueForKeyWithContext` on build 24A5390f. The controlled SAE mutation can now be tested; its readback must be inspected before notifications or respring are used.

### v28 apply result

The controlled mutation succeeded and returned `backup=SAVED` and `readbackEqual=1`. The persisted SAE capability word changed from decimal `52` (`0x34`) to `55` (`0x37`), visual intelligence from `30` (`0x1e`) to `31` (`0x1f`), and current/desired/desired-if-enabled orchestration modes all changed from FullUOD (`2`) to SAE (`4`). Availability remains enabled with no restriction or unavailability reasons. No notification, cache refresh, or respring had been performed when this result was captured.

### v28 gate result after apply

Without a refresh or respring, all isolated Siri gates changed to true, including `AFDeviceSupportsSAE` and `AFDeviceSupportsSystemAssistantExperience`. The live availability object reports SAE capabilities `0x37`, visual capabilities `0x1f`, desired orchestration mode `4`, and no missing system or visual capabilities. This confirms that `SiriAvailability` was the final in-process software gate and that the two previously disabled feature-flag results are represented by the persisted `GrayMatterFeatureFlagEnabled` capability bit rather than requiring direct FeatureFlags plist access.

### v28 result after respring

After respring, `AFDeviceSupportsSAE` and `AFDeviceSupportsSystemAssistantExperience` returned false again while the lower-level device, locale, GMS, and deprecated gates remained true. Siri retained the classic orb UI and Writing Tools still reported unavailable capabilities. The Siri startup path therefore recomputes and replaces the patched `SiriAvailability`; a preference write before respring is not persistent across the daemon startup refresh. The next test must apply the known-good dictionary after startup and notify already-running consumers, without another respring.

### v28 post-startup apply and refresh result

Applying after startup and then calling the recovered refresh method changes its cached gates from false to true. The patched `0x37`/`0x1f` capability words and mode `4` survive that refresh, and all three Darwin notifications are posted successfully. SpringBoard nevertheless continues to present the classic Siri orb, showing that the app-process manager is correct while an external Siri consumer retains or independently computes old availability.

## v29 Availability Writer Discovery

v29 adds a read-only runtime inventory of loaded Siri/Assistant/Availability classes and their availability, capability, orchestration, fetch, refresh, update, and save methods. It does not invoke discovered methods. The goal is to identify the producer or XPC-facing manager that rewrites `SiriAvailability` at startup and supplies external Siri processes. Completed CacheExtra/MG and setter-verification controls are removed from the main UI.

### v29 device result

The inventory identified the cross-process availability path: `SOSiriCapabilitiesServiceClient` exposes `requestSiriAvailabilityWithCompletion:`, while `AFSiriCapabilitiesServiceClient` exposes `updateCapabilities:`. It also confirmed `AFSystemAssistantExperienceStatusManager` has explicit `siriAvailability`, `setSiriAvailability:`, and `fetchSiriAvailability` methods. The `SO` availability object has four capability words versus five in the local `AF` representation, indicating a service-boundary conversion rather than all consumers reading the backed-up preference directly.

## v30 Capability Client Runtime

v30 reports the complete instance/class method lists, properties, ivars, superclass, and instance size for the SO client, AF client, and status manager. It does not instantiate clients or call blocks. This determines their supported constructors/singletons and connection ownership before making an asynchronous XPC availability request.

### v30 device result

Both service clients are simple `NSObject` subclasses with one retained `NSXPCConnection` ivar and no custom constructor or singleton. The AF client provides safe synchronous getters for SAE enabled, asset-download eligibility, and Siri-with-App-Intents enabled. The SO client provides the asynchronous full availability request. This allows the external service state to be queried without guessing a block callback signature.

## v31 Synchronous Capability Service Query

v31 instantiates `AFSiriCapabilitiesServiceClient` with inherited `init` and invokes its three exact-ABI synchronous boolean getters. It reports SAE enablement, whether SAE assets should download, App Intents enablement, and the XPC connection object before and after. The probe performs no update or preference mutation.

### v31 device result

The client connected successfully to `com.apple.siri.orchestration.capabilities`, but the service returned false for SAE, asset-download eligibility, and App Intents. This proves the remaining mismatch is across the capability-service boundary: the app-local status manager can be made fully SAE-capable while SpringBoard's service remains in the classic state.

## v32 Capability Client Call Map

v32 decodes the direct calls and Objective-C selector stubs in `-[AFSiriCapabilitiesServiceClient updateCapabilities:]` and `-[SOSiriCapabilitiesServiceClient requestSiriAvailabilityWithCompletion:]`. It does not invoke either method. The output identifies the remote selector and completion plumbing needed for a correctly typed service refresh/request.

### v32 device result

Both client methods obtain a remote proxy through `serviceWithErrorHandler:` and forward to a remote method with the same selector. Their wrapper layouts are effectively identical and include local `NSError` construction for transport failures. `updateCapabilities:` therefore takes a one-object completion/error callback rather than a capability payload.

## v33 Capability Service Refresh

v33 invokes the confirmed `updateCapabilities:` client method with a one-object completion block, waits at most eight seconds, reports the callback value or timeout, and then queries the three synchronous service booleans again. The intended sequence is Apply SAE Availability, Refresh SAE Cache, then this service update, without respring.

### v33 device result

The callback completed immediately with Cocoa error 4099 wrapping Mach lookup error 159: sandbox restriction while connecting to `com.apple.siri.orchestration.capabilities`. The three synchronous getters consequently returned false fallbacks rather than authoritative service values. Repeating the call produced the same result. Because iLoader performs ordinary Apple-ID sideload signing, a private mach-lookup entitlement is not a viable assumption; investigation returns to the service's persistent capability inputs.

## v34 Capability Service Binary Discovery

v34 checks likely system locations for the standalone capability XPC service or owning daemon. For any readable executable found, it extracts printable strings containing Siri, SAE, Linwood, Grey/Gray Matter, feature-flag, capability, orchestration, device-capable, or availability terms. This is a read-only scan intended to recover the service implementation's preference keys and upstream inputs without requiring Mach lookup access.

### v34 device result

None of the guessed standalone XPC, framework plug-in, or `/usr/libexec` executable paths exists. The service is therefore likely registered by launchd inside a differently named Siri daemon or framework support executable.

## v35 Capability Service Registration Locator

v35 scans readable system LaunchDaemon and LaunchAgent plists for the exact Mach service name, and recursively inventories Siri/Assistant/Orchestration-named entries under system frameworks and `/usr/libexec`. It is read-only and intended to recover the owning executable path before scanning that exact binary.

### v35 device result

The exact Mach service appears in three launch daemon registrations: `com.apple.siriknowledged.plist`, `com.apple.generativeexperiencesd.plist`, and `com.apple.assistantd.plist`. The framework inventory also confirms the real AssistantServices `assistantd` support executable and dedicated SiriAvailability and SiriOrchestrationServices frameworks. The previous misses were path guesses, not absence of the service implementation.

## v36 Capability Daemon Details

v36 parses and prints the three exact launchd dictionaries, extracts each daemon executable from `Program` or `ProgramArguments`, and scans those binaries for Siri/SAE/feature/capability/orchestration strings. This identifies launch conditions, the active owner, and likely upstream keys without invoking or messaging any daemon.

### v36 device result

The iPhone implementation is in `/System/Library/PrivateFrameworks/AssistantServices.framework/assistantd`. Its `ADSiriCapabilitiesStore` updates Siri availability and logs the individual GMS-capable, SAE-override, NL-router, asset, and feature-flag inputs. Most importantly, the executable imports the dedicated `_AFPreferencesSetSiriAvailability` function, while the XPC endpoint is accepted by `ADDaemon`. `generativeexperiencesd` primarily exposes UAF asset paths and generative settings.

## v37 Dedicated Availability Setter Map

v37 resolves likely exported spellings of the dedicated Siri availability setter, reports its image/offset, decodes direct call and selector targets, and includes a compact exact-build code dump. It does not invoke the setter. The goal is to recover its argument ABI and determine whether it publishes the capability-change notification missing from the generic preference write.

### v37 device result

`_AFPreferencesSetSiriAvailability` is exported at AssistantServices offset `0x8d3f8`. Re-analysis after the v38 crash shows that the instruction at `+0x10` is an unconditional tail branch, not a call. The setter is only a short thunk that forwards `x0` plus static key/context arguments to the generic preference setter. Bytes from `+0x14` onward belong to the adjacent function; the apparent synchronize/notification calls were not part of this setter.

## v38 Dedicated Availability Apply

v38 creates the known-good patched preference dictionary, obtains a validated `AFSiriAvailability` through `fromPreferences`, passes it to `_AFPreferencesSetSiriAvailability`, reads it back, and refreshes the local status manager. It reports the complete before/after objects and final local SAE booleans. No respring or direct XPC lookup is used.

### v38 device result and correction

The dedicated call crashed because the thunk expects the raw preference dictionary, not an `AFSiriAvailability` object. The verified generic apply completed before that call, so no malformed value was written. The dangerous action is removed in v39. This also establishes that the dedicated symbol offers no cross-process synchronization advantage over v28.

## v39 Safe Diagnostics and Daemon-Restart Test

v39 removes the crashing dedicated-setter action and retains only the verified dictionary apply/restore and read-only diagnostics. A respring restarts SpringBoard but can leave `assistantd` alive with its pre-spoof MobileGestalt/feature cache. The next system-level test is a full reboot with the persistent MobileGestalt spoof in place, followed by gate and availability inspection before any manual preference patch.

### v39 full-reboot result

A full reboot regenerated the hardware-derived MobileGestalt cache and removed the session spoof. The resulting gates were all false at the identity-dependent layers: `SAEByDeviceCapabilityAndFeatureFlags`, `HasGMSCapabilityUnembargoed`, and `DeviceSupportsSAEDeprecated`, as well as the final SAE/system-experience gates. This proves the current exploit's MobileGestalt write survives respring but not boot. It also explains the impasse: respring preserves the spoof but need not restart `assistantd`; reboot restarts `assistantd` but destroys the spoof before it can be observed.

The remaining viable technical paths are: a persistent write to the underlying MobileGestalt source rather than `CacheExtra`; a permitted way to restart `assistantd` while the session spoof remains in place; or an Apple-granted/private Mach lookup entitlement for the capability service. A normally iLoader-sideloaded app has none of these privileges, and direct capability-service update attempts are rejected with sandbox error 159.

## v40 Feature-Input Runtime Map

v40 inspects the runtime metadata of the exact `assistantd` capability inputs named in its binary strings: `SAEFeatureFlagSet`, `AFFeatureFlags`, and `GMAvailabilityWrapper`. It lists methods, class methods, properties, and ivars without creating objects or calling private selectors. This is the remaining low-risk route to find a writable in-process preference/input API that avoids direct access to the protected FeatureFlags plist.

### v40 device result

`SAEFeatureFlagSet` is not loaded in the sideloaded app. `AFFeatureFlags` exposes a large set of class-level feature getters, including SAE, SiriX, NL Router, assistant-engine, Linwood, and UOD getters, but no relevant setter; the sole exposed setter concerns location-search continuity. `GMAvailabilityWrapper` exposes read/update APIs for Apple Intelligence eligibility, asset readiness, access restriction, and opt-in state, but no direct capability-bit setter. No immediate writable feature-flag route was found.

## v41 Feature-Input Values

v41 calls only exact no-argument boolean getters already enumerated in v40. It records the core `AFFeatureFlags` values and `GMAvailabilityWrapper` eligibility/visibility values plus its availability enum. Run it after applying the session MobileGestalt spoof, before respring, to distinguish the current-process inputs from the stale daemon state. It performs no mutation.

### v41 device result

Before respring, MobileGestalt still reported the original iPhone 15 identity even after the CacheExtra file was written and notified. All relevant `AFFeatureFlags` getters were already true, but `GMAvailabilityWrapper` reported device ineligible, unavailable, and not ever available. This shows the remaining false input is the stale live MobileGestalt/eligibility view, not a disabled local feature flag. Respring reloads that view in new processes but leaves the already-running Siri daemons stale.

## v42 Siri Daemon Control Probe

v42 lists only the PIDs visible to the app for `assistantd`, `siriknowledged`, `generativeexperiencesd`, and SpringBoard, then calls `kill(pid, 0)` as a non-mutating permission check. It never sends a real signal. The result determines whether a later, separately authorised daemon-restart test can reload session-spoofed MobileGestalt without a device reboot.

### v42 device result

`proc_listpids` failed with `EPERM`, so the sideloaded sandbox cannot enumerate daemon PIDs. No signal was attempted. A direct PID-based restart is not available unless a separate process-control capability can be established.

## v43 Daemon Restart Capability Probe

v43 checks only whether standard `killall`/`launchctl` paths exist and whether the current sandbox reports `process-exec` or generic signal operations as allowed. It does not launch a command or send a signal. This completes the process-control feasibility check before any user-mediated daemon restart attempt is considered.

### v43 device result

Neither `/usr/bin/killall` nor either checked `launchctl` path exists. The sandbox denies both `process-exec` and generic signal operations. Together with v42's `proc_listpids` `EPERM`, this proves that the iLoader-sideloaded process cannot restart, signal, or enumerate Siri daemons. The session MobileGestalt spoof / stale-daemon cycle cannot be broken with process control from this app.

## v44 Siri Lifecycle-Surface Map

v44 is a read-only recovery step for the remaining process boundary. It enumerates only classes compiled into `AssistantServices.framework` and filters their declared selectors for lifecycle-relevant terms: availability, capability, language/locale, asset/download, orchestration, refresh/reload/update/reset, preferences, and notifications. It does not instantiate an XPC client, invoke a selector, change a preference, or interact with any daemon.

The purpose is to identify the exact system-owned Settings action worth testing after the session spoof is active. A Settings action may be privileged to request a capability refresh where the sideloaded app is denied Mach lookup (error 159). It is not evidence that the sideloaded app itself has gained that entitlement.

### Manual lifecycle test order

1. Apply the full MobileGestalt spoof and the already verified `SiriAvailability` write.
2. Respring; do not reboot.
3. Enable the user-visible Developer `Internal Features` UI, then look specifically for a Siri/Apple Intelligence/System Assistant Experience/asset/capability setting.
4. Use v44 before calling an unfamiliar private selector. Compare its selector list with the label of any system Settings control discovered.
5. After one deliberate Settings action, immediately capture Current Siri Gates and Siri Availability. A real hit must remain true after the system action, not merely inside the app's local cache.

### v44 device result

The Developer `Internal Features` UI exposed no relevant Apple Intelligence or System Assistant Experience control. The runtime map instead identified two normal Siri Settings paths with exact Objective-C type encodings:

- `AFPreferences -setAssistantIsEnabled:` (`v20@0:8B16`) together with `_registerForAssistantEnablementChangeNotifications` and `_assistantEnablementDidChangeExternally`;
- `AFPreferences -setLanguageCode:` (`v24@0:8@16`) together with `_registerForLanguageCodeChangeNotifications`, `_languageCodeDidChangeExternally`, and `synchronizeVoiceServicesLanguageCode`.

These are stronger lifecycle candidates than Developer-only UI toggles: their real Settings controls must propagate a change to the Siri stack. The next experiment must use Settings, not an app-local invocation: apply the session spoof and availability write, respring, then perform exactly one reversible action (first disable/enable Siri; separately, change Siri language and return it to `en-US`). Do not reboot. After each action, test the visual Siri UI and capture Current Siri Gates plus Siri Availability.

### Follow-up after Siri off/on

The user performed the disable/enable Siri test, not a language change. Afterwards `SAEByDeviceCapabilityAndFeatureFlags` and `HasGMSCapabilityUnembargoed` remained true, but the persisted availability object contained only `LanguageIsSupported` in its system capabilities (`0x4`) and only `FormFactorSupported | NotCameraRestricted` in its visual capabilities (`0xa`). The previously patched DeviceCapable, GrayMatter, setting, and Apple Intelligence use-case bits were removed.

This proves a normal Settings action reaches a system-owned capability recomputation, but that recomputation consumes a source that still evaluates this physical device as non-capable. It is therefore not a way to preserve a forged `SiriAvailability` object. v45 maps the exact setters and external-notification handlers without invoking them, to recover the daemon-side writer/notification chain before trying another lifecycle action.

### v45 device result

`AFPreferences -setAssistantIsEnabled:` calls a contextual preferences object (`initWithInstanceContext:` then `setAssistantEnabled:`), a barrier, and `_AFPreferencesSetValueForKeyWithContext`; its local companion does the same. The external enablement handler first performs `AFBackedUpPreferencesSynchronize`, obtains `assistantIsEnabled` and `dictationIsEnabled`, then fan-outs local observers. It does not call `AFSiriCapabilitiesServiceClient`, `updateCapabilities:`, `fetchSiriAvailability`, a MobileGestalt reload, or any launchd/process API.

The language route is also not a capability refresh: `setLanguageCode:` writes contextual preferences and synchronizes; `synchronizeVoiceServicesLanguageCode` selects an output voice and conditionally queries `AFDeviceSupportsSystemAssistantExperience`. Its external handler synchronizes backed-up preferences and posts local Foundation notifications. A Siri language change is therefore not a distinct route to restart or reconfigure `assistantd` and should not be repeated as an enablement experiment.

The remaining useful read-only task is to recover the static preference key/context arguments at each `_AFPreferencesSetValueForKeyWithContext` call, then establish whether the daemon's capability writer subscribes to one of those backed-up preference domains or instead uses an independent identity source.

## Reassessment of Related bad_query PoCs

The four public PoCs were checked against the established iLoader boundary:

| PoC | Confirmed scope | Effect on Siri path |
|---|---|---|
| MobileHouseArrest | Foreign app-data/app-group containers only; its special route requires the CodeDirectory identity `com.apple.mobile.MobileHouseArrest` | Does not provide `/var/preferences`, a Siri daemon entitlement, or process control. The class-13 MobileGestalt route is already used by this project and does not require that identity. |
| Geod-MCM | A lexical traversal from geod to the same fixed MobileGestalt cache directory under `/var/containers` | Already subsumed by the working class-13 route; it is not arbitrary `/var` access. |
| CFPrefsZeroFile | `cfprefsd` can create one selected missing, root-owned, zero-byte file through a race | Cannot replace, truncate, or supply contents for an existing FeatureFlags or Siri plist. It is not an enablement route and risks a denial of service if misused. |
| InstallCoordination | Attacker-controlled persisted install state can cause `installcoordinationd` to follow a final symlink; the public PoC demonstrates only a scratch target in its own system group | This is the only unclosed candidate, but no proof yet establishes a safe write to a Siri preference or MobileGestalt's hardware source. Do not target a real system plist without a recoverable, separately approved validation plan. |

## Current Boundary

The remaining blocked boundary is no longer a discovered flag or preference. Achieving a persistent system-wide Siri state needs one of: (1) a write primitive for MobileGestalt's real hardware source rather than its boot-regenerated CacheExtra; (2) a jailbreak/root/launchd capability to restart `assistantd` after the session spoof; or (3) an Apple/private entitlement granting Mach lookup to `com.apple.siri.orchestration.capabilities`. Standard iLoader signing provides none of these; its sandbox explicitly rejects the XPC and process-control options.

## Device

- iPhone 15 (iPhone15,4)
- A16 Bionic (t8120, D37AP)
- iOS 27.0 beta (Build 24A5390f)
- iLoader sideloading (no TrollStore on iOS 27)
