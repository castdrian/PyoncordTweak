#import "Logger.h"
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

typedef struct __CMSDecoder *CMSDecoderRef;
extern CFTypeRef SecCMSDecodeGetContent(CFDataRef message);
extern OSStatus CMSDecoderCreate(CMSDecoderRef *cmsDecoder);
extern OSStatus CMSDecoderUpdateMessage(CMSDecoderRef cmsDecoder, const void *content,
                                        size_t contentLength);
extern OSStatus CMSDecoderFinalizeMessage(CMSDecoderRef cmsDecoder);
extern OSStatus CMSDecoderCopyContent(CMSDecoderRef cmsDecoder, CFDataRef *content);

@interface LSApplicationWorkspace : NSObject
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
@end

#define DISCORD_BUNDLE_ID @"com.hammerandchisel.discord"
#define DISCORD_NAME @"Discord"

static NSString *getAccessGroupID(void) {
    NSDictionary *query = @{
        (__bridge NSString *)kSecClass : (__bridge NSString *)kSecClassGenericPassword,
        (__bridge NSString *)kSecAttrAccount : @"bundleSeedID",
        (__bridge NSString *)kSecAttrService : @"",
        (__bridge NSString *)kSecReturnAttributes : @YES
    };

    CFDictionaryRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);

    if (status == errSecItemNotFound) {
        status = SecItemAdd((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
    }

    if (status != errSecSuccess)
        return nil;

    NSString *accessGroup =
        [(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kSecAttrAccessGroup];
    if (result)
        CFRelease(result);

    return accessGroup;
}

static BOOL isSelfCall(void) {
    NSArray *address = [NSThread callStackReturnAddresses];
    Dl_info info     = {0};
    if (dladdr((void *)[address[2] longLongValue], &info) == 0)
        return NO;
    NSString *path = [NSString stringWithUTF8String:info.dli_fname];
    return [path hasPrefix:NSBundle.mainBundle.bundlePath];
}

static NSString *getProvisioningBundleID(void) {
    NSString *provisionPath = [NSBundle.mainBundle pathForResource:@"embedded"
                                                            ofType:@"mobileprovision"];
    if (!provisionPath)
        return nil;

    NSData *provisionData = [NSData dataWithContentsOfFile:provisionPath];
    if (!provisionData)
        return nil;

    CMSDecoderRef decoder = NULL;
    CMSDecoderCreate(&decoder);
    CMSDecoderUpdateMessage(decoder, provisionData.bytes, provisionData.length);
    CMSDecoderFinalizeMessage(decoder);

    CFDataRef dataRef = NULL;
    CMSDecoderCopyContent(decoder, &dataRef);
    NSData *data = (__bridge_transfer NSData *)dataRef;

    if (decoder)
        CFRelease(decoder);

    NSError *error = nil;
    id plist       = [NSPropertyListSerialization propertyListWithData:data
                                                         options:0
                                                          format:NULL
                                                           error:&error];
    if (!plist || ![plist isKindOfClass:[NSDictionary class]])
        return nil;

    NSString *appID = plist[@"Entitlements"][@"application-identifier"];
    if (!appID)
        return nil;

    NSArray *components = [appID componentsSeparatedByString:@"."];
    if (components.count > 1) {
        return [[components subarrayWithRange:NSMakeRange(1, components.count - 1)]
            componentsJoinedByString:@"."];
    }

    return nil;
}

%group Sideloading

%hook NSBundle
- (NSString *)bundleIdentifier {
    if (!isSelfCall())
        return %orig;

    static NSString *provisionID = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ provisionID = getProvisioningBundleID(); });

    return provisionID ?: DISCORD_BUNDLE_ID;
}

- (NSDictionary *)infoDictionary {
    if (!isSelfCall())
        return %orig;

    NSMutableDictionary *info    = [%orig mutableCopy];
    info[@"CFBundleIdentifier"]  = DISCORD_BUNDLE_ID;
    info[@"CFBundleDisplayName"] = DISCORD_NAME;
    info[@"CFBundleName"]        = DISCORD_NAME;
    return info;
}

- (id)objectForInfoDictionaryKey:(NSString *)key {
    if (!isSelfCall())
        return %orig;

    if ([key isEqualToString:@"CFBundleIdentifier"])
        return DISCORD_BUNDLE_ID;
    if ([key isEqualToString:@"CFBundleDisplayName"] || [key isEqualToString:@"CFBundleName"])
        return DISCORD_NAME;
    return %orig;
}
%end

%hook NSFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    BunnyLog(@"containerURLForSecurityApplicationGroupIdentifier called! %@",
             groupIdentifier ?: @"nil");

    NSArray *paths  = [self URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *lastPath = [paths lastObject];
    return [lastPath URLByAppendingPathComponent:@"AppGroup"];
}
%end

%hook UIPasteboard
- (NSString *)_accessGroup {
    return getAccessGroupID();
}
%end

%hook UIApplication
- (BOOL)_canChangeAlternateIconName {
    return YES;
}

- (void)setAlternateIconName:(NSString *)iconName
           completionHandler:(void (^)(NSError *))completion {
    if (completion)
        completion(nil);
    %orig;
}
%end

%hook LSApplicationWorkspace
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID {
    if ([bundleID isEqualToString:DISCORD_BUNDLE_ID]) {
        return [self openApplicationWithBundleID:getProvisioningBundleID()];
    }
    return %orig;
}
%end

%hook UIDocumentPickerViewController
- (id)initForOpeningContentTypes:(NSArray *)contentTypes {
    if (isSelfCall()) {
        NSBundle *bundle = [NSBundle bundleWithIdentifier:getProvisioningBundleID()];
        self             = %orig(contentTypes);
        [self setValue:bundle forKey:@"_clientBundle"];
        return self;
    }
    return %orig;
}
%end

%end // End of Sideloading group

    %ctor {
    BOOL isAppStoreApp = [[NSFileManager defaultManager]
        fileExistsAtPath:[[NSBundle mainBundle] appStoreReceiptURL].path];
    if (!isAppStoreApp) {
        %init(Sideloading);
    }
}
