// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (Ice) © 2023–2025 Jordan Baird
// Copyright (Thaw) © 2026 Toni Förster
// Copyright (C) 2026 Vorssaint
//
// Adapted from Thaw/MenuBar/HiddenSectionPatch/ThawAssessmentModeHiding
// and Ice/Bridging/IceMenuBarVisibility.m.

#import "include/MenuBarVisibilityBridge.h"
#import <dlfcn.h>

@interface MBAssessmentModeConfiguration : NSObject
- (instancetype)initWithAllowedSystemItems:(NSArray<NSNumber *> *)systemItems
                  allowedBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers;
@end

@interface MBAssessmentModeAssertion : NSObject
- (void)activateWithConfiguration:(id)configuration
                completionHandler:(void (^)(NSError *_Nullable error))completionHandler;
- (void)invalidate;
@end

static const char * const kMenuBarClientCorePath =
    "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";
static NSString * const VorssaintMenuBarVisibilityErrorDomain = @"VorssaintMenuBarVisibilityError";

typedef NS_ENUM(NSInteger, VorssaintMenuBarVisibilityErrorCode) {
    VorssaintMenuBarVisibilityErrorUnavailable = 1,
    VorssaintMenuBarVisibilityErrorActivationFailed = 2,
};

static BOOL VorssaintMenuBarVisibilitySupportsMacOS27(void) {
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27;
}

static BOOL VorssaintEnsureMenuBarClientCoreLoaded(void) {
    static dispatch_once_t onceToken;
    static BOOL loaded;
    dispatch_once(&onceToken, ^{
        if (!VorssaintMenuBarVisibilitySupportsMacOS27()) {
            return;
        }
        loaded = dlopen(kMenuBarClientCorePath, RTLD_NOW) != NULL;
        if (!loaded) {
            NSLog(@"[MenuBarVisibilityBridge] failed to load MenuBarClientCore: %s", dlerror());
        }
    });
    return loaded;
}

static BOOL VorssaintAssessmentModeClassesAreUsable(Class _Nullable *configurationClass,
                                                    Class _Nullable *assertionClass) {
    if (!VorssaintEnsureMenuBarClientCoreLoaded()) {
        return NO;
    }

    Class configuration = NSClassFromString(@"MBAssessmentModeConfiguration");
    Class assertion = NSClassFromString(@"MBAssessmentModeAssertion");
    SEL configurationInitializer = @selector(initWithAllowedSystemItems:allowedBundleIdentifiers:);
    SEL activation = @selector(activateWithConfiguration:completionHandler:);
    SEL invalidation = @selector(invalidate);

    if (!configuration || !assertion ||
        ![configuration respondsToSelector:@selector(alloc)] ||
        ![assertion respondsToSelector:@selector(alloc)] ||
        ![configuration instancesRespondToSelector:configurationInitializer] ||
        ![assertion instancesRespondToSelector:@selector(init)] ||
        ![assertion instancesRespondToSelector:activation] ||
        ![assertion instancesRespondToSelector:invalidation]) {
        return NO;
    }

    if (configurationClass) {
        *configurationClass = configuration;
    }
    if (assertionClass) {
        *assertionClass = assertion;
    }
    return YES;
}

static NSError *VorssaintMenuBarVisibilityError(VorssaintMenuBarVisibilityErrorCode code,
                                                NSString *description) {
    return [NSError errorWithDomain:VorssaintMenuBarVisibilityErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: description }];
}

static void VorssaintMenuBarVisibilityComplete(void (^_Nullable completion)(NSError *_Nullable),
                                               NSError *_Nullable error) {
    if (!completion) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(error);
    });
}

BOOL VorssaintMenuBarVisibilityAvailable(void) {
    return VorssaintAssessmentModeClassesAreUsable(NULL, NULL);
}

void *VorssaintMenuBarVisibilityActivate(NSArray<NSString *> *allowedBundleIdentifiers,
                                         NSArray<NSNumber *> *allowedSystemItems,
                                         void (^completion)(NSError *_Nullable)) {
    Class configurationClass;
    Class assertionClass;
    if (!VorssaintAssessmentModeClassesAreUsable(&configurationClass, &assertionClass)) {
        VorssaintMenuBarVisibilityComplete(completion,
            VorssaintMenuBarVisibilityError(VorssaintMenuBarVisibilityErrorUnavailable,
                                            @"Menu bar visibility is unavailable on this macOS version."));
        return NULL;
    }

    @try {
        MBAssessmentModeConfiguration *configuration =
            [[configurationClass alloc] initWithAllowedSystemItems:allowedSystemItems ?: @[]
                                          allowedBundleIdentifiers:allowedBundleIdentifiers ?: @[]];
        if (!configuration) {
            VorssaintMenuBarVisibilityComplete(completion,
                VorssaintMenuBarVisibilityError(VorssaintMenuBarVisibilityErrorActivationFailed,
                                                @"Could not create the menu bar visibility configuration."));
            return NULL;
        }

        MBAssessmentModeAssertion *assertion = [[assertionClass alloc] init];
        if (!assertion) {
            VorssaintMenuBarVisibilityComplete(completion,
                VorssaintMenuBarVisibilityError(VorssaintMenuBarVisibilityErrorActivationFailed,
                                                @"Could not create the menu bar visibility assertion."));
            return NULL;
        }

        [assertion activateWithConfiguration:configuration
                           completionHandler:^(NSError *_Nullable error) {
            VorssaintMenuBarVisibilityComplete(completion, error);
        }];
        return (void *)CFBridgingRetain(assertion);
    } @catch (NSException *exception) {
        NSLog(@"[MenuBarVisibilityBridge] activation threw: %@", exception);
        VorssaintMenuBarVisibilityComplete(completion,
            VorssaintMenuBarVisibilityError(VorssaintMenuBarVisibilityErrorActivationFailed,
                                            exception.reason ?: @"Menu bar visibility activation failed."));
        return NULL;
    }
}

void VorssaintMenuBarVisibilityInvalidate(void *handle) {
    if (!handle) {
        return;
    }

    MBAssessmentModeAssertion *assertion = (MBAssessmentModeAssertion *)CFBridgingRelease(handle);
    @try {
        if ([assertion respondsToSelector:@selector(invalidate)]) {
            [assertion invalidate];
        }
    } @catch (NSException *exception) {
        NSLog(@"[MenuBarVisibilityBridge] invalidation threw: %@", exception);
    }
}
