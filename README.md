# PerfHUD for iOS 6

Zero-footprint real-time performance HUD and CLI telemetry monitor for legacy iOS (ARMv7, iOS 6.0–6.1.6).

![iOS 6](https://img.shields.io/badge/iOS-6.0%E2%80%936.1.6-blue.svg)
![Architecture](https://img.shields.io/badge/Arch-ARMv7%2032--bit-brightgreen.svg)
![Version](https://img.shields.io/badge/Version-1.0.0-orange.svg)

## Features

- **Real-Time Display:**
  - **FPS & Frametime:** Hardware-synchronized via `CADisplayLink` (60 Hz VSync) with sparkline history graph.
  - **CPU Utilization:** Overall CPU load and per-core breakdown (`C0`, `C1` for Apple A5 dual-core) with individual sparkline graphs and color thresholds (Blue < 65%, Yellow 65-85%, Red > 85%).
  - **Memory Metrics:** Active vs Inactive cache, total physical RAM, and detailed breakdown (`Wired`, `Active`, `Inactive`, `Free`).
  - **Stacked Memory Bar:** Visual page-allocation bar.
- **Interactive Control:**
  - Tap directly on the HUD panel to jump it clockwise to the next screen corner, instantly unblocking UI elements beneath.
- **CLI Telemetry Streaming (`perfhud-cli`):**
  - Stream metrics over SSH directly to your terminal without GUI overhead (`perfhud-cli -f`).
  - Zero NAND flash wear: writes atomically to RAM (`/var/tmp/perfhud.stat`).
- **Zero-Footprint Design:**
  - Single CoreGraphics render pass at 2 Hz (0.5s interval).
  - Pure C Mach kernel queries (`host_processor_info`, `host_statistics`).
  - Optional Wireframe mode (no background) in Settings.

## CLI Usage

Connect to your device over SSH:

```bash
# Single snapshot with timestamp:
perfhud-cli

# Output:
# [04:31:14] FPS:60.0 CPU: 11% (C0:12% C1:10%) RAM:242M/502M (W:87 A:109 I:12 F:230)

# Continuous real-time stream:
perfhud-cli -f
```

## Settings

Configurable via Settings.app $\to$ **PerfHUD**:
- **Enabled:** Toggle HUD overlay on/off.
- **Initial Corner:** Choose starting position (Top-Right, Bottom-Right, Bottom-Left, Top-Left).
- **Wireframe:** Transparent mode without solid background.

## License

GPL-3.0 License. Author: noname122021.
