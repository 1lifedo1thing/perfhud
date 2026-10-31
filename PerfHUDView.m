#import "PerfHUDView.h"
#import <QuartzCore/QuartzCore.h>

@implementation PerfHUDView

@synthesize isWireframe = _isWireframe;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = YES;
        self.backgroundColor = [UIColor colorWithWhite:0.08f alpha:1.0f];
        self.userInteractionEnabled = NO;
        self.layer.borderColor = [UIColor colorWithWhite:0.35f alpha:1.0f].CGColor;
        self.layer.borderWidth = 1.0f;
        self.layer.cornerRadius = 4.0f;
        self.layer.masksToBounds = YES;

        _monoFont = [[UIFont fontWithName:@"Courier-Bold" size:9.0f] retain];
    }
    return self;
}

- (void)setIsWireframe:(BOOL)isWireframe {
    _isWireframe = isWireframe;
    if (isWireframe) {
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.layer.borderWidth = 1.0f;
        self.layer.borderColor = [UIColor colorWithWhite:0.75f alpha:0.85f].CGColor;
    } else {
        self.opaque = YES;
        self.backgroundColor = [UIColor colorWithWhite:0.08f alpha:1.0f];
        self.layer.borderWidth = 1.0f;
        self.layer.borderColor = [UIColor colorWithWhite:0.35f alpha:1.0f].CGColor;
    }
    [self setNeedsDisplay];
}

- (void)updateWithSnapshot:(const PerfMetricsSnapshot *)snapshot {
    _snapshot = *snapshot;
    [self setNeedsDisplay];
}

static UIColor *ColorForPercentage(float pct) {
    if (pct >= 85.0f) {
        return [UIColor colorWithRed:0.95f green:0.25f blue:0.25f alpha:1.0f];
    } else if (pct >= 65.0f) {
        return [UIColor colorWithRed:0.95f green:0.8f blue:0.15f alpha:1.0f];
    } else {
        return [UIColor colorWithRed:0.4f green:0.75f blue:1.0f alpha:1.0f];
    }
}

