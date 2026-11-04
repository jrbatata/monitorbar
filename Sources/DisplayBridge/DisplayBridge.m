#import "DisplayBridge.h"
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <objc/message.h>
#include <unistd.h>

// Optional private interfaces, resolved at runtime. No hard link to a private framework.
static void *library(const char *path) { return dlopen(path, RTLD_LAZY | RTLD_LOCAL); }
static void *displayServices(void) {
    static void *handle; static dispatch_once_t once;
    dispatch_once(&once, ^{ handle = library("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"); });
    return handle;
}
int MBGetBrightness(uint32_t display, float *value) {
    void *handle = displayServices();
    int (*fn)(uint32_t, float *) = handle ? dlsym(handle, "DisplayServicesGetBrightness") : NULL;
    return fn ? fn(display, value) : -1;
}
int MBSetBrightness(uint32_t display, float value) {
    void *handle = displayServices();
    int (*fn)(uint32_t, float) = handle ? dlsym(handle, "DisplayServicesSetBrightness") : NULL;
    return fn ? fn(display, value) : -1;
}
NSDictionary *MBDisplayDetails(uint32_t display) {
    static void *handle; static dispatch_once_t once;
    dispatch_once(&once, ^{ handle = library("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay"); });
    CFDictionaryRef (*fn)(uint32_t) = handle ? dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary") : NULL;
    return fn ? CFBridgingRelease(fn(display)) : nil;
}
static id panel(uint32_t display) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ library("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel"); });
    Class cls = NSClassFromString(@"MPDisplay");
    SEL initSelector = NSSelectorFromString(@"initWithCGSDisplayID:");
    if (!cls || ![cls instancesRespondToSelector:initSelector]) return nil;
    return ((id (*)(id, SEL, uint32_t))objc_msgSend)([cls alloc], initSelector, display);
}
BOOL MBCanRotate(uint32_t display) {
    if (CGDisplayIsBuiltin(display)) return NO;
    id object = panel(display);
    NSMethodSignature *signature = [object methodSignatureForSelector:NSSelectorFromString(@"setOrientation:")];
    if (!signature || signature.numberOfArguments != 3) return NO;
    const char *type = [signature getArgumentTypeAtIndex:2];
    return strchr("iIqQ", type[0]) != NULL;
}
BOOL MBSetRotation(uint32_t display, int degrees) {
    if (!MBCanRotate(display) || (degrees != 0 && degrees != 90 && degrees != 180 && degrees != 270)) return NO;
    @try {
        id object = panel(display);
        SEL selector = NSSelectorFromString(@"setOrientation:");
        NSMethodSignature *signature = [object methodSignatureForSelector:selector];
        NSInvocation *call = [NSInvocation invocationWithMethodSignature:signature];
        call.target = object; call.selector = selector;
        long long wide = degrees; int narrow = degrees;
        const char *type = [signature getArgumentTypeAtIndex:2];
        [call setArgument:(type[0] == 'q' || type[0] == 'Q') ? (void *)&wide : (void *)&narrow atIndex:2];
        [call invoke]; return YES;
    } @catch (NSException *exception) { return NO; }
}

typedef CFTypeRef (*AVCreate)(CFAllocatorRef, io_service_t);
typedef IOReturn (*AVIO)(CFTypeRef, uint32_t, uint32_t, void *, uint32_t);
static AVCreate createAV;
static AVIO readAV, writeAV;
static void setupAV(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = library("/System/Library/Frameworks/IOKit.framework/IOKit");
        if (h) { createAV = dlsym(h, "IOAVServiceCreateWithService"); readAV = dlsym(h, "IOAVServiceReadI2C"); writeAV = dlsym(h, "IOAVServiceWriteI2C"); }
    });
}
static id property(io_registry_entry_t entry, NSString *key) {
    return CFBridgingRelease(IORegistryEntryCreateCFProperty(entry, (__bridge CFStringRef)key, kCFAllocatorDefault, 0));
}

@implementation MBDDC {
    CFTypeRef _service;
}
+ (NSArray<MBDDC *> *)connections {
    setupAV();
    if (!createAV || !readAV || !writeAV) return @[];
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) != KERN_SUCCESS) return @[];
    NSMutableArray *results = [NSMutableArray array];
    io_service_t entry;
    while ((entry = IOIteratorNext(iterator))) {
        if ([property(entry, @"Location") isEqual:@"External"]) {
            CFTypeRef service = createAV(kCFAllocatorDefault, entry);
            if (service) {
                // Match only a framebuffer ancestor of this connection; never guess from enumeration order.
                io_registry_entry_t cursor = entry; IOObjectRetain(cursor);
                NSString *location = nil; NSDictionary *attributes = nil;
                for (int depth = 0; depth < 12; depth++) {
                    id candidate = property(cursor, @"DisplayAttributes");
                    if ([candidate isKindOfClass:[NSDictionary class]]) {
                        attributes = candidate;
                        io_string_t path = {0};
                        if (IORegistryEntryGetPath(cursor, kIOServicePlane, path) == KERN_SUCCESS) location = @(path);
                        break;
                    }
                    io_registry_entry_t parent = 0;
                    if (IORegistryEntryGetParentEntry(cursor, kIOServicePlane, &parent) != KERN_SUCCESS) break;
                    IOObjectRelease(cursor); cursor = parent;
                }
                IOObjectRelease(cursor);
                if (location) {
                    MBDDC *connection = [MBDDC new]; connection->_service = service;
                    connection->_location = [location copy];
                    NSDictionary *product = attributes[@"ProductAttributes"];
                    connection->_name = [product[@"ProductName"] isKindOfClass:[NSString class]] ? product[@"ProductName"] : @"";
                    connection->_serial = [product[@"SerialNumber"] isKindOfClass:[NSNumber class]] ? product[@"SerialNumber"] : @0;
                    [results addObject:connection];
                } else { CFRelease(service); }
            }
        }
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
    return results;
}
- (void)dealloc { if (_service) CFRelease(_service); }
- (BOOL)readBrightness:(uint16_t *)current maximum:(uint16_t *)maximum {
    // DDC/CI VCP 0x10. Read request checksum includes the destination address.
    uint8_t request[] = {0x82, 0x01, 0x10, 0x00};
    request[3] = 0x6e ^ request[0] ^ request[1] ^ request[2];
    for (int attempt = 0; attempt < 3; attempt++) {
        if (writeAV(_service, 0x37, 0x51, request, sizeof(request)) != 0) continue;
        usleep(50000);
        uint8_t response[11] = {0};
        if (readAV(_service, 0x37, 0, response, sizeof(response)) != 0) continue;
        uint8_t checksum = 0x50;
        for (int i = 0; i < 10; i++) checksum ^= response[i];
        if (checksum != response[10] || response[0] != 0x6e || response[2] != 0x02 || response[3] != 0 || response[4] != 0x10) continue;
        uint16_t max = ((uint16_t)response[6] << 8) | response[7];
        uint16_t value = ((uint16_t)response[8] << 8) | response[9];
        if (!max || value > max) continue;
        *current = value; *maximum = max; return YES;
    }
    return NO;
}
- (BOOL)setBrightness:(uint16_t)value {
    uint8_t packet[] = {0x84, 0x03, 0x10, value >> 8, value & 0xff, 0};
    uint8_t checksum = 0x6e ^ 0x51;
    for (int i = 0; i < 5; i++) checksum ^= packet[i];
    packet[5] = checksum;
    for (int i = 0; i < 3; i++) {
        usleep(10000);
        if (writeAV(_service, 0x37, 0x51, packet, sizeof(packet)) == 0) return YES;
    }
    return NO;
}
@end
