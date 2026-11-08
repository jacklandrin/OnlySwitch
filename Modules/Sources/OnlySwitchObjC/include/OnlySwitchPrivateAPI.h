#pragma once
#import <Foundation/Foundation.h>
#import <IOKit/i2c/IOI2CInterface.h>
#import <CoreGraphics/CoreGraphics.h>

//for turn on/off bluetooth
void IOBluetoothPreferenceSetControllerPowerState(int state);
int IOBluetoothPreferenceGetControllerPowerState(void);

extern void DisplayServicesBrightnessChanged(CGDirectDisplayID display, double brightness);
extern int DisplayServicesGetBrightness(CGDirectDisplayID display, float *brightness);
extern int DisplayServicesSetBrightness(CGDirectDisplayID display, float brightness);
extern int DisplayServicesGetLinearBrightness(CGDirectDisplayID display, float *brightness);
extern int DisplayServicesSetLinearBrightness(CGDirectDisplayID display, float brightness);

extern void CGSServiceForDisplayNumber(CGDirectDisplayID display, io_service_t* service);
