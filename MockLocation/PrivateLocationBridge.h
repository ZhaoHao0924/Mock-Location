#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PrivateLocationBridge : NSObject

+ (BOOL)isAvailable;
+ (nullable NSString *)availabilityMessage;
+ (BOOL)startWithLocations:(NSArray<CLLocation *> *)locations
                     error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)stopWithError:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
