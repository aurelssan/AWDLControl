//
//  TrafficMonitor.m
//  AWDLControl
//

#import "TrafficMonitor.h"

#import <SystemConfiguration/SystemConfiguration.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <net/if_dl.h>

static const NSTimeInterval SampleInterval = 1.0;

@interface TrafficMonitor ()

@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, copy) NSString *bsdName;
@property (nonatomic) uint32_t lastIn;
@property (nonatomic) uint32_t lastOut;
@property (nonatomic) BOOL hasBaseline;

@end

@implementation TrafficMonitor

// The kernel exposes 32-bit byte counters on macOS. At one sample per second a
// counter can wrap at most once between two samples (that would require 4 GB/s),
// so summing across the wrap point is enough to recover the true delta.
static uint64_t Delta32(uint32_t previous, uint32_t current) {
    if (current >= previous) {
        return (uint64_t)(current - previous);
    }
    return (uint64_t)UINT32_MAX - previous + current + 1;
}

- (NSString *)wifiInterfaceName {
    NSArray *interfaces = CFBridgingRelease(SCNetworkInterfaceCopyAll());
    for (id object in interfaces) {
        SCNetworkInterfaceRef interface = (__bridge SCNetworkInterfaceRef)object;
        CFStringRef type = SCNetworkInterfaceGetInterfaceType(interface);
        if (!type || !CFEqual(type, kSCNetworkInterfaceTypeIEEE80211)) {
            continue;
        }
        CFStringRef bsdName = SCNetworkInterfaceGetBSDName(interface);
        if (!bsdName) {
            continue;
        }
        NSString *name = (__bridge NSString *)bsdName;
        // awdl0 and llw0 also report as IEEE80211 but they are not the primary link.
        if ([name hasPrefix:@"awdl"] || [name hasPrefix:@"llw"]) {
            continue;
        }
        return name;
    }
    return nil;
}

- (BOOL)readCountersIn:(uint32_t *)inBytes out:(uint32_t *)outBytes {
    if (self.bsdName.length == 0) {
        self.bsdName = [self wifiInterfaceName];
        if (self.bsdName.length == 0) {
            return NO;
        }
    }

    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0) {
        return NO;
    }

    BOOL found = NO;
    const char *target = self.bsdName.UTF8String;
    for (struct ifaddrs *ifa = list; ifa != NULL; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_LINK || !ifa->ifa_data) {
            continue;
        }
        if (strcmp(ifa->ifa_name, target) != 0) {
            continue;
        }
        struct if_data *data = (struct if_data *)ifa->ifa_data;
        *inBytes = data->ifi_ibytes;
        *outBytes = data->ifi_obytes;
        found = YES;
        break;
    }

    freeifaddrs(list);
    return found;
}

- (void)sample {
    uint32_t inBytes = 0;
    uint32_t outBytes = 0;
    if (![self readCountersIn:&inBytes out:&outBytes]) {
        // No Wi-Fi link: forget the interface and report a quiet network.
        self.bsdName = nil;
        self.hasBaseline = NO;
        if (self.updateHandler) {
            self.updateHandler(0.0);
        }
        return;
    }

    double rate = 0.0;
    if (self.hasBaseline) {
        uint64_t delta = Delta32(self.lastIn, inBytes) + Delta32(self.lastOut, outBytes);
        rate = (double)delta / SampleInterval;
    }

    self.lastIn = inBytes;
    self.lastOut = outBytes;
    self.hasBaseline = YES;

    if (self.updateHandler) {
        self.updateHandler(rate);
    }
}

- (void)start {
    if (self.timer) {
        return;
    }
    self.bsdName = nil;
    self.hasBaseline = NO;
    [self sample];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:SampleInterval
                                                  target:self
                                                selector:@selector(timerFired:)
                                                userInfo:nil
                                                 repeats:YES];
    self.timer.tolerance = 0.2;
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
    self.bsdName = nil;
    self.hasBaseline = NO;
}

- (void)timerFired:(NSTimer *)timer {
    [self sample];
}

- (void)dealloc {
    [_timer invalidate];
}

@end
