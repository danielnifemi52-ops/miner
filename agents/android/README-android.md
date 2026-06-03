# XMRig Android Miner Agent

A Flutter-based background mining agent for Monero (XMR).

## Features
- Persistent background service via `flutter_background_service`
- Automatic start on device boot
- Interactive Flutter UI displaying live hashrate, uptime, and status
- Smart battery monitoring: Pauses mining if battery drops below 20%, resumes above 30%
- Seamless configuration sync with Coordinator server

## Setup and Installation

### 1. Download XMRig Binary
Download the official XMRig ARM64 Android binary from [XMRig GitHub Releases](https://github.com/xmrig/xmrig/releases).
Extract `xmrig` and rename the executable binary to `xmrig-arm64`. Place it under the `assets` folder:
`assets/xmrig-arm64`

### 2. Configure Coordinator URL & Agent Secret
Edit the constants at the top of [worker_reporter.dart](file:///c:/Users/Owner/Desktop/miner/agents/android/lib/worker_reporter.dart):
```dart
static const String defaultCoordinatorUrl = "http://YOUR_COORDINATOR_IP:3000";
static const String defaultAgentSecret = "YOUR_AGENT_SECRET";
```

### 3. Build the APK
Run the following command to build the release APK:
```bash
flutter build apk --release
```

### 4. Install and Run
Sideload the built APK onto your Android device:
- Copy the APK to your device.
- Enable **Install Unknown Apps** for your file manager or browser under Settings -> Security.
- Install the APK.
- Open the app and grant the requested battery optimization exclusions and notification permissions.
