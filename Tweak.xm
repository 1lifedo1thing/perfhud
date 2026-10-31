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
static BOOL s_onlyFps = NO;
static NSInteger s_position = 0;
static BOOL s_isWireframe = NO;
static NSInteger s_tapBehavior = 2; // 0: Corner Jump, 1: Pip / Peek Hide, 2: Pass-Through Gaming (Default: 2)
static BOOL s_showFps = YES;
static BOOL s_showCpu = YES;
static BOOL s_showRam = YES;
static BOOL s_showNet = YES;
static BOOL s_showDiskSpace = YES;
static BOOL s_showDiskIo = YES;
static BOOL s_monitorWhenScreenOff = NO;
static double s_refreshInterval = 0.5;

static void LoadSettings(void) {
    CFPreferencesAppSynchronize(CFSTR("com.noname122021.perfhud"));
    Boolean valid = false;

    Boolean bEnabled = CFPreferencesGetAppBooleanValue(CFSTR("enabled"), CFSTR("com.noname122021.perfhud"), &valid);
    s_enabled = valid ? (BOOL)bEnabled : YES;

    Boolean bOnlyFps = CFPreferencesGetAppBooleanValue(CFSTR("onlyFps"), CFSTR("com.noname122021.perfhud"), &valid);
    s_onlyFps = valid ? (BOOL)bOnlyFps : NO;

    CFIndex pos = CFPreferencesGetAppIntegerValue(CFSTR("position"), CFSTR("com.noname122021.perfhud"), &valid);
    s_position = valid ? (NSInteger)pos : 0;

    Boolean bWire = CFPreferencesGetAppBooleanValue(CFSTR("wireframe"), CFSTR("com.noname122021.perfhud"), &valid);
    s_isWireframe = valid ? (BOOL)bWire : NO;

    CFIndex tapAct = CFPreferencesGetAppIntegerValue(CFSTR("tapBehavior"), CFSTR("com.noname122021.perfhud"), &valid);
    s_tapBehavior = valid ? (NSInteger)tapAct : 2; // Default: 2 (Pass-Through)

    Boolean bFps = CFPreferencesGetAppBooleanValue(CFSTR("showFps"), CFSTR("com.noname122021.perfhud"), &valid);
    s_showFps = valid ? (BOOL)bFps : YES;

    Boolean bCpu = CFPreferencesGetAppBooleanValue(CFSTR("showCpu"), CFSTR("com.noname122021.perfhud"), &valid);
    s_showCpu = valid ? (BOOL)bCpu : YES;

    Boolean bRam = CFPreferencesGetAppBooleanValue(CFSTR("showRam"), CFSTR("com.noname122021.perfhud"), &valid);
    s_showRam = valid ? (BOOL)bRam : YES;

    Boolean bNet = CFPreferencesGetAppBooleanValue(CFSTR("showNet"), CFSTR("com.noname122021.perfhud"), &valid);
    s_showNet = valid ? (BOOL)bNet : YES;

    Boolean bDiskSpace = CFPreferencesGetAppBooleanValue(CFSTR("showDiskSpace"), CFSTR("com.noname122021.perfhud"), &valid);
    s_showDiskSpace = valid ? (BOOL)bDiskSpace : YES;

    Boolean bDiskIo = CFPreferencesGetAppBooleanValue(CFSTR("showDiskIo"), CFSTR("com.noname122021.perfhud"), &valid);
    s_showDiskIo = valid ? (BOOL)bDiskIo : YES;

    Boolean bScreenOff = CFPreferencesGetAppBooleanValue(CFSTR("monitorWhenScreenOff"), CFSTR("com.noname122021.perfhud"), &valid);
    s_monitorWhenScreenOff = valid ? (BOOL)bScreenOff : NO;
}

@interface UIApplication (SpringBoardOrientation)
- (UIInterfaceOrientation)activeInterfaceOrientation;
@end

static UIInterfaceOrientation GetCurrentActiveOrientation(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(activeInterfaceOrientation)]) {
        UIInterfaceOrientation o = [app activeInterfaceOrientation];
        if (o >= UIInterfaceOrientationPortrait && o <= UIInterfaceOrientationLandscapeLeft) {
            return o;
        }
    }
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
        fprintf(f, "[%s] FPS:%4.1f CPU:%3.0f%% (C0:%2.0f%% C1:%2.0f%%) RAM:%.2fM/%.1fM (W:%.0f A:%.0f I:%.0f F:%.0f) NET:D:%.1fK/U:%.1fK DISK:%.0fM(%.0f%%) IO:R:%.1fK/W:%.1fK\n",
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
                s_snapshot.ram_free_mb,
                s_snapshot.net_down_kb,
                s_snapshot.net_up_kb,
                s_snapshot.disk_avail_mb,
                s_snapshot.disk_used_pct,
                s_snapshot.disk_read_kb,
                s_snapshot.disk_write_kb);
        fclose(f);
    }
}

