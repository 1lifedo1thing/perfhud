#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdbool.h>
#include <string.h>

int main(int argc, char *argv[]) {
    bool follow = false;
    if (argc > 1 && (strcmp(argv[1], "-f") == 0 || strcmp(argv[1], "--follow") == 0)) {
        follow = true;
    }

    const char *path = "/var/tmp/perfhud.stat";
    char line[256];
    char last_line[256] = {0};

    if (access(path, F_OK) != 0) {
        fprintf(stderr, "PerfHUD is not running or disabled in Settings.\n");
        return 1;
    }

    if (!follow) {
        FILE *f = fopen(path, "r");
        if (f && fgets(line, sizeof(line), f)) {
            printf("%s", line);
            fclose(f);
            return 0;
        }
        return 1;
    }

    printf("=== Streaming PerfHUD Telemetry (Ctrl+C to stop) ===\n");
    while (1) {
        FILE *f = fopen(path, "r");
        if (f) {
            if (fgets(line, sizeof(line), f)) {
                if (strcmp(line, last_line) != 0) {
                    printf("%s", line);
                    fflush(stdout);
                    strncpy(last_line, line, sizeof(last_line) - 1);
                }
            }
            fclose(f);
        }
        usleep(250000); // 250ms polling in RAM
    }

    return 0;
}
