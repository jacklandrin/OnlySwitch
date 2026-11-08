@interface KeyboardBrightnessClient : NSObject

- (void)unregisterKeyboardNotificationBlock;
- (BOOL)isAutoBrightnessEnabledForKeyboard:(unsigned long long)arg1;
- (BOOL)isIdleDimmingSuspendedOnKeyboard:(unsigned long long)arg1;
- (BOOL)suspendIdleDimming:(BOOL)arg1 forKeyboard:(unsigned long long)arg2;
- (BOOL)setIdleDimTime:(double)arg1 forKeyboard:(unsigned long long)arg2;
- (double)idleDimTimeForKeyboard:(unsigned long long)arg1;
- (BOOL)isKeyboardBuiltIn:(unsigned long long)arg1;
- (BOOL)isAmbientFeatureAvailableOnKeyboard:(unsigned long long)arg1;
- (BOOL)enableAutoBrightness:(BOOL)arg1 forKeyboard:(unsigned long long)arg2;
- (BOOL)setBrightness:(float)arg1 fadeSpeed:(int)arg2 commit:(_Bool)arg3 forKeyboard:(unsigned long long)arg4;
- (BOOL)setBrightness:(float)arg1 forKeyboard:(unsigned long long)arg2;
- (float)brightnessForKeyboard:(unsigned long long)arg1;
- (BOOL)isBacklightDimmedOnKeyboard:(unsigned long long)arg1;
- (BOOL)isBacklightSaturatedOnKeyboard:(unsigned long long)arg1;
- (BOOL)isBacklightSuppressedOnKeyboard:(unsigned long long)arg1;
- (id)copyKeyboardBacklightIDs;
- (id)init;

// Auto-dim speed is 500ms
// manual control fade speed is 350ms

@end
