#import "PerfHUDWindow.h"

#define HUD_WIDTH  126.0f
#define STATUS_BAR_OFFSET 22.0f
#define MARGIN_OFFSET 6.0f
#define PEEK_TAB_WIDTH 12.0f

@interface UIWindow (PrivateContext)
- (void)_destroyContext;
- (void)_createContext;
- (BOOL)_ignoresHitTest;
@end

@interface UIApplication (StatusBarPrivate)
- (id)statusBar;
@end

@interface UIStatusBar : UIView
- (CGFloat)currentHeight;
@end

@implementation PerfHUDWindow {
    NSInteger _currentPosition;
    UIInterfaceOrientation _currentOrientation;
}

@synthesize hudView = _hudView;
@synthesize tapBehavior = _tapBehavior;
@synthesize currentOrientation = _currentOrientation;

- (void)setTapBehavior:(NSInteger)behavior {
    BOOL changed = (_tapBehavior != behavior);
    _tapBehavior = behavior;
    
    // Reset stashing when behavior changes
    if (_stashTimer) {
        [_stashTimer invalidate];
        _stashTimer = nil;
    }
    _isStashed = NO;
    
    // Always sync interaction & gesture with pass-through mode
    self.userInteractionEnabled = (_tapBehavior != 2);
    if (_tapGesture) {
        _tapGesture.enabled = (_tapBehavior != 2);
    }

    // Recreate WindowServer CAContext so _ignoresHitTest takes effect across processes
    if (changed || _tapBehavior == 2) {
        if ([self respondsToSelector:@selector(_destroyContext)] &&
            [self respondsToSelector:@selector(_createContext)]) {
            [self _destroyContext];
            [self _createContext];
            self.hidden = NO;
        }
    }
}

- (BOOL)_ignoresHitTest {
    return (_tapBehavior == 2);
}

- (id)init {
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    CGFloat initialH = 110.0f;
    self = [super initWithFrame:CGRectMake(screenBounds.size.width - HUD_WIDTH - MARGIN_OFFSET,
                                           STATUS_BAR_OFFSET + 2.0f,
                                           HUD_WIDTH,
                                           initialH)];
    if (self) {
        self.opaque = NO;
        self.windowLevel = UIWindowLevelStatusBar + 150.0f;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;

        _currentPosition = 0;
        _currentOrientation = UIInterfaceOrientationPortrait;
        _tapBehavior = -1; // Force setTapBehavior: to initialize context
        _isStashed = NO;

        _hudView = [[PerfHUDView alloc] initWithFrame:self.bounds];
        _hudView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_hudView];

        _tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        _tapGesture.cancelsTouchesInView = YES;
        _tapGesture.enabled = (_tapBehavior != 2);
        [self addGestureRecognizer:_tapGesture];
    }
    return self;
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;

    if (_tapBehavior == 1) { // Pip peek / stash behavior
        if (_isStashed) {
            [self unstash];
        } else {
            [self stash];
        }
    } else {
        [self cycleToNextPosition];
    }
}

- (void)stash {
    if (_stashTimer) {
        [_stashTimer invalidate];
        _stashTimer = nil;
    }
    _isStashed = YES;
    [self updatePosition:_currentPosition withOrientation:_currentOrientation];

    // Automatically return after 2.0 seconds
    _stashTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                   target:self
                                                 selector:@selector(unstash)
                                                 userInfo:nil
                                                  repeats:NO];
}

- (void)unstash {
    if (_stashTimer) {
        [_stashTimer invalidate];
        _stashTimer = nil;
    }
    _isStashed = NO;
    [self updatePosition:_currentPosition withOrientation:_currentOrientation];
}

- (void)cycleToNextPosition {
    _isStashed = NO;
    _currentPosition = (_currentPosition + 1) % 4;
    [self updatePosition:_currentPosition withOrientation:_currentOrientation];
}

- (void)recalculateLayout {
    [self updatePosition:_currentPosition withOrientation:_currentOrientation];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (_tapBehavior == 2) { // Passthrough mode: complete click-through for games
        return nil;
    }
    return [super hitTest:point withEvent:event];
}

