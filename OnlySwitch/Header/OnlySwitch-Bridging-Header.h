//
//  OnlySwitch-Bridging-Header.h
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/5.
//

#import "CBBlueLightClient.h"

//for turn on/off bluetooth
void IOBluetoothPreferenceSetControllerPowerState(int state);
int IOBluetoothPreferenceGetControllerPowerState();

