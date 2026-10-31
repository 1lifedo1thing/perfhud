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
    
    uint32_t cpu_count;

    // RAM details
    float ram_total_mb;
    float ram_free_mb;
    float ram_active_mb;
    float ram_inactive_mb;
    float ram_wired_mb;
} PerfMetricsSnapshot;

#ifdef __cplusplus
extern "C" {
#endif

void PerfMetrics_Init(void);
void PerfMetrics_Update(PerfMetricsSnapshot *snapshot, float current_fps);
void PerfMetrics_PushHistory(PerfMetricHistory *metric, float val);

#ifdef __cplusplus
}
#endif

#endif