static void DrawSparkline(CGContextRef ctx, CGRect rect, const PerfMetricHistory *metric, UIColor *color, float fixed_min, float fixed_max) {
    if (rect.size.width <= 0 || rect.size.height <= 0) return;

    CGContextSaveGState(ctx);
    CGContextSetStrokeColorWithColor(ctx, color.CGColor);
    CGContextSetLineWidth(ctx, 1.0f);

    float range = fixed_max - fixed_min;
    if (range <= 0.001f) range = 1.0f;

    float step_x = rect.size.width / (float)(PERFHUD_HISTORY_LEN - 1);
    BOOL started = NO;

    for (int i = 0; i < PERFHUD_HISTORY_LEN; i++) {
        int idx = (metric->head + i) % PERFHUD_HISTORY_LEN;
        float val = metric->history[idx];

        if (val < fixed_min) val = fixed_min;
        if (val > fixed_max) val = fixed_max;

        float norm = (val - fixed_min) / range;
        float x = rect.origin.x + (i * step_x);
        float y = rect.origin.y + rect.size.height - (norm * rect.size.height);

        if (!started) {
            CGContextMoveToPoint(ctx, x, y);
            started = YES;
        } else {
            CGContextAddLineToPoint(ctx, x, y);
        }
    }

    CGContextStrokePath(ctx);
    CGContextRestoreGState(ctx);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    if (_isWireframe) {
        CGContextClearRect(ctx, rect);
    }

    float pad_x = 5.0f;
    float w = rect.size.width - (pad_x * 2.0f);
    float graph_w = 44.0f;
    float cur_y = 4.0f;
    float row_h = 14.0f;

    // 1. FPS Row
    UIColor *fpsColor;
    if (_snapshot.fps.current >= 55.0f) {
        fpsColor = [UIColor colorWithRed:0.2f green:0.9f blue:0.2f alpha:1.0f];
    } else if (_snapshot.fps.current >= 35.0f) {
        fpsColor = [UIColor colorWithRed:0.95f green:0.8f blue:0.1f alpha:1.0f];
    } else {
        fpsColor = [UIColor colorWithRed:0.95f green:0.2f blue:0.2f alpha:1.0f];
    }

    NSString *fpsText = [NSString stringWithFormat:@"FPS:%4.1f", _snapshot.fps.current];
    [fpsColor setFill];
    [fpsText drawAtPoint:CGPointMake(pad_x, cur_y) withFont:_monoFont];

    CGRect fpsGraphRect = CGRectMake(rect.size.width - pad_x - graph_w, cur_y + 2.0f, graph_w, 9.0f);
    DrawSparkline(ctx, fpsGraphRect, &_snapshot.fps, fpsColor, 0.0f, 60.0f);
    cur_y += row_h;

    // 2. CPU Total Row
    UIColor *cpuColor = ColorForPercentage(_snapshot.cpu_total.current);
    NSString *cpuText = [NSString stringWithFormat:@"CPU:%3.0f%%", _snapshot.cpu_total.current];
    [cpuColor setFill];
    [cpuText drawAtPoint:CGPointMake(pad_x, cur_y) withFont:_monoFont];

    CGRect cpuGraphRect = CGRectMake(rect.size.width - pad_x - graph_w, cur_y + 2.0f, graph_w, 9.0f);
    DrawSparkline(ctx, cpuGraphRect, &_snapshot.cpu_total, cpuColor, 0.0f, 100.0f);
    cur_y += row_h;

    // 3. Per-Core Rows
    if (_snapshot.cpu_count > 1) {
        for (uint32_t c = 0; c < _snapshot.cpu_count && c < 2; c++) {
            float corePct = _snapshot.cpu_cores[c].current;
            UIColor *coreColor = ColorForPercentage(corePct);

            NSString *coreText = [NSString stringWithFormat:@" C%u:%3.0f%%", c, corePct];
            [coreColor setFill];
            [coreText drawAtPoint:CGPointMake(pad_x, cur_y) withFont:_monoFont];

            CGRect coreGraphRect = CGRectMake(rect.size.width - pad_x - graph_w, cur_y + 2.0f, graph_w, 9.0f);
            DrawSparkline(ctx, coreGraphRect, &_snapshot.cpu_cores[c], coreColor, 0.0f, 100.0f);
            cur_y += row_h;
        }
    }

    // 4. Free RAM Row with 2 decimals! (e.g. "RAM:240.35M")
    UIColor *ramColor = [UIColor colorWithRed:0.95f green:0.6f blue:0.2f alpha:1.0f];
    float avail_mb = _snapshot.ram_free_mb + _snapshot.ram_inactive_mb;
    NSString *ramText = [NSString stringWithFormat:@"RAM:%6.2fM", avail_mb];
    [ramColor setFill];
    [ramText drawAtPoint:CGPointMake(pad_x, cur_y) withFont:_monoFont];

    // TALL RAM GRAPH (Height 16.0f with dynamic auto-scaling zoom!)
    CGRect ramGraphRect = CGRectMake(rect.size.width - pad_x - graph_w, cur_y + 1.0f, graph_w, 16.0f);
    float ram_min = _snapshot.ram_free.min_val - 2.0f;
    float ram_max = _snapshot.ram_free.max_val + 2.0f;
    if (ram_min < 0.0f) ram_min = 0.0f;
    if (ram_max <= ram_min) ram_max = ram_min + 10.0f;
    DrawSparkline(ctx, ramGraphRect, &_snapshot.ram_free, ramColor, ram_min, ram_max);
    cur_y += (row_h + 3.0f);

    // 5. Total RAM Row
    UIColor *totalColor = [UIColor colorWithWhite:0.75f alpha:1.0f];
    [totalColor setFill];
    NSString *totalText = [NSString stringWithFormat:@"Total RAM:%5.1fM", _snapshot.ram_total_mb];
    [totalText drawAtPoint:CGPointMake(pad_x, cur_y) withFont:_monoFont];
    cur_y += row_h;

    // 6. Memory Breakdown Legend with exact values
    NSString *ramDetail = [NSString stringWithFormat:@"W:%.0f A:%.0f I:%.0f F:%.0f",
                           _snapshot.ram_wired_mb,
                           _snapshot.ram_active_mb,
                           _snapshot.ram_inactive_mb,
                           _snapshot.ram_free_mb];
    UIFont *smallFont = [UIFont fontWithName:@"Courier-Bold" size:8.0f];
    [[UIColor colorWithWhite:0.6f alpha:1.0f] setFill];
    [ramDetail drawAtPoint:CGPointMake(pad_x, cur_y) withFont:smallFont];
    cur_y += 10.0f;

    // 7. Tall Memory Bar (Height 6.0f)
    float bar_y = cur_y;
    float bar_h = 6.0f;
    CGRect barBg = CGRectMake(pad_x, bar_y, w, bar_h);
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.25f alpha:1.0f].CGColor);
    CGContextFillRect(ctx, barBg);

    float accounted_mb = _snapshot.ram_wired_mb + _snapshot.ram_active_mb + _snapshot.ram_inactive_mb + _snapshot.ram_free_mb;
    if (accounted_mb > 0.0f) {
        float px_per_mb = w / accounted_mb;
        float cur_x = pad_x;

        // Wired (Red)
        float wired_w = _snapshot.ram_wired_mb * px_per_mb;
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:0.95f green:0.25f blue:0.25f alpha:0.95f].CGColor);
        CGContextFillRect(ctx, CGRectMake(cur_x, bar_y, wired_w, bar_h));
        cur_x += wired_w;

        // Active (Yellow)
        float active_w = _snapshot.ram_active_mb * px_per_mb;
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:0.95f green:0.8f blue:0.2f alpha:0.95f].CGColor);
        CGContextFillRect(ctx, CGRectMake(cur_x, bar_y, active_w, bar_h));
        cur_x += active_w;

        // Inactive (Cyan)
        float inactive_w = _snapshot.ram_inactive_mb * px_per_mb;
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:0.2f green:0.75f blue:0.95f alpha:0.95f].CGColor);
        CGContextFillRect(ctx, CGRectMake(cur_x, bar_y, inactive_w, bar_h));
    }
}

- (void)dealloc {
    [_monoFont release];
    _monoFont = nil;
    [super dealloc];
}

@end
