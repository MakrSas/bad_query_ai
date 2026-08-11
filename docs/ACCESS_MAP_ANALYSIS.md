# ACCESS MAP Analysis

Analysis of the FilzaSlop ACCESS MAP.txt output for iOS 27.0 (Build 24A5390f).

## Exploit Primitives

### Issue A: MobileHouseArrest Identity-Trust Bypass
- **Component**: MobileContainerManager + containermanagerd
- **Trigger**: App signed as `com.apple.mobile.MobileHouseArrest`
- **Effect**: Issues foreign-container sandbox extensions for any valid container identifier

### Issue B: geod Class-12 Lookup Bypass
- **Component**: MobileContainerManager + containermanagerd  
- **Trigger**: Class 12 with identifier `com.apple.geod`
- **Key**: geod is in `ContainerManagerCommon`'s built-in lookup-bypass list
- **Container root**: `/private/var/containers/Data/System/com.apple.geod`
- **Part-domain traversal**: `Library/Caches/../../../../../../` reaches `/var/`, then back into containers

### Issue C: MobileGestalt Group Authorization Gap
- **Component**: MobileContainerManager + containermanagerd
- **Trigger**: Class 13, group `systemgroup.com.apple.mobilegestaltcache`, part 3, flags `0x8100000000`
- **Target**: `/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist`
- **Access**: Full read-write

## Accessible Containers

### Confirmed Read-Write Access

| Container | Class | Root Path | Writable Items |
|-----------|-------|-----------|----------------|
| MobileGestalt Cache | C13 | `.../systemgroup.com.apple.mobilegestaltcache/Library/Caches` | `com.apple.MobileGestalt.plist` |
| InstallCoordination | C13 | `.../systemgroup.com.apple.installcoordinationd/.../InstallCoordination` | `Coordinators/`, `DataPromises/`, `PromiseStaging/` |
| geod System Data | C12 | `/var/containers/Data/System/com.apple.geod` | `Library/Caches/`, `Library/Preferences/` |
| geod → MobileGestalt | C12 | Traversal via `../../../../../../containers/Shared/...` | `com.apple.MobileGestalt.plist` |

### Confirmed Access (Read-Only or Limited)

| Container | Class | Status |
|-----------|-------|--------|
| LiveContainer App Data | C2 | Read via MHA identity |
| SideStore App Group | C7 | Read via MHA identity |
| iconscache System Group | C13 | Read via MHA identity |

### Failed Probes

| Probe | Class | Status |
|-------|-------|--------|
| Eligibility Overrides | C12 | FAILED |
| App Managed Data | C15 | FAILED |
| Configuration Profiles Root | C13 | FAILED |
| Shared Web Credentials Root | C10 | FAILED |
| SpringBoard preferences | — | DENIED (EPERM) |

## Traversal Path Mechanics

From geod class-12 container (`/var/containers/Data/System/com.apple.geod/Library/Caches/`):

```
../../../../../../  =  /var/  (6 levels up from Library/Caches)

Then:
  + containers/Shared/SystemGroup/...  → /var/containers/...  ✓ WORKS
  + db/eligibilityd/                   → /var/db/...           ✗ BLOCKED
  + preferences/FeatureFlags/          → /var/preferences/...  ✗ BLOCKED
```

**Rule**: Containermanagerd allows sandbox extensions ONLY for resolved paths under `/var/containers/`. Any path resolving outside this hierarchy is rejected.

## Rejected Routes

- **ProxyForClient spoof**: Raw containermanagerd command 39 rejected MobileHouseArrest, mobile_installation_proxy, filecoordinationd, accountsd, and Safari.History identities
- **SpringBoard preferences**: `O_RDWR` open returns EPERM even with all MCM routes active
- **Files Traversal**: Disabled in current build

## Implications for AI Enabler

1. **MobileGestalt**: Full control via Issue C — the primary exploit path
2. **Eligibility**: Can READ but NOT WRITE; however, auto-updates after MG spoof
3. **Feature Flags**: Completely unreachable — need alternative approach (private API, config profile, etc.)
4. **AI Assets**: At `/var/MobileAsset/` — unreachable via containermanager

## v8 Implication: Access Is Not Evaluation

The access map establishes where `bad_query` can obtain a sandbox extension; it does not establish which process consumes a value. This distinction is decisive for the FeatureFlags route:

- `bad_query` can load and inspect FeatureFlags symbols in its own process.
- `siriknowledged`, `assistantd`, and SpringBoard perform their own feature checks in separate processes.
- An app-local swizzle or `DYLD_INSERT_LIBRARIES` setting does not automatically alter those already-running Apple daemons.
- The MobileGestalt cache remains the only confirmed system-wide writable input, and its opaque `CacheExtra` hashes must be recovered for the exact iOS 27 build rather than copied from another release.

This is why v8 treats daemon-side loading as a feasibility gate and keeps geod preferences, profiles, and trial state as bounded fallback experiments. See [AI_ENABLER_V8_STRATEGY.md](AI_ENABLER_V8_STRATEGY.md).
