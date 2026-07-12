//
//  DDCControl.h
//  OnlySwitch
//
//  Talks DDC/CI to external displays so their brightness can follow the
//  built-in screen. Uses the private `IOAVService` API on Apple Silicon –
//  the same approach used by MonitorControl and waydabber/m1ddc.
//

#ifndef DDCControl_h
#define DDCControl_h

#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>

/// `IOAVService` is a private CoreFoundation type. Its symbols are exported by
/// IOKit, so we only need to forward declare them here.
typedef CFTypeRef IOAVServiceRef;

extern IOAVServiceRef IOAVServiceCreate(CFAllocatorRef allocator);
extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t offset, void *outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t dataAddress, void *inputBuffer, uint32_t inputBufferSize);

/// Thin wrapper around DDC/CI brightness control for every connected external
/// monitor. All methods touch the I2C bus and are therefore slow (tens of
/// milliseconds per display) – call them from a background queue.
@interface DDCControl : NSObject

/// Rediscovers the connected external (DDC/CI capable) displays and caches each
/// one's maximum brightness value. Call once before adjusting brightness and
/// again whenever the screen arrangement changes.
+ (void)refreshExternalDisplays;

/// Number of external displays found by the last `refreshExternalDisplays` call.
+ (NSInteger)externalDisplayCount;

/// Sets every cached external display to `percentage` (0.0 – 1.0) of its own
/// maximum brightness.
+ (void)setExternalBrightnessPercentage:(float)percentage;

/// Powers every cached external display on (`YES`) or into DPMS off (`NO`) via
/// the VCP power-mode feature, so they can go fully dark with the built-in panel.
+ (void)setExternalDisplaysPower:(BOOL)on;

@end

#endif /* DDCControl_h */