static float ReadGameFpsIfActive(void) {
    FILE *f = fopen("/var/tmp/perfhud_game_fps", "r");
    if (!f) return -1.0f;

    float fps = -1.0f;
    unsigned long ts = 0;
    if (fscanf(f, "%f %lu", &fps, &ts) == 2) {
        fclose(f);
        time_t now = time(NULL);
        // If written within last 2 seconds, game is actively rendering
        if (now >= (time_t)ts && (now - (time_t)ts) <= 2) {
            return fps;
        }
    } else {
        fclose(f);
    }
    return -1.0f;
}

static void OnTimerTick(NSTimer *timer) {
    if (!s_enabled || !s_hudWindow) return;

    // Check active orientation every tick as a fail-safe (covers non-standard apps/games)
    UIInterfaceOrientation activeOrient = GetCurrentActiveOrientation();
    if (activeOrient != s_hudWindow.currentOrientation) {
        [s_hudWindow updatePosition:s_position withOrientation:activeOrient];
    }

    PerfMetricsOptions opts = {
        .calc_cpu = (!s_onlyFps && s_showCpu),
        .calc_ram = (!s_onlyFps && s_showRam),
        .calc_net = (!s_onlyFps && s_showNet),
        .calc_disk_space = (!s_onlyFps && s_showDiskSpace),
        .calc_disk_io = (!s_onlyFps && s_showDiskIo)
    };

    float displayFps = s_calculatedFps;
    float gameFps = ReadGameFpsIfActive();
    if (gameFps >= 0.0f) {
        displayFps = gameFps;
    }

    PerfMetrics_UpdateWithOptions(&s_snapshot, displayFps, &opts);
    [s_hudWindow.hudView updateWithSnapshot:&s_snapshot];
    [s_hudWindow recalculateLayout];
    ExportTelemetrySnapshot();
}

@interface PerfHUDManager : NSObject
+ (void)start;
+ (void)applySettings;
+ (void)updateOrientation:(UIInterfaceOrientation)orientation;
+ (void)screenDimmed;
+ (void)screenUndimmed;
+ (void)displayTick:(CADisplayLink *)link;
+ (void)timerTick:(NSTimer *)timer;
@end

@implementation PerfHUDManager

+ (void)screenDimmed {
    if (!s_enabled) return;
    if (s_hudWindow) {
        s_hudWindow.hidden = YES;
    }
    if (!s_monitorWhenScreenOff) {
        StopMonitoring();
    }
}

+ (void)screenUndimmed {
    if (!s_enabled) return;
    if (s_hudWindow) {
        s_hudWindow.hidden = NO;
        [s_hudWindow updatePosition:s_position withOrientation:GetCurrentActiveOrientation()];
    }
    if (!s_monitorWhenScreenOff) {
        StartMonitoring(self);
    }
}

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

static void StopMonitoring(void) {
    if (s_displayLink) {
        [s_displayLink invalidate];
        s_displayLink = nil;
    }
    if (s_updateTimer) {
        [s_updateTimer invalidate];
        s_updateTimer = nil;
    }
    s_frameCount = 0;
    s_lastFpsTimestamp = 0;
    // Remove stale telemetry file when disabled
    unlink("/var/tmp/perfhud.stat");
}

