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

GitHub Actions with `xcode-27` runner. Produces unsigned IPA/TIPA for TrollStore sideloading.

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
8. **Swizzle _os_feature_enabled_impl** — hook the check function at runtime to always return true for Siri flags

## Device

- iPhone 15 (iPhone15,4)
- A16 Bionic (t8120, D37AP)
- iOS 27.0 beta (Build 24A5390f)
- TrollStore + LiveContainer
