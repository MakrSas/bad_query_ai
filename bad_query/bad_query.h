//
//  bad_query.h
//  bad_query
//
//  Created by Taj C on 7/21/26.
//

#ifndef bad_query_h
#define bad_query_h

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

int64_t bad_query(char* path, bool create, char *group_identifier, bool is_group);
int64_t bad_query_ex(char* path, bool create, char *group_identifier, uint64_t container_class);
char *bad_query_list(char *path, int64_t max_inode);
void bad_query_release(int64_t handle);

// MobileGestalt direct API
void *mg_copy_answer(const char *key);
bool mg_get_bool_answer(const char *key);
void mg_notify_cache_changed(void);

// Feature flags and eligibility private API probing
void post_darwin_notification(const char *name);
char *probe_private_apis(void);
int ff_try_set(const char *subsystem, const char *flag, bool value);
int ff_check(const char *subsystem, const char *flag);
char *siri_gate_probe(void);
char *siri_group_probe(void);
int siri_gate_call_confirmed(int gate_index);
char *siri_gate_code_dump(void);
char *siri_gate_target_dump(void);
char *siri_gate_selector_probe(void);
char *siri_deprecated_dependency_probe(void);
char *siri_refresh_sae_cache(void);
char *siri_refresh_method_dump(void);
char *siri_refresh_call_map(void);
char *siri_availability_probe(void);
char *siri_availability_runtime_map(void);
char *siri_availability_detail_probe(void);
char *siri_preferences_source_map(void);
char *siri_preferences_key_probe(void);
char *siri_preferences_write(int operation);
char *siri_availability_writer_inventory(void);
char *siri_capabilities_client_runtime(void);
char *siri_capabilities_service_sync_probe(void);
char *siri_capabilities_client_call_map(void);
char *siri_capabilities_service_update(void);
char *siri_capability_service_binary_probe(void);
char *siri_capability_service_registration_probe(void);
char *siri_capability_daemon_details(void);

// Eligibility private API
char *elig_probe_domains(void);
int elig_set_input_try(int p1, int p2, int p3);

// MobileGestalt extra key probing
char *mg_probe_extra_keys(void);

#endif /* bad_query_h */
