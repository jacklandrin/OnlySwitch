//
//  MenuBarClientCoreBridge.h
//  OnlySwitch
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MenuBarClientCoreBridge : NSObject

@property (nonatomic, readonly, getter=isAvailable) BOOL available;

- (void)activateWithAllowedSystemItems:(NSArray<NSNumber *> *)systemItems
              allowedBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                            completion:(void (^)(NSError * _Nullable error))completion;
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
