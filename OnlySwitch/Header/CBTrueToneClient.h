//
//  CBTrueToneClient.h
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/27.
//

#ifndef CBTrueToneClient_h
#define CBTrueToneClient_h

@interface CBTrueToneClient : NSObject
- (BOOL)available;
- (BOOL)supported;
- (BOOL)enabled;
- (BOOL)setEnabled:(BOOL)arg1;
@end

#endif /* CBTrueToneClient_h */
