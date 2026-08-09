#import "PrivateLocationBridge.h"
#import <objc/message.h>
#import <Security/Security.h>

static NSString *const MockLocationBridgeErrorDomain = @"com.personal.mocklocation.bridge";

@implementation PrivateLocationBridge

+ (id)simulationManager {
    static id manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class managerClass = NSClassFromString(@"CLSimulationManager");
        if (managerClass != Nil) {
            manager = [[managerClass alloc] init];
        }
    });
    return manager;
}

+ (NSArray<NSString *> *)requiredSelectors {
    return @[
        @"clearSimulatedLocations",
        @"appendSimulatedLocation:",
        @"startLocationSimulation",
        @"stopLocationSimulation"
    ];
}

+ (BOOL)hasSimulationEntitlement {
    SecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
    if (task == NULL) {
        return NO;
    }

    CFTypeRef value = SecTaskCopyValueForEntitlement(
        task,
        CFSTR("com.apple.locationd.simulation"),
        NULL
    );
    BOOL hasEntitlement = value != NULL &&
        CFGetTypeID(value) == CFBooleanGetTypeID() &&
        CFBooleanGetValue((CFBooleanRef)value);

    if (value != NULL) {
        CFRelease(value);
    }
    CFRelease(task);
    return hasEntitlement;
}

+ (BOOL)isAvailable {
    id manager = [self simulationManager];
    if (manager == nil) {
        return NO;
    }

    for (NSString *name in [self requiredSelectors]) {
        if (![manager respondsToSelector:NSSelectorFromString(name)]) {
            return NO;
        }
    }
    return YES;
}

+ (NSString *)availabilityMessage {
    if (NSClassFromString(@"CLSimulationManager") == Nil) {
        return @"The system location simulation runtime is unavailable on this OS version.";
    }
    if (![self hasSimulationEntitlement]) {
        return @"This installation is missing the com.apple.locationd.simulation entitlement. Reinstall the signed IPA with TrollStore, then restart the device once.";
    }
    if (![self isAvailable]) {
        return @"The installed runtime does not expose the required location simulation selectors.";
    }
    return nil;
}

+ (void)invokeVoidSelector:(SEL)selector on:(id)target {
    ((void (*)(id, SEL))objc_msgSend)(target, selector);
}

+ (void)appendLocation:(CLLocation *)location to:(id)target {
    SEL selector = NSSelectorFromString(@"appendSimulatedLocation:");
    ((void (*)(id, SEL, CLLocation *))objc_msgSend)(target, selector, location);
}

+ (NSError *)unavailableError {
    NSString *message = [self availabilityMessage] ?: @"Location simulation is unavailable.";
    return [NSError errorWithDomain:MockLocationBridgeErrorDomain
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

+ (BOOL)startWithLocations:(NSArray<CLLocation *> *)locations
                     error:(NSError * _Nullable * _Nullable)error {
    if (locations.count == 0) {
        if (error != nil) {
            *error = [NSError errorWithDomain:MockLocationBridgeErrorDomain
                                         code:2
                                     userInfo:@{ NSLocalizedDescriptionKey: @"A location is required." }];
        }
        return NO;
    }
    if ([self availabilityMessage] != nil) {
        if (error != nil) {
            *error = [self unavailableError];
        }
        return NO;
    }

    id manager = [self simulationManager];
    @try {
        [self invokeVoidSelector:NSSelectorFromString(@"stopLocationSimulation") on:manager];
        [self invokeVoidSelector:NSSelectorFromString(@"clearSimulatedLocations") on:manager];
        for (CLLocation *location in locations) {
            [self appendLocation:location to:manager];
        }
        [self invokeVoidSelector:NSSelectorFromString(@"startLocationSimulation") on:manager];
        return YES;
    } @catch (NSException *exception) {
        if (error != nil) {
            *error = [NSError errorWithDomain:MockLocationBridgeErrorDomain
                                         code:3
                                     userInfo:@{ NSLocalizedDescriptionKey: exception.reason ?: @"Location simulation failed." }];
        }
        return NO;
    }
}

+ (BOOL)stopWithError:(NSError * _Nullable * _Nullable)error {
    if ([self availabilityMessage] != nil) {
        if (error != nil) {
            *error = [self unavailableError];
        }
        return NO;
    }

    id manager = [self simulationManager];
    @try {
        [self invokeVoidSelector:NSSelectorFromString(@"stopLocationSimulation") on:manager];
        [self invokeVoidSelector:NSSelectorFromString(@"clearSimulatedLocations") on:manager];
        return YES;
    } @catch (NSException *exception) {
        if (error != nil) {
            *error = [NSError errorWithDomain:MockLocationBridgeErrorDomain
                                         code:4
                                     userInfo:@{ NSLocalizedDescriptionKey: exception.reason ?: @"Unable to stop location simulation." }];
        }
        return NO;
    }
}

@end
