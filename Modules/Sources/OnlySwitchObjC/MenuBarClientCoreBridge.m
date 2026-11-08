//
//  MenuBarClientCoreBridge.m
//  OnlySwitch
//

#import "MenuBarClientCoreBridge.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <Security/Security.h>

static NSString * const MenuBarClientCoreBridgeErrorDomain = @"jacklandrin.OnlySwitch.MenuBarClientCoreBridge";

typedef id (*MBInitConfigurationFunction)(id, SEL, NSArray<NSNumber *> *, NSArray<NSString *> *);
typedef void (*MBActivateFunction)(id, SEL, id, void (^)(NSError * _Nullable));
typedef void (*MBInvalidateFunction)(id, SEL);

@interface MenuBarClientCoreBridge ()
@property (nonatomic, strong, nullable) id activeAssertion;
@end

@implementation MenuBarClientCoreBridge

+ (BOOL)hasEligibleCodeSignature {
    static BOOL eligible = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SecCodeRef code = NULL;
        if (SecCodeCopySelf(kSecCSDefaultFlags, &code) != errSecSuccess || code == NULL) {
            return;
        }

        // Basic validation is a static-code option. It validates the signing
        // envelope without evaluating the local developer certificate's trust
        // chain; team identity and ad-hoc rejection are checked below.
        SecStaticCodeRef staticCode = NULL;
        OSStatus staticCodeStatus = SecCodeCopyStaticCode(code, kSecCSDefaultFlags, &staticCode);
        OSStatus validityStatus = staticCodeStatus == errSecSuccess && staticCode != NULL
            ? SecStaticCodeCheckValidity(staticCode, kSecCSBasicValidateOnly, NULL)
            : staticCodeStatus;
        if (staticCode != NULL) {
            CFRelease(staticCode);
        }
        CFDictionaryRef signingInformation = NULL;
        OSStatus informationStatus = SecCodeCopySigningInformation(
            code,
            kSecCSSigningInformation,
            &signingInformation
        );
        CFRelease(code);
        if (validityStatus != errSecSuccess
            || informationStatus != errSecSuccess
            || signingInformation == NULL) {
            if (signingInformation != NULL) {
                CFRelease(signingInformation);
            }
            return;
        }

        NSDictionary *information = CFBridgingRelease(signingInformation);
        NSString *teamIdentifier = information[(__bridge NSString *)kSecCodeInfoTeamIdentifier];
        NSNumber *signatureFlags = information[(__bridge NSString *)kSecCodeInfoFlags];
        BOOL isAdHoc = (signatureFlags.unsignedIntValue & kSecCodeSignatureAdhoc) != 0;
        eligible = teamIdentifier.length > 0 && !isAdHoc;
    });
    return eligible;
}

+ (BOOL)loadFramework {
    static BOOL loaded = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen(
            "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore",
            RTLD_LAZY | RTLD_LOCAL
        );
        loaded = handle != NULL;
    });
    return loaded;
}

+ (Class)configurationClass {
    return [self loadFramework] ? NSClassFromString(@"MBAssessmentModeConfiguration") : Nil;
}

+ (Class)assertionClass {
    return [self loadFramework] ? NSClassFromString(@"MBAssessmentModeAssertion") : Nil;
}

- (BOOL)isAvailable {
    if (![MenuBarClientCoreBridge hasEligibleCodeSignature]) {
        return NO;
    }

    Class configurationClass = [MenuBarClientCoreBridge configurationClass];
    Class assertionClass = [MenuBarClientCoreBridge assertionClass];
    if (configurationClass == Nil || assertionClass == Nil) {
        return NO;
    }

    SEL configurationSelector = NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:");
    SEL activationSelector = NSSelectorFromString(@"activateWithConfiguration:completionHandler:");
    SEL invalidationSelector = NSSelectorFromString(@"invalidate");
    return class_getInstanceMethod(configurationClass, configurationSelector) != NULL
        && class_getInstanceMethod(assertionClass, activationSelector) != NULL
        && class_getInstanceMethod(assertionClass, invalidationSelector) != NULL;
}

- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description {
    return [NSError errorWithDomain:MenuBarClientCoreBridgeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (NSError *)errorWithException:(NSException *)exception {
    NSString *description = exception.reason.length > 0
        ? exception.reason
        : @"The native menu-bar API raised an exception.";
    return [self errorWithCode:4 description:description];
}

- (void)invalidateAssertionSafely:(id)assertion {
    if (assertion == nil) {
        return;
    }

    @try {
        SEL invalidationSelector = NSSelectorFromString(@"invalidate");
        if ([assertion respondsToSelector:invalidationSelector]) {
            MBInvalidateFunction invalidate = (MBInvalidateFunction)objc_msgSend;
            invalidate(assertion, invalidationSelector);
        }
    } @catch (__unused NSException *exception) {
        // A changed private API must not crash OnlySwitch while unwinding an
        // assertion. There is no supported recovery path for this assertion.
    }
}

- (void)activateWithAllowedSystemItems:(NSArray<NSNumber *> *)systemItems
              allowedBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                            completion:(void (^)(NSError * _Nullable))completion {
    NSParameterAssert(completion != nil);
    if (![self isAvailable]) {
        completion([self errorWithCode:1 description:@"The native menu-bar API is unavailable."]);
        return;
    }

    [self invalidate];

    __block BOOL completionDelivered = NO;
    __block id assertion = nil;
    void (^finish)(NSError * _Nullable) = ^(NSError * _Nullable error) {
        BOOL shouldInvalidate = NO;
        @synchronized (self) {
            if (completionDelivered) {
                return;
            }
            completionDelivered = YES;
            self.activeAssertion = error == nil ? assertion : nil;
            shouldInvalidate = error != nil;
        }
        if (shouldInvalidate) {
            [self invalidateAssertionSafely:assertion];
        }
        completion(error);
    };

    @try {
        Class configurationClass = [MenuBarClientCoreBridge configurationClass];
        Class assertionClass = [MenuBarClientCoreBridge assertionClass];
        SEL configurationSelector = NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:");
        SEL activationSelector = NSSelectorFromString(@"activateWithConfiguration:completionHandler:");

        id allocatedConfiguration = [configurationClass alloc];
        MBInitConfigurationFunction initializeConfiguration = (MBInitConfigurationFunction)objc_msgSend;
        id configuration = initializeConfiguration(
            allocatedConfiguration,
            configurationSelector,
            systemItems,
            bundleIdentifiers
        );
        if (configuration == nil) {
            finish([self errorWithCode:2 description:@"The native menu-bar configuration could not be created."]);
            return;
        }

        assertion = [[assertionClass alloc] init];
        if (assertion == nil
            || ![assertion respondsToSelector:activationSelector]
            || ![assertion respondsToSelector:NSSelectorFromString(@"invalidate")]) {
            finish([self errorWithCode:3 description:@"The native menu-bar assertion could not be created."]);
            return;
        }

        MBActivateFunction activate = (MBActivateFunction)objc_msgSend;
        activate(assertion, activationSelector, configuration, ^(NSError * _Nullable error) {
            finish(error);
        });
    } @catch (NSException *exception) {
        finish([self errorWithException:exception]);
    }
}

- (void)invalidate {
    id assertion = nil;
    @synchronized (self) {
        assertion = self.activeAssertion;
        self.activeAssertion = nil;
    }
    [self invalidateAssertionSafely:assertion];
}

- (void)dealloc {
    [self invalidate];
}

@end
