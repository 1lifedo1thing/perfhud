#import <UIKit/UIKit.h>
#import "PerfHUDView.h"

@interface PerfHUDWindow : UIWindow {
    PerfHUDView *_hudView;
    NSInteger _tapBehavior; // 0: Jump corner, 1: Pip/peek hide
    BOOL _isStashed;
    NSTimer *_stashTimer;
}

@property (nonatomic, readonly) PerfHUDView *hudView;
@property (nonatomic, assign) NSInteger tapBehavior;

- (void)cycleToNextPosition;
- (void)updatePosition:(NSInteger)position withOrientation:(UIInterfaceOrientation)orientation;
- (void)recalculateLayout;

@end
