#import "PerfMetrics.h"
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <mach/processor_info.h>
#import <sys/sysctl.h>
#import <sys/socket.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <net/if_var.h>
#import <net/if_dl.h>
#import <sys/mount.h>
#import <sys/time.h>
#import <CoreFoundation/CoreFoundation.h>

typedef mach_port_t io_object_t;
typedef io_object_t io_registry_entry_t;
typedef io_object_t io_iterator_t;
extern const mach_port_t kIOMasterPortDefault;
CFMutableDictionaryRef IOServiceMatching(const char *name);
kern_return_t IOServiceGetMatchingServices(mach_port_t masterPort, CFDictionaryRef matching, io_iterator_t *existing);
io_object_t IOIteratorNext(io_iterator_t iterator);
kern_return_t IORegistryEntryCreateCFProperties(io_registry_entry_t entry, CFMutableDictionaryRef *properties, CFAllocatorRef allocator, uint32_t options);
kern_return_t IOObjectRelease(io_object_t object);

static unsigned long long s_last_cpu_total = 0;
static unsigned long long s_last_cpu_busy = 0;
static unsigned long long s_last_core_total[MAX_CORES] = {0};
static unsigned long long s_last_core_busy[MAX_CORES] = {0};
static uint64_t s_ram_total_bytes = 0;

static uint64_t s_last_ibytes = 0;
static uint64_t s_last_obytes = 0;
static uint64_t s_last_net_time_us = 0;

static io_registry_entry_t s_cached_drive = 0;
static uint64_t s_last_disk_read_bytes = 0;
static uint64_t s_last_disk_write_bytes = 0;
static uint64_t s_last_disk_time_us = 0;

void PerfMetrics_Init(void) {
    int mib[2] = { CTL_HW, HW_MEMSIZE };
    uint64_t mem = 0;
    size_t len = sizeof(mem);
    if (sysctl(mib, 2, &mem, &len, NULL, 0) == 0) {
        s_ram_total_bytes = mem;
    } else {
        s_ram_total_bytes = 512 * 1024 * 1024;
    }

    if (!s_cached_drive) {
        io_iterator_t iter = 0;
        CFMutableDictionaryRef matching = IOServiceMatching("IOBlockStorageDriver");
        if (matching && IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iter) == 0 && iter) {
            s_cached_drive = IOIteratorNext(iter);
            IOObjectRelease(iter);
        }
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

static void ReadNetwork(PerfMetricsSnapshot *s) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    uint64_t now_us = (uint64_t)tv.tv_sec * 1000000ULL + (uint64_t)tv.tv_usec;

    struct ifaddrs *ifa_list = NULL;
    if (getifaddrs(&ifa_list) != 0) return;

    uint64_t ibytes = 0, obytes = 0;
    for (struct ifaddrs *ifa = ifa_list; ifa != NULL; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr && ifa->ifa_addr->sa_family == AF_LINK) {
            struct if_data *ifd = (struct if_data *)ifa->ifa_data;
            if (ifd && strcmp(ifa->ifa_name, "lo0") != 0 && (ifa->ifa_flags & IFF_UP)) {
                ibytes += ifd->ifi_ibytes;
                obytes += ifd->ifi_obytes;
            }
        }
    }
    freeifaddrs(ifa_list);

    if (s_last_net_time_us > 0 && now_us > s_last_net_time_us) {
        double dt = (double)(now_us - s_last_net_time_us) / 1000000.0;
        if (dt > 0.05) {
            if (ibytes >= s_last_ibytes) {
                s->net_down_kb = (float)((double)(ibytes - s_last_ibytes) / (1024.0 * dt));
            }
            if (obytes >= s_last_obytes) {
                s->net_up_kb = (float)((double)(obytes - s_last_obytes) / (1024.0 * dt));
            }
        }
    }
    s_last_ibytes = ibytes;
    s_last_obytes = obytes;
    s_last_net_time_us = now_us;
    PerfMetrics_PushHistory(&s->net_down, s->net_down_kb);
}

