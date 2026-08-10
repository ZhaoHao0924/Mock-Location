#import <UIKit/UIKit.h>
#import <MAMapKit/MAMapView.h>

NS_ASSUME_NONNULL_BEGIN

@interface AMapMapViewFactory : NSObject
+ (nullable NSString *)resourceBundleVersion;
+ (NSInteger)resourceBundleStatus;
/// YES when the process can actually create a Metal device. An ad-hoc
/// TrollStore signature can be denied the GPU userclients Metal needs.
+ (BOOL)isMetalAvailable;
/// YES when the Metal renderer is selected by preference (defaults to YES).
+ (BOOL)isMetalPreferred;
+ (NSInteger)prepareSDK;
+ (MAMapView * _Nullable)mapViewWithFrame:(CGRect)frame;
@end

NS_ASSUME_NONNULL_END
