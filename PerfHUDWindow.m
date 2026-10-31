#import "PerfHUDWindow.h"

#define HUD_WIDTH  126.0f
#define HUD_HEIGHT 110.0f
#define STATUS_BAR_OFFSET 22.0f
#define MARGIN_OFFSET 6.0f

@implementation PerfHUDWindow {
    NSInteger _currentPosition;
    UIInterfaceOrientation _currentOrientation;
}

@synthesize hudView = _hudView;

- (id)init {
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    self = [super initWithFrame:CGRectMake(screenBounds.size.width - HUD_WIDTH - MARGIN_OFFSET,
                                           STATUS_BAR_OFFSET + 2.0f,
                                           HUD_WIDTH,
                                           HUD_HEIGHT)];
    if (self) {
        self.windowLevel = UIWindowLevelStatusBar + 150.0f;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;

        _currentPosition = 0;
        _currentOrientation = UIInterfaceOrientationPortrait;
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
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [self cycleToNextPosition];
    }
}

- (void)cycleToNextPosition {
    _currentPosition = (_currentPosition + 1) % 4;
    [self updatePosition:_currentPosition withOrientation:_currentOrientation];
}

- (void)updatePosition:(NSInteger)position withOrientation:(UIInterfaceOrientation)orientation {
    _currentPosition = position;
    _currentOrientation = orientation;

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

    self.bounds = CGRectMake(0, 0, HUD_WIDTH, HUD_HEIGHT);

    CGFloat x = MARGIN_OFFSET + (HUD_WIDTH / 2.0f);
    CGFloat y = STATUS_BAR_OFFSET + 2.0f + (HUD_HEIGHT / 2.0f);

    switch (position) {
        case 0: // Top-Right
            x = screenW - (HUD_WIDTH / 2.0f) - MARGIN_OFFSET;
            y = STATUS_BAR_OFFSET + 2.0f + (HUD_HEIGHT / 2.0f);
            break;
        case 1: // Bottom-Right
            x = screenW - (HUD_WIDTH / 2.0f) - MARGIN_OFFSET;
            y = screenH - (HUD_HEIGHT / 2.0f) - MARGIN_OFFSET;
            break;
        case 2: // Bottom-Left
            x = MARGIN_OFFSET + (HUD_WIDTH / 2.0f);
            y = screenH - (HUD_HEIGHT / 2.0f) - MARGIN_OFFSET;
            break;
        case 3: // Top-Left
            x = MARGIN_OFFSET + (HUD_WIDTH / 2.0f);
            y = STATUS_BAR_OFFSET + 2.0f + (HUD_HEIGHT / 2.0f);
            break;
        default:
            break;
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
    [_hudView removeFromSuperview];
    [_hudView release];
    _hudView = nil;
    [super dealloc];
}

@end
