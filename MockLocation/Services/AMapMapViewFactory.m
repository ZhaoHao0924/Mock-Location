#import "AMapMapViewFactory.h"
#import <MAMapKit/MAMapView.h>
#import <MAMapKit/MAMapView+Resource.h>
#import <MAMapKit/MAMapVersion.h>

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
        status = [MAMapView setBundlePath:bundlePath];
    });
    return status;
}

+ (NSInteger)prepareSDK {
    NSInteger status = [self resourceBundleStatus];
    // The iOS 15 deployment target guarantees Metal support and avoids the
    // legacy OpenGLES renderer path in an unsigned TrollStore installation.
    [MAMapView setMetalEnabled:YES];
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
