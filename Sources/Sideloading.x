#import "Logger.h"
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

typedef struct __CMSDecoder *CMSDecoderRef;
extern OSStatus CMSDecoderCreate(CMSDecoderRef *cmsDecoder);
extern OSStatus CMSDecoderUpdateMessage(CMSDecoderRef cmsDecoder, const void *content,
                                        size_t contentLength);
extern OSStatus CMSDecoderFinalizeMessage(CMSDecoderRef cmsDecoder);
extern OSStatus CMSDecoderCopyContent(CMSDecoderRef cmsDecoder, CFDataRef *content);

#define DISCORD_BUNDLE_ID @"com.hammerandchisel.discord"
#define DISCORD_NAME @"Discord"

static AVAudioPlayer *silentAudioPlayer = nil;

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

static void setupSilentAudioPlayer(void) {
    NSString *audioPath = [NSBundle.mainBundle pathForResource:@"silence" ofType:@"wav"];
    if (!audioPath) {
        NSString *documentsPath =
            NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        audioPath = [documentsPath stringByAppendingPathComponent:@"silence.wav"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:audioPath]) {
            char wavHeader[] = {0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56,
                                0x45, 0x66, 0x6D, 0x74, 0x20, 0x10, 0x00, 0x00, 0x00, 0x01, 0x00,
                                0x01, 0x00, 0x44, 0xAC, 0x00, 0x00, 0x88, 0x58, 0x01, 0x00, 0x02,
                                0x00, 0x10, 0x00, 0x64, 0x61, 0x74, 0x61, 0x00, 0x00, 0x00, 0x00};
            NSData *wavData  = [NSData dataWithBytes:wavHeader length:sizeof(wavHeader)];
            [wavData writeToFile:audioPath atomically:YES];
        }
    }

    NSError *error = nil;
    silentAudioPlayer =
        [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:audioPath]
                                               error:&error];
    silentAudioPlayer.numberOfLoops = -1;
    silentAudioPlayer.volume        = 0.0;
    [silentAudioPlayer prepareToPlay];
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
    return isSelfCall() ? DISCORD_BUNDLE_ID : %orig;
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

%end

%ctor {
    BOOL isAppStoreApp = [[NSFileManager defaultManager]
        fileExistsAtPath:[[NSBundle mainBundle] appStoreReceiptURL].path];
    if (!isAppStoreApp) {
        %init(Sideloading);

        NSString *provisioningBundleID = getProvisioningBundleID();
        NSString *currentBundleID      = [[NSBundle mainBundle] bundleIdentifier];

        if (provisioningBundleID && [currentBundleID isEqualToString:provisioningBundleID]) {
            setupSilentAudioPlayer();

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                               AVAudioSession *session = [AVAudioSession sharedInstance];
                               NSError *error          = nil;
                               [session setCategory:AVAudioSessionCategoryPlayback error:&error];
                               [session setActive:YES error:&error];

                               [silentAudioPlayer play];
                           });
        }
    }
}
