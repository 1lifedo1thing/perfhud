#import <UIKit/UIKit.h>
#import "PerfMetrics.h"

@interface PerfHUDView : UIView {
    PerfMetricsSnapshot _snapshot;
    BOOL _isWireframe;
    UIFont *_monoFont;
}

@property (nonatomic, assign) BOOL isWireframe;

- (void)updateWithSnapshot:(const PerfMetricsSnapshot *)snapshot;

@end