static void StartMonitoring(id target) {
    if (!s_displayLink) {
        s_displayLink = [CADisplayLink displayLinkWithTarget:target selector:@selector(displayTick:)];
        [s_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    if (s_updateTimer) {
        [s_updateTimer invalidate];
        s_updateTimer = nil;
    }
    s_updateTimer = [NSTimer scheduledTimerWithTimeInterval:s_refreshInterval
                                                     target:target
                                                   selector:@selector(timerTick:)
                                                   userInfo:nil
                                                    repeats:YES];
}

+ (void)applySettings {
    LoadSettings();
    if (!s_enabled) {
        if (s_hudWindow) {
            s_hudWindow.hidden = YES;
        }
        StopMonitoring();
        return;
    }

    if (!s_hudWindow) {
        s_hudWindow = [[PerfHUDWindow alloc] init];
    }
    s_hudWindow.tapBehavior = s_tapBehavior;
    s_hudWindow.hudView.onlyFps = s_onlyFps;
    s_hudWindow.hudView.isWireframe = s_isWireframe;
    s_hudWindow.hudView.showFps = s_showFps;
    s_hudWindow.hudView.showCpu = s_showCpu;
    s_hudWindow.hudView.showRam = s_showRam;
    s_hudWindow.hudView.showNet = s_showNet;
    s_hudWindow.hudView.showDiskSpace = s_showDiskSpace;
    s_hudWindow.hudView.showDiskIo = s_showDiskIo;

    [s_hudWindow updatePosition:s_position withOrientation:GetCurrentActiveOrientation()];
    s_hudWindow.hidden = NO;

    StartMonitoring(self);
}

static void OnPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [PerfHUDManager applySettings];
}

+ (void)start {
    [self applySettings];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    OnPreferencesChanged,
                                    CFSTR("com.noname122021.perfhud/settingschanged"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);
}

@end

%group SpringBoardHooks

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

- (void)noteInterfaceOrientationChanged:(UIInterfaceOrientation)orientation duration:(NSTimeInterval)duration updateMirroredDisplays:(BOOL)update force:(BOOL)force {
    %orig;
    [PerfHUDManager updateOrientation:orientation];
}

- (void)activeInterfaceOrientationDidChangeToOrientation:(UIInterfaceOrientation)toOrientation willAnimateWithDuration:(NSTimeInterval)duration fromOrientation:(UIInterfaceOrientation)fromOrientation {
    %orig;
    [PerfHUDManager updateOrientation:toOrientation];
}

%end

%hook SBAwayController

- (void)dimScreen:(BOOL)dimmed {
    %orig;
    [PerfHUDManager screenDimmed];
}

- (void)undimScreen:(BOOL)undimmed {
    %orig;
    [PerfHUDManager screenUndimmed];
}

%end

%end // SpringBoardHooks

%group GameHooks

// Game / App OpenGL ES Frame Interposer
static NSUInteger s_appFrameCount = 0;
static CFTimeInterval s_appLastTimestamp = 0;
static BOOL s_gameHookEnabled = YES;

%hook EAGLContext

- (BOOL)presentRenderbuffer:(NSUInteger)target {
    if (s_gameHookEnabled) {
        s_appFrameCount++;
        CFTimeInterval now = CACurrentMediaTime();
        if (s_appLastTimestamp == 0) {
            s_appLastTimestamp = now;
        } else {
            CFTimeInterval delta = now - s_appLastTimestamp;
            if (delta >= 0.5) {
                float fps = (float)((double)s_appFrameCount / delta);
                if (fps > 60.0f) fps = 60.0f;
                s_appFrameCount = 0;
                s_appLastTimestamp = now;

                // Atomic write to RAM disk
                FILE *f = fopen("/var/tmp/perfhud_game_fps", "w");
                if (f) {
                    fprintf(f, "%.1f %lu\n", fps, (unsigned long)time(NULL));
                    fclose(f);
                }
            }
        }
    }
    return %orig;
}

%end

%end // GameHooks

static void OnGameSettingsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    CFPreferencesAppSynchronize(CFSTR("com.noname122021.perfhud"));
    Boolean valid = false;
    Boolean bEnabled = CFPreferencesGetAppBooleanValue(CFSTR("enabled"), CFSTR("com.noname122021.perfhud"), &valid);
    s_gameHookEnabled = valid ? (BOOL)bEnabled : YES;
    if (!s_gameHookEnabled) {
        unlink("/var/tmp/perfhud_game_fps");
    }
}

%ctor {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    if ([bundleId isEqualToString:@"com.apple.springboard"]) {
        // Initialize SpringBoard HUD
        %init(SpringBoardHooks);
    } else {
        // We are inside a game or third-party app
        CFPreferencesAppSynchronize(CFSTR("com.noname122021.perfhud"));
        Boolean valid = false;
        Boolean bEnabled = CFPreferencesGetAppBooleanValue(CFSTR("enabled"), CFSTR("com.noname122021.perfhud"), &valid);
        s_gameHookEnabled = valid ? (BOOL)bEnabled : YES;

        // If tweak is disabled in Settings, do not hook anything in games!
        if (s_gameHookEnabled) {
            %init(GameHooks);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            NULL,
                                            OnGameSettingsChanged,
                                            CFSTR("com.noname122021.perfhud/settingschanged"),
                                            NULL,
                                            CFNotificationSuspensionBehaviorCoalesce);
        }
    }
}
