#import "PerfHUDWindow.h"

#define HUD_WIDTH  126.0f
#define STATUS_BAR_OFFSET 22.0f
#define MARGIN_OFFSET 6.0f
#define PEEK_TAB_WIDTH 12.0f

@implementation PerfHUDWindow {
    NSInteger _currentPosition;
    UIInterfaceOrientation _currentOrientation;
}

@synthesize hudView = _hudView;
@synthesize tapBehavior = _tapBehavior;

- (id)init {
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    CGFloat initialH = 110.0f;
    self = [super initWithFrame:CGRectMake(screenBounds.size.width - HUD_WIDTH - MARGIN_OFFSET,
                                           STATUS_BAR_OFFSET + 2.0f,
                                           HUD_WIDTH,
                                           initialH)];
    if (self) {
        self.windowLevel = UIWindowLevelStatusBar + 150.0f;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;

        _currentPosition = 0;
        _currentOrientation = UIInterfaceOrientationPortrait;
        _tapBehavior = 1; // default: Hide / Peek (2 sec)
        _isStashed = NO;

        _hudView = [[PerfHUDView alloc] initWithFrame:self.bounds];
        _hudView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_hudView];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        tap.cancelsTouchesInView = YES;
        [self addGestureRecognizer:tap];
        [tap release];
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

- (void)updatePosition:(NSInteger)position withOrientation:(UIInterfaceOrientation)orientation {
    _currentPosition = position;
    _currentOrientation = orientation;

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

    self.bounds = CGRectMake(0, 0, HUD_WIDTH, currentH);

    CGFloat x = MARGIN_OFFSET + (HUD_WIDTH / 2.0f);
    CGFloat y = STATUS_BAR_OFFSET + 2.0f + (currentH / 2.0f);

    switch (position) {
        case 0: // Top-Right
            x = screenW - (HUD_WIDTH / 2.0f) - MARGIN_OFFSET;
            y = STATUS_BAR_OFFSET + 2.0f + (currentH / 2.0f);
            break;
        case 1: // Bottom-Right
            x = screenW - (HUD_WIDTH / 2.0f) - MARGIN_OFFSET;
            y = screenH - (currentH / 2.0f) - MARGIN_OFFSET;
            break;
        case 2: // Bottom-Left
            x = MARGIN_OFFSET + (HUD_WIDTH / 2.0f);
            y = screenH - (currentH / 2.0f) - MARGIN_OFFSET;
            break;
        case 3: // Top-Left
            x = MARGIN_OFFSET + (HUD_WIDTH / 2.0f);
            y = STATUS_BAR_OFFSET + 2.0f + (currentH / 2.0f);
            break;
        default:
            break;
    }

    // Apply stashing (peek tab)
    if (_isStashed) {
        // If on the right side (pos 0 or 1), push off right edge leaving PEEK_TAB_WIDTH visible
        if (position == 0 || position == 1) {
            x = screenW + (HUD_WIDTH / 2.0f) - PEEK_TAB_WIDTH;
        } else {
            // Push off left edge leaving PEEK_TAB_WIDTH visible
            x = -(HUD_WIDTH / 2.0f) + PEEK_TAB_WIDTH;
        }
    }

    CGPoint physicalCenter = CGPointMake(x, y);
    if (orientation == UIInterfaceOrientationLandscapeRight) {
        physicalCenter = CGPointMake(y, screenBounds.size.height - x);
    } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
        physicalCenter = CGPointMake(screenBounds.size.width - y, x);
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
    [_hudView removeFromSuperview];
    [_hudView release];
    _hudView = nil;
    [super dealloc];
}

@end
