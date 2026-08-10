#import <UIKit/UIKit.h>

@class MAMapView;

NS_ASSUME_NONNULL_BEGIN

@interface AMapMapViewFactory : NSObject
+ (MAMapView * _Nullable)mapViewWithFrame:(CGRect)frame;
@end

NS_ASSUME_NONNULL_END
