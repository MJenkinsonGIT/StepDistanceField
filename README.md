# StepDistanceField

A data field for the Garmin Venu 3 that displays activity steps, distance in miles, and current walking/running speed — all calculated from the accelerometer-based step counter, so it works indoors without GPS.

---

## About This Project

This app was built through **vibecoding** — a development approach where the human provides direction, intent, and testing, and an AI (in this case, Claude by Anthropic) writes all of the code. I have no formal programming background; this is an experiment in what's possible when curiosity and AI assistance meet.

Every line of Monkey C in this project was written by Claude. My role was to describe what I wanted, test each iteration on a real Garmin Venu 3, report back what worked and what didn't, and keep pushing until the result was something I was happy with.

As part of this process, I've been building a knowledge base — a growing collection of Markdown documents that capture the real-world lessons Claude and I have uncovered together: non-obvious API behaviours, compiler quirks, layout constraints specific to the Venu 3's circular display, and fixes for bugs that aren't covered anywhere in the official SDK documentation. These files are fed back into Claude at the start of each new session so the knowledge carries forward rather than being rediscovered from scratch every time.

The knowledge base is open source. If you're building Connect IQ apps for the Venu 3 and want to skip some of the trial and error, you're welcome to use it:

**[Venu 3 Claude Coding Knowledge Base](https://github.com/MJenkinsonGIT/Venu3ClaudeCodingKnowledge)**

---

## Installation

### Which file should I download?

Each release includes three files. All three contain the same app — the difference is how they were compiled:

| File | Size | Best for |
|------|------|----------|
| `StepDistanceField-release.prg` | Smallest | Most users — just install and run |
| `StepDistanceField-debug.prg` | ~4× larger | Troubleshooting crashes — includes debug symbols |
| `StepDistanceField.iq` | Small (7-zip archive) | Developers / advanced users |

**Release `.prg`** is a fully optimised build with debug symbols and logging stripped out. This is what you want if you just want to use the app.

**Debug `.prg` + `.prg.debug.xml`** — these two files must be kept together. The `.prg` is the app binary; the `.prg.debug.xml` is the symbol map that translates raw crash addresses into source file names and line numbers. If the app crashes, the watch writes a log to `GARMIN\APPS\LOGS\CIQ_LOG.YAML` — cross-referencing that log against the `.prg.debug.xml` tells you exactly which line of code caused the crash. Without the `.prg.debug.xml`, the crash addresses in the log are unreadable hex. The app behaves identically to the release build; there is no difference in features or behaviour.

**`.iq` file** is a 7-zip archive containing the release `.prg` plus metadata (manifest, settings schema, signature). It is the format used for Connect IQ Store submissions. You can extract the `.prg` from it by renaming it to `.7z` and extracting — Windows 11 (22H2 and later) supports 7-zip natively via File Explorer's right-click menu. On older Windows versions you will need [7-Zip](https://www.7-zip.org/) (free).

---

**Option A — direct `.prg` download (simplest)**
1. Download the `.prg` file from the [Releases](#) section
2. Connect your Venu 3 via USB
3. Copy the `.prg` to `GARMIN\APPS\` on the watch
4. Press the **Back button** on the watch — it will show "Verifying Apps"
5. Unplug once the watch finishes

**Option B — debug build (for crash analysis)**
1. Download both `StepDistanceField-debug.prg` and `StepDistanceField.prg.debug.xml` — keep them together in the same folder on your PC
2. Copy `StepDistanceField-debug.prg` to `GARMIN\APPS\` on the watch
3. Press the **Back button** on the watch — it will show "Verifying Apps"
4. If the app crashes, retrieve `GARMIN\APPS\LOGS\CIQ_LOG.YAML` from the watch and cross-reference it against the `.prg.debug.xml` to identify the crash location

**Option C — extracting from the `.iq` file**

1. Rename `StepDistanceField.iq` to `StepDistanceField.7z`
2. Right-click it → **Extract All** (Windows 11 22H2+) or use [7-Zip](https://www.7-zip.org/) on older Windows
3. Inside the extracted folder, find the `.prg` file inside the device ID subfolder
4. Copy the `.prg` to `GARMIN\APPS\` on the watch
5. Press the **Back button** on the watch — it will show "Verifying Apps"
6. Unplug once the watch finishes

To add the field to an activity data screen: start an activity, long-press the lower button, navigate to **Data Screens**, and add the field to a slot.

> **To uninstall:** Use Garmin Express. Sideloaded apps cannot be removed directly from the watch or the Garmin Connect phone app.

---

## Device Compatibility

Built and tested on: **Garmin Venu 3**
SDK Version: **8.4.1 / API Level 5.2**

Compatibility with other devices has not been tested.

---

## What It Displays

The field shows three values at once:

```
        1,842 Steps
   0.89           3.2
   Miles           mph
```

| Value | Description |
|-------|-------------|
| **Steps** | Steps taken since the activity timer started |
| **Miles** | Distance covered since the activity timer started |
| **mph** | Current walking/running speed averaged over the last ~15 seconds |

The layout adapts automatically: a larger font is used when the field occupies a full or half screen slot; a more compact font is used in the smaller 1-of-4 slot.

---

## Why This Exists

Garmin's built-in distance and speed fields rely on GPS. For indoor activities — cardio workouts, treadmill walking, gym sessions — GPS is off, so those fields show nothing. This field uses the watch's **accelerometer-based step counter** instead, giving you meaningful distance and speed data indoors.

It also displays the step count for the current activity session, which Garmin does not expose as a built-in data field.

---

## How the Data Is Calculated

### Steps

Steps are read from `ActivityMonitor.getInfo().distance`, which is maintained by the watch's accelerometer regardless of whether GPS is active.

Because `ActivityMonitor` returns a **cumulative lifetime total** (not a per-activity count), a baseline is captured the moment you start the activity timer. Every subsequent reading subtracts that baseline:

```
activitySteps = currentLifetimeSteps − baselineSteps
```

The baseline is captured in `onTimerStart()`. If the timer is paused and resumed, the speed buffer is re-seeded but the step/distance baseline is preserved so the session total remains accurate.

### Distance (Miles)

`ActivityMonitor.getInfo().distance` returns cumulative distance in **centimetres**. The same baseline-subtraction approach is applied, then the result is converted to miles:

```
sessionDistanceCm = currentLifetimeDistanceCm − baselineDistanceCm
distanceMiles = sessionDistanceCm ÷ 160,934.4
```

160,934.4 is the number of centimetres in one mile (1,609.344 metres × 100).

The Venu 3 derives this distance from your step count and your **stride length**, which Garmin estimates from your height and gender in your user profile. It is the same figure Garmin uses in its own step-based distance tracking.

### Speed (mph)

Speed is calculated from a **15-sample circular buffer** of (timestamp, distance) pairs updated every second while the timer is running. Each new sample overwrites the oldest entry. Speed is then the straight-line rate between the oldest and newest sample in the buffer:

```
deltaCm = currentDistanceCm − oldestBufferDistanceCm
deltaMs = currentTimestampMs − oldestBufferTimestampMs

speedMph = (deltaCm ÷ (deltaMs + 1)) × (3,600,000 ÷ 160,934.4)
```

The `+ 1` in the denominator is a branchless guard against division by zero when the buffer is freshly seeded — it introduces an error of less than 0.001% over a 15-second window and is imperceptible in practice.

The `3,600,000 ÷ 160,934.4` factor converts from centimetres-per-millisecond to miles-per-hour:
- × 1,000 to convert ms → seconds
- × 3,600 to convert seconds → hours
- ÷ 160,934.4 to convert cm → miles

Speed resets to 0.0 whenever the activity timer is paused (auto-pause, manual pause) and resumes from 0 when the timer restarts, preventing stale speed values from persisting across pause events.

---

## Accuracy Notes

- **Steps** are as accurate as the Venu 3's accelerometer, which Garmin has tuned for walking and running. Unusual movements (cycling, weight training) may not register correctly.
- **Distance** accuracy depends on how well your Garmin profile's stride length estimate matches reality. You can improve accuracy by calibrating your stride length in the Garmin Connect app.
- **Speed** is a 15-second rolling average. It responds smoothly to changes in pace but will lag slightly behind instantaneous speed — this is intentional to prevent the display from jumping around.
- All three values reset to zero when the activity timer is reset.
