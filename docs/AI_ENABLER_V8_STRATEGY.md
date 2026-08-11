# AI Enabler v8 Strategy

Date: 2026-08-11  
Device baseline: iPhone 15 (iPhone15,4, A16/t8120/D37AP), iOS 27.0 beta (24A5390f)  
Repository: `MakrSas/bad_query_ai`

## Executive conclusion

The MobileGestalt and eligibility parts of the enablement chain are already working. The remaining blocker is not an eligibility answer:

```text
Siri.sae_override                  = disabled
Siri.assistant_engine_override     = disabled
SiriUI.sae                         = enabled
GREYMATTER                         = ELIGIBLE (answer_t = 4)
```

`_os_feature_enabled_impl` is therefore a useful v8 probe, but it is not a complete solution while it runs only inside `bad_query`. The flag lookup is performed by other processes. The first v8 gate is consequently to establish whether code can be loaded into one of those processes on this device. If that gate fails, spending more time on a process-local hook, guessed eligibility signatures, or writes outside `/var/containers/` cannot unlock Siri.

## Evidence carried forward from v7

- Class-13 MobileGestalt access is read-write and survives a respring, but not a reboot.
- The AI capability and model-spoof keys currently used by the project are confirmed by `MGCopyAnswer`.
- Eligibilityd re-evaluates after the MobileGestalt spoof and changes the generative-model input and GREYMATTER answer automatically.
- `/var/preferences/FeatureFlags/Global.plist` is outside the confirmed containment boundary. The file was also absent during the v6 probe.
- The guessed C ABIs for `os_eligibility_get_domain_answer` and `os_eligibility_set_input` crash the app. They must not be called again until their prototypes are recovered from the exact iOS 27 binaries.
- Several feature-flag and MobileGestalt names copied from older releases or internet tables do not map to the iOS 27 beta device.

These observations make feature-flag evaluation, not eligibility mutation, the correct v8 boundary.

## Route ranking

| Route | What it can change | Priority | Why |
|---|---|---:|---|
| ABI-safe FeatureFlags hook in the app | Only checks made by `bad_query` | P0 diagnostic | Confirms the symbol, ABI, arguments, and return semantics without pretending to affect Siri daemons |
| Injection into the evaluator process | Checks made by `siriknowledged`, `assistantd`, SiriUI, or SpringBoard | P0 feasibility gate | The only direct form of the proposed hook that could affect the real decision |
| Exact iOS 27 MobileGestalt key discovery | Device capability branches before/around feature flags | P1 | The writable surface is real, but opaque hashes from other releases are not evidence |
| Container-local preferences / geod | Preferences visible to a containerized service | P2 | Worth a bounded experiment only if an actual consumer path can be demonstrated |
| Configuration profile | Only payloads supported by an installed profile handler | P3 | A profile cannot arbitrarily write `FeatureFlags/Global.plist`; no blind profile install |
| Trial/experiment or CloudKit state | Server-controlled enrollment | P3 | High noise and cannot be assumed to override a local hard feature flag |
| Eligibility private API/XPC | Eligibility state | P4 | Eligibility is already green; the v7 ABI crash makes brute force unsafe and low value |

## v8 work packages

### v8.0 — Freeze the known-good baseline

Before testing a hook, record one baseline after a clean respring:

1. `MGCopyAnswer` for the four confirmed spoof keys.
2. GREYMATTER answer and the generative-model input from the readable diagnostic plist.
3. The three feature-flag results from `ff_check`.
4. Whether Writing Tools, ChatGPT Extension, and the Siri settings UI are present.
5. A timestamp, OS build, and whether the last transition was a respring or reboot.

The v7 buttons that call guessed eligibility prototypes should be treated as disabled until ABI recovery. A crash in a probe is not a useful negative result and can obscure the state of the working MobileGestalt path.

### v8.1 — Recover the FeatureFlags call contract

The base ABI is now confirmed from open-source WebKit's `FeatureFlagsSPI.h`:

```c
bool _os_feature_enabled_impl(const char *domain, const char *feature);
```

