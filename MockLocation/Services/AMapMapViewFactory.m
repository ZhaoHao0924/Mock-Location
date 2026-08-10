#import "AMapMapViewFactory.h"
#import <MAMapKit/MAMapView.h>

@implementation AMapMapViewFactory

+ (MAMapView * _Nullable)mapViewWithFrame:(CGRect)frame {
    return [[MAMapView alloc] initWithFrame:frame];
}
@end
