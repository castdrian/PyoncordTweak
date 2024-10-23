// Adapted from https://github.com/dayanch96/YTLite/blob/main/Sideloading.x the dev is a prick though so go look up the license yourself, ps. the matrix dude is also a twat
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>

#define DISCORD_BUNDLE_ID @"com.hammerandchisel.discord"
#define DISCORD_NAME @"Discord"

@interface SSOConfiguration : NSObject
@end

%group gSideloading
// Keychain patching
static NSString *accessGroupID() {
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
                           (__bridge NSString *)kSecClassGenericPassword, (__bridge NSString *)kSecClass,
                           @"bundleSeedID", kSecAttrAccount,
                           @"", kSecAttrService,
                           (id)kCFBooleanTrue, kSecReturnAttributes,
                           nil];
    CFDictionaryRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
    if (status == errSecItemNotFound)
        status = SecItemAdd((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
        if (status != errSecSuccess)
            return nil;
    NSString *accessGroup = [(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kSecAttrAccessGroup];

    return accessGroup;
}

%hook GCKBUtils
+ (NSString *)appIdentifier { return DISCORD_BUNDLE_ID; }
%end

%hook GPCDeviceInfo
+ (NSString *)bundleId { return DISCORD_BUNDLE_ID; }
%end

%hook OGLBundle
+ (NSString *)shortAppName { return DISCORD_NAME; }
%end

%hook GVROverlayView
+ (NSString *)appName { return DISCORD_NAME; }
%end

%hook OGLPhenotypeFlagServiceImpl
- (NSString *)bundleId { return DISCORD_BUNDLE_ID; }
%end

%hook APMAEU
+ (BOOL)isFAS { return YES; }
%end

%hook GULAppEnvironmentUtil
+ (BOOL)isFromAppStore { return YES; }
%end

%hook SSOConfiguration
- (id)initWithClientID:(id)clientID supportedAccountServices:(id)supportedAccountServices {
    self = %orig;
    [self setValue:DISCORD_NAME forKey:@"_shortAppName"];
    [self setValue:DISCORD_BUNDLE_ID forKey:@"_applicationIdentifier"];
    return self;
}
%end

BOOL isSelf() {
    NSArray *address = [NSThread callStackReturnAddresses];
    Dl_info info = {0};
    if (dladdr((void *)[address[2] longLongValue], &info) == 0) return NO;
    NSString *path = [NSString stringWithUTF8String:info.dli_fname];
    return [path hasPrefix:NSBundle.mainBundle.bundlePath];
}

%hook NSBundle
- (NSString *)bundleIdentifier {
    return isSelf() ? DISCORD_BUNDLE_ID : %orig;
}

- (NSDictionary *)infoDictionary {
    NSDictionary *dict = %orig;
    if (!isSelf())
        return %orig;
    NSMutableDictionary *info = [dict mutableCopy];
    if (info[@"CFBundleIdentifier"]) info[@"CFBundleIdentifier"] = DISCORD_BUNDLE_ID;
    if (info[@"CFBundleDisplayName"]) info[@"CFBundleDisplayName"] = DISCORD_NAME;
    if (info[@"CFBundleName"]) info[@"CFBundleName"] = DISCORD_NAME;
    return info;
}

- (id)objectForInfoDictionaryKey:(NSString *)key {
    if (!isSelf())
        return %orig;
    if ([key isEqualToString:@"CFBundleIdentifier"])
        return DISCORD_BUNDLE_ID;
    if ([key isEqualToString:@"CFBundleDisplayName"] || [key isEqualToString:@"CFBundleName"])
        return DISCORD_NAME;
    return %orig;
}
%end

%hook SSOKeychainHelper
+ (NSString *)accessGroup {
    return accessGroupID();
}
+ (NSString *)sharedAccessGroup {
    return accessGroupID();
}
%end

%hook SSOKeychainCore
+ (NSString *)accessGroup {
    return accessGroupID();
}

+ (NSString *)sharedAccessGroup {
    return accessGroupID();
}
%end

// Fix App Group Directory by moving it to documents directory
%hook NSFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    if (groupIdentifier != nil) {
        NSArray *paths = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
        NSURL *documentsURL = [paths lastObject];
        return [documentsURL URLByAppendingPathComponent:@"AppGroup"];
    }
    return %orig(groupIdentifier);
}
%end
%end

%ctor {
    BOOL isAppStoreApp = [[NSFileManager defaultManager] fileExistsAtPath:[[NSBundle mainBundle] appStoreReceiptURL].path];
    if (!isAppStoreApp) %init(gSideloading);
}