#import <UIKit/UIKit.h>
#import <MAMapKit/MAMapView.h>

NS_ASSUME_NONNULL_BEGIN

@interface AMapMapViewFactory : NSObject
+ (nullable NSString *)resourceBundleVersion;
+ (NSInteger)resourceBundleStatus;
+ (NSInteger)prepareSDK;
+ (MAMapView * _Nullable)mapViewWithFrame:(CGRect)frame;
@end

NS_ASSUME_NONNULL_END
