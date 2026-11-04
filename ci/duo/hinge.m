// Folds and turns the iPhone Duo simulator from inside it: ci/duo.sh builds this for the simulator
// and runs it with `xcrun simctl spawn`. It posts the vendor-defined HID event that Xcode's Device
// Hub sends for its hinge slider and its Rotate buttons, and reads the angle back from CoreMotion,
// which UIKit's hinge reads too. Private and undocumented: a later Xcode may change it, and then
// ci/duo.sh fails by name rather than shooting the wrong pose.
//
//   hinge set <degrees> <confirm-seconds>    0 closed … 180 flat; waits until CoreMotion reports it
//   hinge orient <portrait|landscape-left|landscape-right|pud>
//   hinge get
//
// Adapted from hinge 0.3.0 (https://github.com/artemnovichkov/hinge, skills/hinge/scripts/
// hinge_helper.m), MIT License, Copyright (c) 2026 Artem Novichkov:
//
//   Permission is hereby granted, free of charge, to any person obtaining a copy of this software
//   and associated documentation files (the "Software"), to deal in the Software without
//   restriction, including without limitation the rights to use, copy, modify, merge, publish,
//   distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
//   Software is furnished to do so, subject to the following conditions: The above copyright
//   notice and this permission notice shall be included in all copies or substantial portions of
//   the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
//   PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
//   LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
//   OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//   DEALINGS IN THE SOFTWARE.

#import <Foundation/Foundation.h>

#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

extern IOHIDEventRef IOHIDEventCreateVendorDefinedEvent(CFAllocatorRef allocator, uint64_t timeStamp,
    uint32_t usagePage, uint32_t usage, uint32_t version, const uint8_t *data, CFIndex length, uint32_t options);
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreateWithType(CFAllocatorRef allocator, int type,
    CFDictionaryRef properties);
extern void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef client, IOHIDEventRef event);
extern CFDataRef IOCFSerialize(CFTypeRef object, CFOptionFlags options);

enum { kUsagePage = 0xFF61, kUsage = 0x5B, kClientTypeSimple = 4, kSerializeBinary = 1 };

// The provider Device Hub names for both its hinge slider and its orientation picker.
static CFStringRef const kProvider = CFSTR("com.apple.Virtualization.VirtualMachines");
// How close a reported angle must be to count as the one sent.
static const double kAngleTolerance = 0.5;
static const CFTimeInterval kRunLoopSlice = 0.05;
// Time for the last event to leave before the process exits.
static const useconds_t kSettleMicros = 20000;

// CoreMotion's private angle API, the source of UIKit's hinge.
@interface CMAngle : NSObject
- (float)angleDegrees;
@end

@interface CMAngleManager : NSObject
+ (BOOL)isAvailable;
- (void)startAngleUpdatesToQueue:(NSOperationQueue *)queue handler:(void (^)(CMAngle *angle))handler;
- (void)stopAngleUpdates;
@end

static void send_payload(IOHIDEventSystemClientRef client, CFStringRef source, CFStringRef type, CFTypeRef value) {
    const void *keys[] = {CFSTR("provider"), CFSTR("source"), CFSTR("type"), CFSTR("value")};
    const void *values[] = {kProvider, source, type, value};
    CFDictionaryRef payload = CFDictionaryCreate(NULL, keys, values, 4,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDataRef data = IOCFSerialize(payload, kSerializeBinary);
    if (data) {
        IOHIDEventRef event = IOHIDEventCreateVendorDefinedEvent(NULL, mach_absolute_time(), kUsagePage, kUsage, 0,
            CFDataGetBytePtr(data), CFDataGetLength(data), 0);
        if (event) {
            IOHIDEventSystemClientDispatchEvent(client, event);
            CFRelease(event);
        }
        CFRelease(data);
    }
    CFRelease(payload);
}

static void send_angle(IOHIDEventSystemClientRef client, double degrees) {
    CFNumberRef value = CFNumberCreate(NULL, kCFNumberDoubleType, &degrees);
    send_payload(client, CFSTR("hinge-slider-control"), CFSTR("range"), value);
    CFRelease(value);
}

// Device Hub's Rotate Left and Right send the orientation to turn to.
static void send_orientation(IOHIDEventSystemClientRef client, const char *orientation) {
    CFStringRef value = CFStringCreateWithCString(NULL, orientation, kCFStringEncodingUTF8);
    send_payload(client, CFSTR("orientation-picker-control"), CFSTR("enum"), value);
    CFRelease(value);
}

// Starts angle updates, runs `afterStart`, then waits until `accept` takes an update or `timeout`
// passes (CoreMotion delivers the current angle at once). 1 accepted, 0 timed out, -1 no hinge.
static int observe_angles(CFTimeInterval timeout, void (^afterStart)(void), bool (^accept)(double degrees)) {
    Class managerClass = NSClassFromString(@"CMAngleManager");
    if (!managerClass || ![managerClass isAvailable]) {
        fprintf(stderr, "hinge: this simulator reports no hinge\n");
        return -1;
    }
    id manager = [[managerClass alloc] init];
    __block bool accepted = false;
    [manager startAngleUpdatesToQueue:[NSOperationQueue new] handler:^(CMAngle *angle) {
        if (!accepted && accept([angle angleDegrees])) accepted = true;
    }];
    if (afterStart) afterStart();
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + timeout;
    while (!accepted && CFAbsoluteTimeGetCurrent() < deadline) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, kRunLoopSlice, false);
    }
    [manager stopAngleUpdates];
    return accepted ? 1 : 0;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "get") == 0) {
        __block double current = 0;
        int result = observe_angles(2, NULL, ^bool(double degrees) { current = degrees; return true; });
        if (result != 1) return 1;
        printf("%.1f\n", current);
        return 0;
    }
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreateWithType(NULL, kClientTypeSimple, NULL);
    if (!client) {
        fprintf(stderr, "hinge: no HID event system client\n");
        return 1;
    }
    if (argc == 4 && strcmp(argv[1], "set") == 0) {
        double target = fmin(fmax(atof(argv[2]), 0), 180), timeout = atof(argv[3]);
        int result = observe_angles(timeout, ^{ send_angle(client, target); }, ^bool(double reported) {
            return fabs(reported - target) <= kAngleTolerance;
        });
        if (result == 0) fprintf(stderr, "hinge: the angle did not reach %.1f within %.1f s\n", target, timeout);
        usleep(kSettleMicros);
        return result == 1 ? 0 : 1;
    }
    if (argc == 3 && strcmp(argv[1], "orient") == 0) {
        send_orientation(client, argv[2]);
        usleep(kSettleMicros);
        return 0;
    }
    fprintf(stderr, "usage: hinge set <degrees> <confirm-seconds> | orient <orientation> | get\n");
    return 64;
}
