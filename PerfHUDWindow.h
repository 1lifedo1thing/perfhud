#import <UIKit/UIKit.h>
#import "PerfHUDView.h"

@interface PerfHUDWindow : UIWindow {
    PerfHUDView *_hudView;
}

@property (nonatomic, readonly) PerfHUDView *hudView;

- (void)cycleToNextPosition;
- (void)updatePosition:(NSInteger)position withOrientation:(UIInterfaceOrientation)orientation;

@end