static void ReadDiskSpace(PerfMetricsSnapshot *s) {
    struct statfs sf;
    if (statfs("/private/var", &sf) == 0) {
        float total_gb = (float)((double)sf.f_blocks * sf.f_bsize / (1024.0 * 1024.0 * 1024.0));
        float avail_mb = (float)((double)sf.f_bavail * sf.f_bsize / (1024.0 * 1024.0));
        s->disk_total_gb = total_gb;
        s->disk_avail_mb = avail_mb;
        s->disk_avail_gb = avail_mb / 1024.0f;
        if (total_gb > 0.01f) {
            float total_mb = total_gb * 1024.0f;
            s->disk_used_pct = ((total_mb - avail_mb) / total_mb) * 100.0f;
        }
    }
}

static void ReadDiskIo(PerfMetricsSnapshot *s) {
    if (!s_cached_drive) {
        io_iterator_t iter = 0;
        CFMutableDictionaryRef matching = IOServiceMatching("IOBlockStorageDriver");
        if (matching && IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iter) == 0 && iter) {
            s_cached_drive = IOIteratorNext(iter);
            IOObjectRelease(iter);
        }
    }

    if (s_cached_drive) {
        CFMutableDictionaryRef props = NULL;
        if (IORegistryEntryCreateCFProperties(s_cached_drive, &props, kCFAllocatorDefault, 0) == 0 && props) {
            CFDictionaryRef stats = (CFDictionaryRef)CFDictionaryGetValue(props, CFSTR("Statistics"));
            if (stats) {
                CFNumberRef rNum = (CFNumberRef)CFDictionaryGetValue(stats, CFSTR("Bytes (Read)"));
                CFNumberRef wNum = (CFNumberRef)CFDictionaryGetValue(stats, CFSTR("Bytes (Write)"));
                int64_t rb = 0, wb = 0;
                if (rNum) CFNumberGetValue(rNum, kCFNumberSInt64Type, &rb);
                if (wNum) CFNumberGetValue(wNum, kCFNumberSInt64Type, &wb);

                struct timeval tv;
                gettimeofday(&tv, NULL);
                uint64_t now_us = (uint64_t)tv.tv_sec * 1000000ULL + (uint64_t)tv.tv_usec;

                if (s_last_disk_time_us > 0 && now_us > s_last_disk_time_us) {
                    double dt = (double)(now_us - s_last_disk_time_us) / 1000000.0;
                    if (dt > 0.05) {
                        if ((uint64_t)rb >= s_last_disk_read_bytes) {
                            s->disk_read_kb = (float)((double)((uint64_t)rb - s_last_disk_read_bytes) / (1024.0 * dt));
                        }
                        if ((uint64_t)wb >= s_last_disk_write_bytes) {
                            s->disk_write_kb = (float)((double)((uint64_t)wb - s_last_disk_write_bytes) / (1024.0 * dt));
                        }
                    }
                }
                s_last_disk_read_bytes = (uint64_t)rb;
                s_last_disk_write_bytes = (uint64_t)wb;
                s_last_disk_time_us = now_us;
            }
            CFRelease(props);
        }
    }
    PerfMetrics_PushHistory(&s->disk_write, s->disk_write_kb);
}

void PerfMetrics_UpdateWithOptions(PerfMetricsSnapshot *snapshot, float current_fps, const PerfMetricsOptions *opts) {
    if (s_ram_total_bytes == 0) {
        PerfMetrics_Init();
    }

    PerfMetrics_PushHistory(&snapshot->fps, current_fps);

    if (opts->calc_cpu) {
        ReadCPU(snapshot);
    }
    if (opts->calc_ram) {
        ReadRAM(snapshot);
        float avail_ram = snapshot->ram_free_mb + snapshot->ram_inactive_mb;
        PerfMetrics_PushHistory(&snapshot->ram_free, avail_ram);
    }
    if (opts->calc_net) {
        ReadNetwork(snapshot);
    }
    if (opts->calc_disk_space) {
        ReadDiskSpace(snapshot);
    }
    if (opts->calc_disk_io) {
        ReadDiskIo(snapshot);
    }
}

void PerfMetrics_Update(PerfMetricsSnapshot *snapshot, float current_fps) {
    PerfMetricsOptions default_opts = { true, true, true, true, true };
    PerfMetrics_UpdateWithOptions(snapshot, current_fps, &default_opts);
}
