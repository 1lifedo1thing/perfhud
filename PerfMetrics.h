#ifndef PERFHUD_METRICS_H
#define PERFHUD_METRICS_H

#include <stdint.h>
#include <stdbool.h>

#define PERFHUD_HISTORY_LEN 30
#define MAX_CORES 4

typedef struct {
    float history[PERFHUD_HISTORY_LEN];
    uint8_t head;
    float current;
    float min_val;
    float max_val;
} PerfMetricHistory;

typedef struct {
    PerfMetricHistory fps;
    PerfMetricHistory cpu_total;
    PerfMetricHistory cpu_cores[MAX_CORES];
    PerfMetricHistory ram_free;
    PerfMetricHistory net_down;
    PerfMetricHistory disk_write;
    
    uint32_t cpu_count;

    // RAM details
    float ram_total_mb;
    float ram_free_mb;
    float ram_active_mb;
    float ram_inactive_mb;
    float ram_wired_mb;

    // Network speeds (KB/s)
    float net_down_kb;
    float net_up_kb;

    // Disk / Storage (/private/var)
    float disk_avail_mb;
    float disk_avail_gb;
    float disk_total_gb;
    float disk_used_pct;
    float disk_read_kb;  // Real NAND read speed in KB/s
    float disk_write_kb; // Real NAND write speed in KB/s
} PerfMetricsSnapshot;

typedef struct {
    bool calc_cpu;
    bool calc_ram;
    bool calc_net;
    bool calc_disk_space;
    bool calc_disk_io;
} PerfMetricsOptions;

#ifdef __cplusplus
extern "C" {
#endif

void PerfMetrics_Init(void);
void PerfMetrics_UpdateWithOptions(PerfMetricsSnapshot *snapshot, float current_fps, const PerfMetricsOptions *opts);
void PerfMetrics_Update(PerfMetricsSnapshot *snapshot, float current_fps);
void PerfMetrics_PushHistory(PerfMetricHistory *metric, float val);
void PerfMetrics_PushHistory(PerfMetricHistory *metric, float val);

#ifdef __cplusplus
}
#endif

#endif
