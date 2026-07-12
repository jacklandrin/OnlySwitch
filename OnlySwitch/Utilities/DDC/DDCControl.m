//
//  DDCControl.m
//  OnlySwitch
//

#import "DDCControl.h"
#import <unistd.h>
#import <math.h>
#import <string.h>
@import IOKit;

// DDC/CI over I2C constants (VESA MCCS). Values mirror waydabber/m1ddc.
static const uint32_t  kDDCChipAddress     = 0x37;
static const uint32_t  kDDCInputAddress    = 0x51;
static const uint8_t   kVCPLuminance       = 0x10;   // VCP "Luminance" feature code
static const uint8_t   kVCPPowerMode       = 0xD6;   // VCP "Power Mode" feature code
static const uint16_t  kPowerModeOn        = 0x01;   // DPMS on
static const uint16_t  kPowerModeOff       = 0x04;   // DPMS off (wakes again via DDC)
static const useconds_t kDDCWaitMicros     = 10000;  // settle time between I2C transactions
static const int       kDDCWriteIterations = 2;      // some displays need the write repeated

#pragma mark - Cached display model

@interface DDCDisplay : NSObject
@property (nonatomic, strong) id avService; // IOAVServiceRef held by ARC
@property (nonatomic, assign) int maxValue;
@end

@implementation DDCDisplay
@end

#pragma mark - DDCControl

@implementation DDCControl

static NSMutableArray<DDCDisplay *> *_displays;

#pragma mark Low level I2C

+ (BOOL)sendBytes:(const uint8_t *)bytes
           length:(uint32_t)length
        toService:(IOAVServiceRef)service {
    for (int i = 0; i < kDDCWriteIterations; i++) {
        usleep(kDDCWaitMicros);
        IOReturn result = IOAVServiceWriteI2C(service,
                                              kDDCChipAddress,
                                              kDDCInputAddress,
                                              (void *)bytes,
                                              length);
        if (result != kIOReturnSuccess) {
            return NO;
        }
    }
    return YES;
}

+ (BOOL)writeVCPCode:(uint8_t)code value:(uint16_t)value toService:(IOAVServiceRef)service {
    uint8_t data[6];
    data[0] = 0x84;                  // length / op
    data[1] = 0x03;                  // "Set VCP Feature"
    data[2] = code;
    data[3] = (value >> 8) & 0xFF;   // high byte
    data[4] = value & 0xFF;          // low byte
    data[5] = 0x6E ^ kDDCInputAddress ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[4];
    return [self sendBytes:data length:sizeof(data) toService:service];
}

+ (BOOL)writeLuminance:(uint16_t)value toService:(IOAVServiceRef)service {
    return [self writeVCPCode:kVCPLuminance value:value toService:service];
}

+ (BOOL)readLuminanceFromService:(IOAVServiceRef)service
                         current:(int *)current
                             max:(int *)max {
    uint8_t request[4];
    request[0] = 0x82;               // length / op
    request[1] = 0x01;               // "Get VCP Feature"
    request[2] = kVCPLuminance;
    request[3] = 0x6E ^ request[0] ^ request[1] ^ request[2];
    if (![self sendBytes:request length:sizeof(request) toService:service]) {
        return NO;
    }

    uint8_t reply[12] = {0};
    usleep(kDDCWaitMicros);
    if (IOAVServiceReadI2C(service,
                           kDDCChipAddress,
                           kDDCInputAddress,
                           reply,
                           sizeof(reply)) != kIOReturnSuccess) {
        return NO;
    }

    // "Get VCP Feature Reply": maximum value in bytes [6..7], current value in
    // bytes [8..9], both big-endian.
    int maxValue = (reply[6] << 8) | reply[7];
    int curValue = (reply[8] << 8) | reply[9];
    // A real DDC brightness maximum is small – essentially always 100, never
    // more than a couple hundred. Some displays return garbage on an unreliable
    // read (seen: 0xC800 = 51200). If we cached that, brightness writes would be
    // scaled to absurd 16-bit values and the monitor would flip between bright
    // and dark. Reject implausible maxima so the caller keeps the safe default.
    if (maxValue < 1 || maxValue > 255) {
        return NO; // no/garbage response – treat as unreadable
    }
    if (max) { *max = maxValue; }
    if (current) { *current = curValue; }
    return YES;
}

