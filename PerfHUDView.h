#import <UIKit/UIKit.h>
#import "PerfMetrics.h"

@interface PerfHUDView : UIView {
    PerfMetricsSnapshot _snapshot;
    BOOL _isWireframe;
    UIFont *_monoFont;
    UIFont *_smallFont;

    // Visibility options
    BOOL _showFps;
    BOOL _showCpu;
    BOOL _showRam;
    BOOL _showNet;
    BOOL _showDiskSpace;
    BOOL _showDiskIo;
}

@property (nonatomic, assign) BOOL isWireframe;
@property (nonatomic, assign) BOOL showFps;
@property (nonatomic, assign) BOOL showCpu;
@property (nonatomic, assign) BOOL showRam;
@property (nonatomic, assign) BOOL showNet;
@property (nonatomic, assign) BOOL showDiskSpace;
@property (nonatomic, assign) BOOL showDiskIo;

- (void)updateWithSnapshot:(const PerfMetricsSnapshot *)snapshot;
- (CGFloat)calculateContentHeight;

@end