- (void)updatePosition:(NSInteger)position withOrientation:(UIInterfaceOrientation)orientation {
    _currentPosition = position;
    _currentOrientation = orientation;

    CGFloat currentW = [_hudView calculateContentWidth];
    CGFloat currentH = [_hudView calculateContentHeight];
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    
    CGFloat screenW = screenBounds.size.width;
    CGFloat screenH = screenBounds.size.height;
    if (UIInterfaceOrientationIsLandscape(orientation)) {
        screenW = screenBounds.size.height;
        screenH = screenBounds.size.width;
    }

    self.transform = CGAffineTransformIdentity;
    if (orientation == UIInterfaceOrientationLandscapeLeft) {
        self.transform = CGAffineTransformMakeRotation(-M_PI_2);
    } else if (orientation == UIInterfaceOrientationLandscapeRight) {
        self.transform = CGAffineTransformMakeRotation(M_PI_2);
    } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
        self.transform = CGAffineTransformMakeRotation(M_PI);
    }

    self.bounds = CGRectMake(0, 0, currentW, currentH);
    _hudView.frame = self.bounds;

    UIApplication *app = [UIApplication sharedApplication];
    BOOL isStatusBarHidden = [app isStatusBarHidden];
    if (!isStatusBarHidden && [app respondsToSelector:@selector(statusBar)]) {
        UIStatusBar *sb = (UIStatusBar *)[app statusBar];
        if (sb && ([sb respondsToSelector:@selector(currentHeight)] ? [sb currentHeight] <= 0.0f : sb.hidden)) {
            isStatusBarHidden = YES;
        }
    }
    CGFloat topOffset = isStatusBarHidden ? MARGIN_OFFSET : (STATUS_BAR_OFFSET + 2.0f);

    CGFloat x = MARGIN_OFFSET + (currentW / 2.0f);
    CGFloat y = topOffset + (currentH / 2.0f);

    switch (position) {
        case 0: // Top-Right
            x = screenW - (currentW / 2.0f) - MARGIN_OFFSET;
            y = topOffset + (currentH / 2.0f);
            break;
        case 1: // Bottom-Right
            x = screenW - (currentW / 2.0f) - MARGIN_OFFSET;
            y = screenH - (currentH / 2.0f) - MARGIN_OFFSET;
            break;
        case 2: // Bottom-Left
            x = MARGIN_OFFSET + (currentW / 2.0f);
            y = screenH - (currentH / 2.0f) - MARGIN_OFFSET;
            break;
        case 3: // Top-Left
            x = MARGIN_OFFSET + (currentW / 2.0f);
            y = topOffset + (currentH / 2.0f);
            break;
        default:
            break;
    }

    // Apply stashing (peek tab)
    if (_isStashed) {
        // If on the right side (pos 0 or 1), push off right edge leaving PEEK_TAB_WIDTH visible
        if (position == 0 || position == 1) {
            x = screenW + (currentW / 2.0f) - PEEK_TAB_WIDTH;
        } else {
            // Push off left edge leaving PEEK_TAB_WIDTH visible
            x = -(currentW / 2.0f) + PEEK_TAB_WIDTH;
        }
    }

    CGPoint physicalCenter = CGPointMake(x, y);
    if (orientation == UIInterfaceOrientationLandscapeRight) {
        physicalCenter = CGPointMake(screenBounds.size.width - y, x);
    } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
        physicalCenter = CGPointMake(y, screenBounds.size.height - x);
    } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
        physicalCenter = CGPointMake(screenBounds.size.width - x, screenBounds.size.height - y);
    }

    self.center = physicalCenter;
}

- (void)dealloc {
    if (_stashTimer) {
        [_stashTimer invalidate];
        _stashTimer = nil;
    }
    if (_tapGesture) {
        [self removeGestureRecognizer:_tapGesture];
        [_tapGesture release];
        _tapGesture = nil;
    }
    [_hudView removeFromSuperview];
    [_hudView release];
    _hudView = nil;
    [super dealloc];
}

@end
