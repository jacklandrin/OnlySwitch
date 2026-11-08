#import <Foundation/Foundation.h>

@interface BrightnessControl : NSObject

+ (void)setBrightness:(float)brightness;
+ (float)getBrightness;
+ (bool)isAutoBrightnessEnabled;
+ (bool)isIdleDimmingSuspended;
+ (void)setSuspendIdleDimming:(bool)value;
+ (void)setIdleDimTime:(double)value;
+ (double)idleDimTimeForKeyboard;
+ (void)enableAutoBrightness:(bool)value;
+ (void)flashKeyboardLights:(int)times
               withInterval:(double)interval
               andFadeSpeed:(double)fadeSpeed;

@end
