#import "PerfHUDView.h"
#import <QuartzCore/QuartzCore.h>

@implementation PerfHUDView

@synthesize isWireframe = _isWireframe;
@synthesize showFps = _showFps;
@synthesize showCpu = _showCpu;
@synthesize showRam = _showRam;
@synthesize showNet = _showNet;
@synthesize showDiskSpace = _showDiskSpace;
@synthesize showDiskIo = _showDiskIo;

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

        _showFps = YES;
        _showCpu = YES;
        _showRam = YES;
        _showNet = YES;
        _showDiskSpace = YES;
        _showDiskIo = YES;

        _monoFont = [[UIFont fontWithName:@"Courier-Bold" size:9.0f] retain];
        _smallFont = [[UIFont fontWithName:@"Courier-Bold" size:8.0f] retain];
    }
    return self;
}

- (CGFloat)calculateContentHeight {
    CGFloat h = 8.0f; // top + bottom padding
    CGFloat row_h = 13.0f;

    if (_showFps) {
        h += row_h;
    }
    if (_showCpu) {
        h += row_h; // CPU total
        if (_snapshot.cpu_count > 1) {
            h += (row_h * (_snapshot.cpu_count > 2 ? 2 : _snapshot.cpu_count));
        }
    }
    if (_showRam) {
        h += (row_h + 3.0f); // Free RAM + sparkline
        h += row_h;          // Total RAM text
        h += 10.0f;          // W/A/I/F details
        h += (6.0f + 3.0f);  // Bar + spacing
    }
    if (_showNet) {
        h += row_h;          // Net down/up text + sparkline
    }
    if (_showDiskIo) {
        h += row_h;          // Disk R/W I/O speeds (KB/s) + write sparkline
    }
    if (_showDiskSpace) {
        h += 11.0f;          // Disk capacity text (MB)
        h += (3.0f + 2.0f);  // Disk bar
    }

    if (h < 26.0f) h = 26.0f; // min height
    return h;
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
    float row_h = 13.0f;

    // 1. FPS Row
    if (_showFps) {
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
    }

    // 2. CPU Rows
    if (_showCpu) {
        UIColor *cpuColor = ColorForPercentage(_snapshot.cpu_total.current);
        NSString *cpuText = [NSString stringWithFormat:@"CPU:%3.0f%%", _snapshot.cpu_total.current];
        [cpuColor setFill];
        [cpuText drawAtPoint:CGPointMake(pad_x, cur_y) withFont:_monoFont];

        CGRect cpuGraphRect = CGRectMake(rect.size.width - pad_x - graph_w, cur_y + 2.0f, graph_w, 9.0f);
        DrawSparkline(ctx, cpuGraphRect, &_snapshot.cpu_total, cpuColor, 0.0f, 100.0f);
        cur_y += row_h;

        // Per-Core Rows (only if > 1 core exists)
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
    }

    // 3. RAM Rows
    if (_showRam) {
        UIColor *ramColor = [UIColor colorWithRed:0.95f green:0.6f blue:0.2f alpha:1.0f];
        float avail_mb = _snapshot.ram_free_mb + _snapshot.ram_inactive_mb;
        NSString *ramText = [NSString stringWithFormat:@"RAM:%6.2fM", avail_mb];
        [ramColor setFill];
        [ramText drawAtPoint:CGPointMake(pad_x, cur_y) withFont:_monoFont];

        CGRect ramGraphRect = CGRectMake(rect.size.width - pad_x - graph_w, cur_y + 1.0f, graph_w, 15.0f);
        float ram_min = _snapshot.ram_free.min_val - 2.0f;
        float ram_max = _snapshot.ram_free.max_val + 2.0f;
        if (ram_min < 0.0f) ram_min = 0.0f;
        if (ram_max <= ram_min) ram_max = ram_min + 10.0f;
        DrawSparkline(ctx, ramGraphRect, &_snapshot.ram_free, ramColor, ram_min, ram_max);
        cur_y += (row_h + 3.0f);

        UIColor *totalColor = [UIColor colorWithWhite:0.75f alpha:1.0f];
        [totalColor setFill];
        NSString *totalText = [NSString stringWithFormat:@"Total RAM:%5.1fM", _snapshot.ram_total_mb];
        [totalText drawAtPoint:CGPointMake(pad_x, cur_y) withFont:_monoFont];
        cur_y += row_h;

        NSString *ramDetail = [NSString stringWithFormat:@"W:%.0f A:%.0f I:%.0f F:%.0f",
                               _snapshot.ram_wired_mb,
                               _snapshot.ram_active_mb,
                               _snapshot.ram_inactive_mb,
                               _snapshot.ram_free_mb];
        [[UIColor colorWithWhite:0.6f alpha:1.0f] setFill];
        [ramDetail drawAtPoint:CGPointMake(pad_x, cur_y) withFont:_smallFont];
        cur_y += 10.0f;

        float bar_y = cur_y;
        float bar_h = 6.0f;
        CGRect barBg = CGRectMake(pad_x, bar_y, w, bar_h);
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.25f alpha:1.0f].CGColor);
        CGContextFillRect(ctx, barBg);

        float accounted_mb = _snapshot.ram_wired_mb + _snapshot.ram_active_mb + _snapshot.ram_inactive_mb + _snapshot.ram_free_mb;
        if (accounted_mb > 0.0f) {
            float px_per_mb = w / accounted_mb;
            float cur_x = pad_x;

            float wired_w = _snapshot.ram_wired_mb * px_per_mb;
            CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:0.95f green:0.25f blue:0.25f alpha:0.95f].CGColor);
            CGContextFillRect(ctx, CGRectMake(cur_x, bar_y, wired_w, bar_h));
            cur_x += wired_w;

            float active_w = _snapshot.ram_active_mb * px_per_mb;
            CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:0.95f green:0.8f blue:0.2f alpha:0.95f].CGColor);
            CGContextFillRect(ctx, CGRectMake(cur_x, bar_y, active_w, bar_h));
            cur_x += active_w;

            float inactive_w = _snapshot.ram_inactive_mb * px_per_mb;
            CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:0.2f green:0.75f blue:0.95f alpha:0.95f].CGColor);
            CGContextFillRect(ctx, CGRectMake(cur_x, bar_y, inactive_w, bar_h));
        }
        cur_y += (bar_h + 3.0f);
    }

    // 4. Network Row (Down/Up KB/s + Sparkline)
    if (_showNet) {
        UIColor *netColor = [UIColor colorWithRed:0.3f green:0.85f blue:0.65f alpha:1.0f];
        [netColor setFill];
        NSString *dStr = (_snapshot.net_down_kb >= 1000.0f) ?
            [NSString stringWithFormat:@"%4.1fM", _snapshot.net_down_kb / 1024.0f] :
            [NSString stringWithFormat:@"%3.0fK", _snapshot.net_down_kb];
        NSString *uStr = (_snapshot.net_up_kb >= 1000.0f) ?
            [NSString stringWithFormat:@"%4.1fM", _snapshot.net_up_kb / 1024.0f] :
            [NSString stringWithFormat:@"%3.0fK", _snapshot.net_up_kb];

        NSString *netText = [NSString stringWithFormat:@"D:%@ U:%@", dStr, uStr];
        [netText drawAtPoint:CGPointMake(pad_x, cur_y) withFont:_monoFont];

        CGRect netGraphRect = CGRectMake(rect.size.width - pad_x - graph_w, cur_y + 2.0f, graph_w, 9.0f);
        float net_max = _snapshot.net_down.max_val;
        if (net_max < 20.0f) net_max = 20.0f;
        DrawSparkline(ctx, netGraphRect, &_snapshot.net_down, netColor, 0.0f, net_max);
        cur_y += row_h;
    }

    // 5. Disk I/O Read/Write Speeds (KB/s or MB/s + Sparkline)
    if (_showDiskIo) {
        UIColor *diskIoColor = [UIColor colorWithRed:0.85f green:0.55f blue:0.95f alpha:1.0f];
        [diskIoColor setFill];
        NSString *rStr = (_snapshot.disk_read_kb >= 1000.0f) ?
            [NSString stringWithFormat:@"%4.1fM", _snapshot.disk_read_kb / 1024.0f] :
            [NSString stringWithFormat:@"%3.0fK", _snapshot.disk_read_kb];
        NSString *wStr = (_snapshot.disk_write_kb >= 1000.0f) ?
            [NSString stringWithFormat:@"%4.1fM", _snapshot.disk_write_kb / 1024.0f] :
            [NSString stringWithFormat:@"%3.0fK", _snapshot.disk_write_kb];

        NSString *ioText = [NSString stringWithFormat:@"R:%@ W:%@", rStr, wStr];
        [ioText drawAtPoint:CGPointMake(pad_x, cur_y) withFont:_monoFont];

        CGRect diskGraphRect = CGRectMake(rect.size.width - pad_x - graph_w, cur_y + 2.0f, graph_w, 9.0f);
        float disk_max = _snapshot.disk_write.max_val;
        if (disk_max < 50.0f) disk_max = 50.0f;
        DrawSparkline(ctx, diskGraphRect, &_snapshot.disk_write, diskIoColor, 0.0f, disk_max);
        cur_y += row_h;
    }

    // 6. Disk Storage Capacity (Megabytes on left, Percentage pinned to right edge)
    if (_showDiskSpace) {
        UIColor *diskColor = [UIColor colorWithRed:0.75f green:0.65f blue:0.95f alpha:1.0f];
        [diskColor setFill];

        NSString *diskLeftText = [NSString stringWithFormat:@"Disk:%.2fM", _snapshot.disk_avail_mb];
        [diskLeftText drawAtPoint:CGPointMake(pad_x, cur_y) withFont:_monoFont];

        NSString *pctText = [NSString stringWithFormat:@"%2.0f%%", _snapshot.disk_used_pct];
        CGSize pctSize = [pctText sizeWithFont:_monoFont];
        [pctText drawAtPoint:CGPointMake(rect.size.width - pad_x - pctSize.width, cur_y) withFont:_monoFont];
        cur_y += 11.0f;

        float d_bar_y = cur_y;
        float d_bar_h = 3.0f;
        CGRect d_barBg = CGRectMake(pad_x, d_bar_y, w, d_bar_h);
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.25f alpha:1.0f].CGColor);
        CGContextFillRect(ctx, d_barBg);

        float used_pct = _snapshot.disk_used_pct / 100.0f;
        if (used_pct > 1.0f) used_pct = 1.0f;
        if (used_pct > 0.0f) {
            UIColor *barCol = (used_pct >= 0.9f) ? [UIColor colorWithRed:0.95f green:0.25f blue:0.25f alpha:1.0f] :
                              (used_pct >= 0.75f) ? [UIColor colorWithRed:0.95f green:0.8f blue:0.2f alpha:1.0f] :
                              [UIColor colorWithRed:0.5f green:0.65f blue:0.95f alpha:1.0f];
            CGContextSetFillColorWithColor(ctx, barCol.CGColor);
            CGContextFillRect(ctx, CGRectMake(pad_x, d_bar_y, w * used_pct, d_bar_h));
        }
        cur_y += (d_bar_h + 2.0f);
    }
}

- (void)dealloc {
    [_monoFont release];
    _monoFont = nil;
    [_smallFont release];
    _smallFont = nil;
    [super dealloc];
}

@end
