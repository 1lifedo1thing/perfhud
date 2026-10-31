#import "PerfMetrics.h"
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <mach/processor_info.h>
#import <sys/sysctl.h>

static unsigned long long s_last_cpu_total = 0;
static unsigned long long s_last_cpu_busy = 0;
static unsigned long long s_last_core_total[MAX_CORES] = {0};
static unsigned long long s_last_core_busy[MAX_CORES] = {0};
static uint64_t s_ram_total_bytes = 0;

void PerfMetrics_Init(void) {
    int mib[2] = { CTL_HW, HW_MEMSIZE };
    uint64_t mem = 0;
    size_t len = sizeof(mem);
    if (sysctl(mib, 2, &mem, &len, NULL, 0) == 0) {
        s_ram_total_bytes = mem;
    } else {
        s_ram_total_bytes = 512 * 1024 * 1024;
    }
}

void PerfMetrics_PushHistory(PerfMetricHistory *metric, float val) {
    metric->history[metric->head] = val;
    metric->head = (metric->head + 1) % PERFHUD_HISTORY_LEN;
    metric->current = val;

    float min_v = metric->history[0];
    float max_v = metric->history[0];
    for (int i = 1; i < PERFHUD_HISTORY_LEN; i++) {
        if (metric->history[i] < min_v) min_v = metric->history[i];
        if (metric->history[i] > max_v) max_v = metric->history[i];
    }
    metric->min_val = min_v;
    metric->max_val = max_v;
}

static void ReadCPU(PerfMetricsSnapshot *s) {
    natural_t cpu_count = 0;
    processor_info_array_t info_array;
    mach_msg_type_number_t info_count = 0;
    
    kern_return_t kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpu_count, &info_array, &info_count);
    if (kr != KERN_SUCCESS) {
        return;
    }

    s->cpu_count = cpu_count;
    processor_cpu_load_info_data_t *cpu_loads = (processor_cpu_load_info_data_t *)info_array;
    unsigned long long total_ticks_all = 0;
    unsigned long long busy_ticks_all = 0;

    for (natural_t i = 0; i < cpu_count; i++) {
        unsigned long long user = cpu_loads[i].cpu_ticks[CPU_STATE_USER];
        unsigned long long system = cpu_loads[i].cpu_ticks[CPU_STATE_SYSTEM];
        unsigned long long nice = cpu_loads[i].cpu_ticks[CPU_STATE_NICE];
        unsigned long long idle = cpu_loads[i].cpu_ticks[CPU_STATE_IDLE];

        unsigned long long core_busy = user + system + nice;
        unsigned long long core_total = core_busy + idle;

        busy_ticks_all += core_busy;
        total_ticks_all += core_total;

        if (i < MAX_CORES) {
            float core_usage = 0.0f;
            if (s_last_core_total[i] > 0 && core_total > s_last_core_total[i]) {
                core_usage = ((float)(core_busy - s_last_core_busy[i]) / (float)(core_total - s_last_core_total[i])) * 100.0f;
            }
            s_last_core_busy[i] = core_busy;
            s_last_core_total[i] = core_total;

            if (core_usage < 0.0f) core_usage = 0.0f;
            if (core_usage > 100.0f) core_usage = 100.0f;

            PerfMetrics_PushHistory(&s->cpu_cores[i], core_usage);
        }
    }

    vm_deallocate(mach_task_self(), (vm_address_t)info_array, info_count * sizeof(int));

    float overall_usage = 0.0f;
    if (s_last_cpu_total > 0 && total_ticks_all > s_last_cpu_total) {
        overall_usage = ((float)(busy_ticks_all - s_last_cpu_busy) / (float)(total_ticks_all - s_last_cpu_total)) * 100.0f;
    }
    s_last_cpu_total = total_ticks_all;
    s_last_cpu_busy = busy_ticks_all;

    if (overall_usage < 0.0f) overall_usage = 0.0f;
    if (overall_usage > 100.0f) overall_usage = 100.0f;
    PerfMetrics_PushHistory(&s->cpu_total, overall_usage);
}

static void ReadRAM(PerfMetricsSnapshot *s) {
    mach_port_t host = mach_host_self();
    vm_statistics_data_t vm_stat;
    mach_msg_type_number_t count = HOST_VM_INFO_COUNT;

    s->ram_total_mb = (float)s_ram_total_bytes / (1024.0f * 1024.0f);

    if (host_statistics(host, HOST_VM_INFO, (host_info_t)&vm_stat, &count) == KERN_SUCCESS) {
        float page_bytes = (float)vm_page_size;
        float mb_factor = page_bytes / (1024.0f * 1024.0f);

        s->ram_free_mb = (float)vm_stat.free_count * mb_factor;
        s->ram_active_mb = (float)vm_stat.active_count * mb_factor;
        s->ram_inactive_mb = (float)vm_stat.inactive_count * mb_factor;
        s->ram_wired_mb = (float)vm_stat.wire_count * mb_factor;
    }
}

void PerfMetrics_Update(PerfMetricsSnapshot *snapshot, float current_fps) {
    if (s_ram_total_bytes == 0) {
        PerfMetrics_Init();
    }

    PerfMetrics_PushHistory(&snapshot->fps, current_fps);
    ReadCPU(snapshot);
    ReadRAM(snapshot);

    float avail_ram = snapshot->ram_free_mb + snapshot->ram_inactive_mb;
    PerfMetrics_PushHistory(&snapshot->ram_free, avail_ram);
}
