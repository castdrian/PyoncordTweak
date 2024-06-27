#import <Orion/Orion.h>
#import "fishhook.h"

const char * const _Nonnull get_install_prefix(void) {
    return THEOS_PACKAGE_INSTALL_PREFIX;
}

static NSDictionary *stripGroupAccessAttr(CFDictionaryRef attributes) {
    NSMutableDictionary *newAttributes = [[NSMutableDictionary alloc] initWithDictionary:(__bridge id)attributes];
    [newAttributes removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
    return newAttributes;
}

static void *SecItemAdd_orig;
static OSStatus SecItemAdd_replacement(CFDictionaryRef query, CFTypeRef *result) {
	NSDictionary *strippedQuery = stripGroupAccessAttr(query);
	return ((OSStatus (*)(CFDictionaryRef, CFTypeRef *))SecItemAdd_orig)((__bridge CFDictionaryRef)strippedQuery, result);
}

static void *SecItemCopyMatching_orig;
static OSStatus SecItemCopyMatching_replacement(CFDictionaryRef query, CFTypeRef *result) {
    NSDictionary *strippedQuery = stripGroupAccessAttr(query);
	return ((OSStatus (*)(CFDictionaryRef, CFTypeRef *))SecItemCopyMatching_orig)((__bridge CFDictionaryRef)strippedQuery, result);
}

static void *SecItemUpdate_orig;
static OSStatus SecItemUpdate_replacement(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
	NSDictionary *strippedQuery = stripGroupAccessAttr(query);
	return ((OSStatus (*)(CFDictionaryRef, CFDictionaryRef))SecItemUpdate_orig)((__bridge CFDictionaryRef)strippedQuery, attributesToUpdate);
}

__attribute__((constructor)) static void init() {
	orion_init();

	rebind_symbols((struct rebinding[3]) {
			{"SecItemAdd", SecItemAdd_replacement, (void *)&SecItemAdd_orig},
			{"SecItemCopyMatching", SecItemCopyMatching_replacement, (void *)&SecItemCopyMatching_orig},
			{"SecItemUpdate", SecItemUpdate_replacement, (void *)&SecItemUpdate_orig}
		}, 3);
}