WebKit also documents that both arguments are expected to be compile-time static strings. References: [WebKit bug 208607](https://bugs.webkit.org/show_bug.cgi?id=208607) and [WebKit bug 229017](https://bugs.webkit.org/show_bug.cgi?id=229017).

The v7 four-argument cast has been replaced with this two-argument prototype. The exact iOS 27 beta implementation still needs matching-binary inspection before any machine-code hook is attempted:

- obtain the matching `FeatureFlags` binary or dyld-cache slice;
- inspect exported symbols, symbol stubs, Objective-C metadata, and nearby call sites;
- determine argument registers/stack layout, return type, and whether the subsystem and feature are C strings, `CFStringRef`, or another object type;
- identify the simple implementation separately from the full implementation;
- record whether callers use direct intra-image calls or an imported symbol binding.

The first implementation should be observational: call the original function and log only a normalized copy of the arguments and result. It must tolerate unknown calls and avoid dereferencing unverified pointers. Only after the call contract is proven should the probe return `true` for the two exact Siri flags and delegate all other calls unchanged.

Success for this work package is a crash-free, repeatable override in the `bad_query` process. It is not evidence that Siri has been enabled.

Current v8 diagnostic changes:

- the app reports the three required flags through the corrected two-argument ABI;
- the crash-prone eligibility actions have been removed from the UI and their C entry points made inert;
- the app can dump every `CacheExtra` key with its value type to the log and to `Documents/CacheExtra-latest.{plist,txt}`.
- iOS file sharing and in-place document access are enabled for the generated Info.plist so the snapshots can be retrieved from the app's Documents directory.

### v8.2 — Establish the process boundary

Use the system behavior and available artifacts to identify which process makes each relevant decision. The target list is:

```text
siriknowledged -> assistant engine / Siri feature evaluation
assistantd     -> assistant services, if used by this build
SpringBoard    -> SiriUI presentation and system integration
```

For each process, answer:

- Does it load the same `FeatureFlags` implementation?
- Does it evaluate the two `Siri` flags at startup or on a configuration notification?
- Can a harmless, process-local observation be seen from logs or behavior?
- Is there a supported or already-available loader that can place a test dylib in that process?

`DYLD_INSERT_LIBRARIES` set for the app does not propagate to already-running Apple daemons. TrollStore installation and an app sandbox extension do not, by themselves, grant the ability to inject into those daemons. This is a hard feasibility gate, not an implementation detail.

### v8.3 — Injection feasibility gate

Only pursue a daemon-side hook if a real loading primitive is available on the test device. The test must prove, in this order:

1. The target process loads the test image.
2. The image resolves the exact FeatureFlags symbol without changing unrelated calls.
3. The target flag checks are observed.
4. The two target flags are overridden while all other flags retain their original result.
5. SpringBoard and Siri services remain stable across a respring.

If step 1 cannot be demonstrated without a jailbreak-level or equivalent system modification, mark the hook route as blocked for the current environment. Do not claim success from a hook that only changes the app's own `ff_check` result. Do not use repeated crash-and-respring cycles as a substitute for proving injection.

### v8.4 — Exact MobileGestalt discovery

The existing `CacheExtra` dictionary is a useful writable surface but is not a semantic key database. A key hash alone does not reveal its property name, and the v7 mismatches show that release-specific tables cannot be trusted.

The next MG pass should be differential and release-specific:

- dump and preserve every existing `CacheExtra` key, value type, and value before modification;
- compare a clean cache with the AI-spoofed cache and keep a machine-readable diff;
- extract candidate MobileGestalt property names and call sites from binaries matching build `24A5390f`;
- validate each candidate by reading it through `MGCopyAnswer` before writing it;
- write one candidate at a time, respring, and record eligibility plus Siri behavior;
- keep a rollback copy and reject a candidate when its returned type/value does not match the expected property.

The purpose is to find a capability branch that genuinely controls the consumer. It is not to add a large set of guessed keys. The four confirmed keys remain the only default writes.

### v8.5 — Bounded container-local preference experiment

The geod container is writable, but that does not make its preferences global. Test this route only with a sentinel and a consumer check:

- enumerate the existing geod `Library/Preferences` files and preserve their names, owners, and sizes;
- add no more than one clearly named test value in a copied or otherwise reversible plist;
- check whether any Siri-related daemon reads that exact domain or emits a configuration change;
- remove the sentinel and verify the original state.

An arbitrary `com.apple.siri` plist placed under geod is not evidence of influence. Stop this route if no consumer relationship is observable after one controlled cycle.

### v8.6 — Configuration profiles and experiments

Treat configuration profiles as a compatibility question, not a path traversal. Search the exact iOS 27 profile payload support for a Siri/FeatureFlags handler. If no official payload key maps to the required flags, a handcrafted `mobileconfig` is expected to be ignored or rejected and should not be installed on the primary device.

Likewise, server-side trial or experiment state should be investigated only after local feature-flag and process-boundary evidence exists. Cloud enrollment cannot be assumed to override a disabled local flag and may introduce unrelated account or region changes.

## Recommended execution order

```text
Known-good baseline
       |
       v
Recover exact FeatureFlags ABI
       |
       +--> process-local hook proves semantics
       |
       v
Prove a loader for the actual evaluator process
       |
       +--> no loader: stop daemon-hook route, document blocker
       |
       v
Daemon-side hook, with original-result fallback
       |
       v
If still blocked: exact build-specific MG discovery
       |
       v
One bounded geod/profile experiment, then stop on no consumer evidence
```

## Stop conditions and safety

- Never call an undocumented eligibility symbol with an invented prototype.
- Never overwrite the MobileGestalt cache without a verified backup and a single-candidate diff.
- Keep respring and reboot as separate test states; a reboot invalidates the current MG result.
- Stop the hook track when the target process cannot be loaded. A process-local green result is diagnostic only.
- Stop preference/profile tracks when there is no observable consumer; absence of a file is not proof that creating it will create a new system feature.

## Definition of v8 success

There are two valid outcomes:

1. **Enablement success:** after MG spoof and eligibility are green, the exact two Siri flag checks are observed and overridden inside the actual evaluator process, Siri services remain stable, and Apple Intelligence behavior is verified after a respring.
2. **Bounded blocker:** the app-local hook is proven, but no process-loading primitive exists in the current TrollStore/sandbox environment. The documentation then records the missing capability precisely rather than treating an app-local override as a device-wide result.
