//
//  TrafficMonitor.h
//  AWDLControl
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Samples the Wi-Fi interface byte counters once per second and reports the
/// combined up+down throughput in bytes per second.
@interface TrafficMonitor : NSObject

/// Called on the main queue roughly once per second with the current throughput.
@property (nonatomic, copy, nullable) void (^updateHandler)(double bytesPerSecond);

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
