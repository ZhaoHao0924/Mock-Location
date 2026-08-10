#import "AMapMapViewFactory.h"
#import <MAMapKit/MAMapView.h>

@implementation AMapMapViewFactory

+ (MAMapView * _Nullable)mapViewWithFrame:(CGRect)frame {
    if (CGRectIsEmpty(frame) || CGRectGetWidth(frame) < 1.0 || CGRectGetHeight(frame) < 1.0) {
        frame = [UIScreen mainScreen].bounds;
    }
    if (CGRectIsEmpty(frame)) {
        frame = CGRectMake(0.0, 0.0, 1.0, 1.0);
    }
    return [[MAMapView alloc] initWithFrame:frame];
}
@end
