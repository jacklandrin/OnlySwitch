#import "KeyboardManager.h"

@interface KeyboardManager()
+(void)loadPrivateFrameworks;
@end

@implementation KeyboardManager

+ (id)sharedInstance {
    static KeyboardManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

+(void)loadPrivateFrameworks {
    [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreBrightness.framework"] load];
    [KeyboardManager.sharedInstance setBrightnessClient:[[NSClassFromString(@"KeyboardBrightnessClient") alloc] init]];
}

+(void)configure {
    [self loadPrivateFrameworks];
}

+(KeyboardBrightnessClient *)brightnessClient {
    return [KeyboardManager.sharedInstance brightnessClient];
}

- (id)init {
    if (self = [super init]) {
        self.paused = false;
    }
    return self;
}

@end