#pragma mark Discovery

/// Walks the IORegistry and returns an `IOAVService` for every external display.
/// Built-in panels report a "Location" of "Embedded" and are skipped, so this
/// only ever returns DDC/CI capable external monitors.
+ (NSArray<DDCDisplay *> *)discoverExternalDisplays {
    NSMutableArray<DDCDisplay *> *result = [NSMutableArray array];

    io_registry_entry_t root = IORegistryGetRootEntry(kIOMainPortDefault);
    if (root == MACH_PORT_NULL) {
        return result;
    }

    io_iterator_t iterator = MACH_PORT_NULL;
    if (IORegistryEntryCreateIterator(root,
                                      kIOServicePlane,
                                      kIORegistryIterateRecursively,
                                      &iterator) != KERN_SUCCESS) {
        return result;
    }

    io_service_t service = MACH_PORT_NULL;
    while ((service = IOIteratorNext(iterator)) != MACH_PORT_NULL) {
        io_name_t name = {0};
        if (IORegistryEntryGetName(service, name) == KERN_SUCCESS &&
            strcmp(name, "DCPAVServiceProxy") == 0) {

            CFTypeRef location = IORegistryEntrySearchCFProperty(service,
                                                                 kIOServicePlane,
                                                                 CFSTR("Location"),
                                                                 kCFAllocatorDefault,
                                                                 kIORegistryIterateRecursively);
            BOOL isExternal = location != NULL &&
                CFGetTypeID(location) == CFStringGetTypeID() &&
                CFStringCompare((CFStringRef)location, CFSTR("External"), 0) == kCFCompareEqualTo;
            if (location) {
                CFRelease(location);
            }

            if (isExternal) {
                IOAVServiceRef avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service);
                if (avService) {
                    DDCDisplay *display = [DDCDisplay new];
                    display.avService = (__bridge_transfer id)avService;
                    display.maxValue = 100; // MCCS default until a read succeeds
                    [result addObject:display];
                }
            }
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);

    return result;
}

#pragma mark Public API

+ (void)refreshExternalDisplays {
    @synchronized (self) {
        NSMutableArray<DDCDisplay *> *displays = [[self discoverExternalDisplays] mutableCopy];
        for (DDCDisplay *display in displays) {
            int maxValue = 0;
            if ([self readLuminanceFromService:(__bridge IOAVServiceRef)display.avService
                                       current:NULL
                                           max:&maxValue]) {
                display.maxValue = maxValue;
            }
        }
        _displays = displays;
    }
}

+ (NSInteger)externalDisplayCount {
    @synchronized (self) {
        return (NSInteger)_displays.count;
    }
}

+ (void)setExternalBrightnessPercentage:(float)percentage {
    @synchronized (self) {
        if (_displays.count == 0) {
            return;
        }
        float clamped = MAX(0.0f, MIN(1.0f, percentage));
        for (DDCDisplay *display in _displays) {
            uint16_t value = (uint16_t)lroundf(clamped * (float)display.maxValue);
            [self writeLuminance:value toService:(__bridge IOAVServiceRef)display.avService];
        }
    }
}

+ (void)setExternalDisplaysPower:(BOOL)on {
    @synchronized (self) {
        if (_displays.count == 0) {
            return;
        }
        uint16_t value = on ? kPowerModeOn : kPowerModeOff;
        for (DDCDisplay *display in _displays) {
            [self writeVCPCode:kVCPPowerMode value:value toService:(__bridge IOAVServiceRef)display.avService];
        }
    }
}

@end
