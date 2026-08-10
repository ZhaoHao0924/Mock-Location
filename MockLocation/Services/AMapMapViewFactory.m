#import "AMapMapViewFactory.h"
#import <MAMapKit/MAMapView.h>
#import <MAMapKit/MAMapView+Resource.h>
#import <MAMapKit/MAMapVersion.h>
#import <Metal/Metal.h>

/// Must match `AMapSDKConfiguration.metalEnabledDefaultsKey` on the Swift side.
static NSString *const AMapMetalEnabledDefaultsKey = @"amap-metal-enabled";

static BOOL AMapMetalPreferenceEnabled(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:AMapMetalEnabledDefaultsKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:AMapMetalEnabledDefaultsKey];
}

static NSString * _Nullable AMapResourceBundlePath(void) {
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"AMap" ofType:@"bundle"];
    if (bundlePath.length == 0) {
        NSBundle *mapKitBundle = [NSBundle bundleForClass:[MAMapView class]];
        NSString *candidate = [mapKitBundle.resourcePath stringByAppendingPathComponent:@"AMap.bundle"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
            bundlePath = candidate;
        }
    }
    return bundlePath;
}

@implementation AMapMapViewFactory

+ (NSString * _Nullable)resourceBundleVersion {
    NSString *bundlePath = AMapResourceBundlePath();
    if (bundlePath.length == 0) {
        return nil;
    }

    NSString *versionPath = [bundlePath stringByAppendingPathComponent:@"bundleVersion.txt"];
    NSString *version = [NSString stringWithContentsOfFile:versionPath
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
    return [version stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSInteger)resourceBundleStatus {
    static dispatch_once_t onceToken;
    static NSInteger status = 2;
    dispatch_once(&onceToken, ^{
        NSString *bundlePath = AMapResourceBundlePath();
        if (bundlePath.length == 0) {
            return;
        }

        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *resourceIndexPath = [bundlePath stringByAppendingPathComponent:@"res.ck"];
        NSString *resourceArchivePath = [bundlePath stringByAppendingPathComponent:@"res.zip"];
        NSString *threeDBundlePath = [bundlePath stringByAppendingPathComponent:@"AMap3D.bundle"];
        if (![fileManager fileExistsAtPath:resourceIndexPath] ||
            ![fileManager fileExistsAtPath:resourceArchivePath] ||
            ![fileManager fileExistsAtPath:threeDBundlePath]) {
            return;
        }

        NSString *bundleVersion = [self resourceBundleVersion];
        NSString *sdkVersion = [[MAMapKitVersion componentsSeparatedByString:@"+"] firstObject];
        if (bundleVersion.length == 0 || ![bundleVersion isEqualToString:sdkVersion]) {
            status = 1;
            return;
        }
        // Only override the SDK's own lookup when AMap.bundle is absent from the
        // main bundle, which is where the SDK already searches by default under
        // a standard CocoaPods integration.
        //
        // The return value of setBundlePath: is deliberately ignored. Its
        // success encoding is not documented in the SDK headers, so the previous
        // `status = [MAMapView setBundlePath:...]` gated map creation on a guess
        // that 0 means success. If 0 actually means failure there, the guard in
        // LocationAMapSDKView was passing precisely when the resource path had
        // not been applied.
        if ([[NSBundle mainBundle] pathForResource:@"AMap" ofType:@"bundle"].length == 0) {
            [MAMapView setBundlePath:bundlePath];
        }
        status = 0;
    });
    return status;
}

+ (BOOL)isMetalAvailable {
    return MTLCreateSystemDefaultDevice() != nil;
}

+ (BOOL)isMetalPreferred {
    return AMapMetalPreferenceEnabled();
}

+ (BOOL)isMetalEffective {
    return AMapMetalPreferenceEnabled() && [self isMetalAvailable];
}

+ (NSInteger)prepareSDK {
    NSInteger status = [self resourceBundleStatus];
    // Never hand Metal to the SDK when this process cannot create a Metal
    // device. An ad-hoc TrollStore signature can be denied the GPU userclients
    // the Metal path needs, and the failure is silent: the map reports a
    // completed load while its render surface never produces a frame.
    [MAMapView setMetalEnabled:[self isMetalEffective]];
    // AMap 8+ requires privacy status before the first map view is created.
    [MAMapView updatePrivacyShow:AMapPrivacyShowStatusDidShow
                     privacyInfo:AMapPrivacyInfoStatusDidContain];
    [MAMapView updatePrivacyAgree:AMapPrivacyAgreeStatusDidAgree];
    return status;
}

+ (MAMapView * _Nullable)mapViewWithFrame:(CGRect)frame {
    if (CGRectIsEmpty(frame) || CGRectGetWidth(frame) < 1.0 || CGRectGetHeight(frame) < 1.0) {
        frame = [UIScreen mainScreen].bounds;
    }
    if (CGRectIsEmpty(frame)) {
        frame = CGRectMake(0.0, 0.0, 1.0, 1.0);
    }

    [self prepareSDK];

    AMapServices *services = [AMapServices sharedServices];
    services.regionLanguageType = AMapRegionLanguageTypeZhHans;
    MAMapView *mapView = [[MAMapView alloc] initWithFrame:frame];
    mapView.renderringDisabled = NO;
    mapView.drawingDisabled = NO;
    return mapView;
}
@end
