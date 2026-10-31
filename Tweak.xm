#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <stdio.h>
#import <time.h>
#import "PerfHUDWindow.h"
#import "PerfMetrics.h"

static PerfHUDWindow *s_hudWindow = nil;
static CADisplayLink *s_displayLink = nil;
static NSTimer *s_updateTimer = nil;

static NSUInteger s_frameCount = 0;
static CFTimeInterval s_lastFpsTimestamp = 0;
static float s_calculatedFps = 60.0f;
static PerfMetricsSnapshot s_snapshot;

// Settings
static BOOL s_enabled = YES;
static NSInteger s_position = 0;
static BOOL s_isWireframe = NO;
static double s_refreshInterval = 0.5;

static void LoadSettings(void) {
    CFPreferencesAppSynchronize(CFSTR("com.noname122021.perfhud"));
    Boolean valid = false;

    Boolean bEnabled = CFPreferencesGetAppBooleanValue(CFSTR("enabled"), CFSTR("com.noname122021.perfhud"), &valid);
    s_enabled = valid ? (BOOL)bEnabled : YES;

    CFIndex pos = CFPreferencesGetAppIntegerValue(CFSTR("position"), CFSTR("com.noname122021.perfhud"), &valid);
    s_position = valid ? (NSInteger)pos : 0;

    Boolean bWire = CFPreferencesGetAppBooleanValue(CFSTR("wireframe"), CFSTR("com.noname122021.perfhud"), &valid);
    s_isWireframe = valid ? (BOOL)bWire : NO;
}

static UIInterfaceOrientation GetCurrentActiveOrientation(void) {
    UIApplication *app = [UIApplication sharedApplication];
    return [app statusBarOrientation];
}

static void OnDisplayLinkTick(CADisplayLink *link) {
    s_frameCount++;
    CFTimeInterval now = link.timestamp;
    if (s_lastFpsTimestamp == 0) {
        s_lastFpsTimestamp = now;
        return;
    }

    CFTimeInterval delta = now - s_lastFpsTimestamp;
    if (delta >= 0.5) {
        s_calculatedFps = (float)((double)s_frameCount / delta);
        if (s_calculatedFps > 60.0f) s_calculatedFps = 60.0f;
        s_frameCount = 0;
        s_lastFpsTimestamp = now;
    }
}

static void ExportTelemetrySnapshot(void) {
    time_t rawtime;
    struct tm *timeinfo;
    char timeStr[32];

    time(&rawtime);
    timeinfo = localtime(&rawtime);
    strftime(timeStr, sizeof(timeStr), "%H:%M:%S", timeinfo);

    // Atomic write to /var/tmp/perfhud.stat (RAM disk)
    FILE *f = fopen("/var/tmp/perfhud.stat", "w");
    if (f) {
        fprintf(f, "[%s] FPS:%4.1f CPU:%3.0f%% (C0:%2.0f%% C1:%2.0f%%) RAM:%.2fM/%.1fM (W:%.0f A:%.0f I:%.0f F:%.0f)\n",
                timeStr,
                s_snapshot.fps.current,
                s_snapshot.cpu_total.current,
                s_snapshot.cpu_cores[0].current,
                s_snapshot.cpu_cores[1].current,
                (s_snapshot.ram_free_mb + s_snapshot.ram_inactive_mb),
                s_snapshot.ram_total_mb,
                s_snapshot.ram_wired_mb,
                s_snapshot.ram_active_mb,
                s_snapshot.ram_inactive_mb,
                s_snapshot.ram_free_mb);
        fclose(f);
    }
}

static void OnTimerTick(NSTimer *timer) {
    if (!s_enabled || !s_hudWindow) return;

    PerfMetrics_Update(&s_snapshot, s_calculatedFps);
    [s_hudWindow.hudView updateWithSnapshot:&s_snapshot];
    ExportTelemetrySnapshot();
}

@interface PerfHUDManager : NSObject
+ (void)start;
+ (void)applySettings;
+ (void)updateOrientation:(UIInterfaceOrientation)orientation;
+ (void)displayTick:(CADisplayLink *)link;
+ (void)timerTick:(NSTimer *)timer;
@end

@implementation PerfHUDManager

+ (void)displayTick:(CADisplayLink *)link {
    OnDisplayLinkTick(link);
}

+ (void)timerTick:(NSTimer *)timer {
    OnTimerTick(timer);
}

+ (void)updateOrientation:(UIInterfaceOrientation)orientation {
    if (s_hudWindow) {
        [s_hudWindow updatePosition:s_position withOrientation:orientation];
    }
}

+ (void)applySettings {
    LoadSettings();
    if (!s_hudWindow) {
        s_hudWindow = [[PerfHUDWindow alloc] init];
    }
    [s_hudWindow updatePosition:s_position withOrientation:GetCurrentActiveOrientation()];
    s_hudWindow.hudView.isWireframe = s_isWireframe;
    s_hudWindow.hidden = !s_enabled;
}

static void OnPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [PerfHUDManager applySettings];
}

+ (void)start {
    [self applySettings];

    if (!s_displayLink) {
        s_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayTick:)];
        [s_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }

    if (s_updateTimer) {
        [s_updateTimer invalidate];
        s_updateTimer = nil;
    }

    s_updateTimer = [NSTimer scheduledTimerWithTimeInterval:s_refreshInterval
                                                     target:self
                                                   selector:@selector(timerTick:)
                                                   userInfo:nil
                                                    repeats:YES];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    OnPreferencesChanged,
                                    CFSTR("com.noname122021.perfhud/settingschanged"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);
}

@end

// Hook SBUIController & SpringBoard for orientation tracking
%hook SBUIController

- (void)window:(id)window willRotateToInterfaceOrientation:(UIInterfaceOrientation)toOrientation duration:(NSTimeInterval)duration {
    %orig;
    [PerfHUDManager updateOrientation:toOrientation];
}

- (void)window:(id)window didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromOrientation {
    %orig;
    [PerfHUDManager updateOrientation:GetCurrentActiveOrientation()];
}

%end

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    [PerfHUDManager start];
}

- (void)frontDisplayDidChange:(id)newDisplay {
    %orig;
    [PerfHUDManager updateOrientation:GetCurrentActiveOrientation()];
}

%end
