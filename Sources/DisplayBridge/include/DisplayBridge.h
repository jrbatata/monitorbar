#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN
int MBGetBrightness(uint32_t display, float *value);
int MBSetBrightness(uint32_t display, float value);
BOOL MBCanRotate(uint32_t display);
BOOL MBSetRotation(uint32_t display, int degrees);
NSDictionary * _Nullable MBDisplayDetails(uint32_t display);

@interface MBDDC : NSObject
+ (NSArray<MBDDC *> *)connections;
@property(nonatomic, readonly) NSString *location;
@property(nonatomic, readonly) NSString *name;
@property(nonatomic, readonly) NSNumber *serial;
- (BOOL)readBrightness:(uint16_t *)current maximum:(uint16_t *)maximum;
- (BOOL)setBrightness:(uint16_t)value;
@end
NS_ASSUME_NONNULL_END
