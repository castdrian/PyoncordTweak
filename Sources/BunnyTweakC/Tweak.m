#import <Orion/Orion.h>

const char * const _Nonnull get_install_prefix(void) {
    return THEOS_PACKAGE_INSTALL_PREFIX;
}

__attribute__((constructor)) static void init() {
    // Initialize Orion - do not remove this line.
    orion_init();
    // Custom initialization code goes here.
}

+ (void)presentAlert:(NSString * _Nonnull)title message:(NSString * _Nonnull)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                    message:message
                                    preferredStyle:UIAlertControllerStyleAlert];
									
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
    	style:UIAlertActionStyleDefault
    	handler:^(UIAlertAction *action) {
        exit(0);
    }];
    [alert addAction:okAction];
    
    UIViewController *rootViewController = [UIApplication sharedApplication].keyWindow.rootViewController;
    [rootViewController presentViewController:alert animated:YES completion:nil];
}