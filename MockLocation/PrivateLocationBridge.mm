#import "PrivateLocationBridge.h"
#import <objc/message.h>
#import <dlfcn.h>

static NSString *const MockLocationBridgeErrorDomain = @"com.personal.mocklocation.bridge";

typedef const void *MockSecTaskRef;
typedef MockSecTaskRef (*MockSecTaskCreateFunction)(CFAllocatorRef allocator);
typedef CFTypeRef (*MockSecTaskCopyFunction)(MockSecTaskRef task, CFStringRef entitlement, CFErrorRef *error);

static BOOL MockHasEntitlement(CFStringRef entitlement) {
    // These private declarations are omitted from the iOS SDK; resolve the exported symbols at runtime.
    MockSecTaskCreateFunction createTask = (MockSecTaskCreateFunction)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    MockSecTaskCopyFunction copyTaskValue = (MockSecTaskCopyFunction)dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    if (createTask == NULL || copyTaskValue == NULL) {
        // The build script verifies the signed entitlement before producing an IPA.
        return YES;
    }

    MockSecTaskRef task = createTask(kCFAllocatorDefault);
    if (task == NULL) {
        return NO;
    }

    CFTypeRef value = copyTaskValue(task, entitlement, NULL);
    BOOL hasEntitlement = value != NULL &&
        CFGetTypeID(value) == CFBooleanGetTypeID() &&
        CFBooleanGetValue((CFBooleanRef)value);

    if (value != NULL) {
        CFRelease(value);
    }
    CFRelease((CFTypeRef)task);
    return hasEntitlement;
}

@implementation PrivateLocationBridge

+ (id)simulationManager {
    Class managerClass = NSClassFromString(@"CLSimulationManager");
    return managerClass != Nil ? [[managerClass alloc] init] : nil;
}

+ (NSArray<NSString *> *)requiredSelectors {
    return @[
        @"clearSimulatedLocations",
        @"appendSimulatedLocation:",
        @"flush",
        @"startLocationSimulation",
        @"stopLocationSimulation"
    ];
}

+ (BOOL)hasSimulationEntitlement {
    return MockHasEntitlement(CFSTR("com.apple.locationd.simulation"));
}

+ (BOOL)hasPlatformApplicationEntitlement {
    return MockHasEntitlement(CFSTR("platform-application"));
}

+ (BOOL)hasNoSandboxEntitlement {
    return MockHasEntitlement(CFSTR("com.apple.private.security.no-sandbox"));
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
        return @"当前 iOS 版本不支持系统定位模拟。";
    }
    if (![self hasSimulationEntitlement]) {
        return @"未检测到定位模拟权限。请使用 TrollStore 重新安装此 IPA。";
    }
    if (![self hasPlatformApplicationEntitlement]) {
        return @"未检测到平台应用权限。请使用 TrollStore 重新安装此 IPA。";
    }
    if (![self hasNoSandboxEntitlement]) {
        return @"缺少 iOS 15 所需的无沙盒权限。请使用 TrollStore 重新安装此 IPA。";
    }
    if (![self isAvailable]) {
        return @"系统定位模拟接口不可用。";
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
    NSString *message = [self availabilityMessage] ?: @"定位模拟功能不可用。";
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
                                     userInfo:@{ NSLocalizedDescriptionKey: @"没有可模拟的位置。" }];
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
        [self invokeVoidSelector:NSSelectorFromString(@"flush") on:manager];
        [self invokeVoidSelector:NSSelectorFromString(@"startLocationSimulation") on:manager];
        return YES;
    } @catch (NSException *exception) {
        if (error != nil) {
            *error = [NSError errorWithDomain:MockLocationBridgeErrorDomain
                                         code:3
                                     userInfo:@{ NSLocalizedDescriptionKey: exception.reason ?: @"启动定位模拟失败。" }];
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
                                     userInfo:@{ NSLocalizedDescriptionKey: exception.reason ?: @"停止定位模拟失败。" }];
        }
        return NO;
    }
}

@end
