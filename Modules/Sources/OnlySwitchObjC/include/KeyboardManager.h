#import <Foundation/Foundation.h>
#import "KeyboardBrightnessClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface KeyboardManager : NSObject
@property(nonatomic,strong) KeyboardBrightnessClient * brightnessClient;
@property(atomic,readwrite) BOOL paused;
+(id)sharedInstance;
+(void)configure;
+(KeyboardBrightnessClient *)brightnessClient;
@end

NS_ASSUME_NONNULL_END
