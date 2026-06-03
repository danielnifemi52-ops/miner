import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'worker_reporter.dart';
import 'xmrig_runner.dart';
import 'battery_monitor.dart';

class MinerService {
  static final XmrigRunner _runner = XmrigRunner();
  static final WorkerReporter _reporter = WorkerReporter();
  static final BatteryMonitor _batteryMonitor = BatteryMonitor();
  static Timer? _statsTimer;
  static int _uptimeSecs = 0;
  static bool _pausedDueToBattery = false;
  static bool _isMiningIntended = false;

  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'miner_service_channel',
        initialNotificationTitle: 'Distributed Miner',
        initialNotificationContent: 'Miner running in background',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onStart: onStart,
      ),
    );
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    // Set up communication channels
    service.on('stopService').listen((event) async {
      await _runner.stop();
      _statsTimer?.cancel();
      service.stopSelf();
    });

    service.on('startMining').listen((event) async {
      _isMiningIntended = true;
      await _startMiningLifecycle(service);
    });

    service.on('stopMining').listen((event) async {
      _isMiningIntended = false;
      await _runner.stop();
      _pausedDueToBattery = false;
      service.invoke('updateStatus', {
        'isMining': false,
        'statusText': 'Stopped',
      });
    });

    // Device info to get hostname (device model/name)
    String deviceName = "Android_Worker";
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceName = "${androidInfo.brand}_${androidInfo.model}".replaceAll(' ', '_');
      }
    } catch (e) {
      print("Failed to get device info: $e");
    }

    // IP address info
    String ipAddress = "127.0.0.1";
    try {
      final networkInfo = NetworkInfo();
      ipAddress = await networkInfo.getWifiIP() ?? "127.0.0.1";
    } catch (e) {
      print("Failed to get Wifi IP: $e");
    }

    // Initialize stats reporting loop
    _uptimeSecs = 0;
    _statsTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
      if (_runner.isMining) {
        _uptimeSecs += 60;
        final hashrate = await _runner.getHashrate();
        final workerId = await _reporter.getWorkerId();
        
        double cpuPercent = 50.0;
        
        if (workerId != null) {
          await _reporter.reportStats(
            workerId: workerId,
            hashrate: hashrate,
            cpuPercent: cpuPercent,
            uptimeSecs: _uptimeSecs,
          );
          
          service.invoke('updateStats', {
            'hashrate': hashrate,
            'uptimeSecs': _uptimeSecs,
          });
        }
      }
    });

    // Setup battery monitoring
    _batteryMonitor.onBatteryStateChanged.listen((state) async {
      if (_isMiningIntended) {
        await _checkBatteryAndAct(service, deviceName, ipAddress);
      }
    });

    // Automatically try starting on service boot
    _isMiningIntended = true;
    await _checkBatteryAndAct(service, deviceName, ipAddress);
  }

  static Future<void> _checkBatteryAndAct(ServiceInstance service, String deviceName, String ipAddress) async {
    final batteryLevel = await _batteryMonitor.getBatteryLevel();
    
    if (batteryLevel < 20 && _runner.isMining) {
      print("Battery low ($batteryLevel%), pausing mining");
      await _runner.stop();
      _pausedDueToBattery = true;
      service.invoke('updateStatus', {
        'isMining': false,
        'statusText': 'Paused (Battery Low)',
      });
    } else if (batteryLevel >= 30 && _pausedDueToBattery && !_runner.isMining) {
      print("Battery recovered ($batteryLevel%), resuming mining");
      _pausedDueToBattery = false;
      await _startMiningLifecycle(service, forceDeviceName: deviceName, forceIp: ipAddress);
    } else if (!_runner.isMining && !_pausedDueToBattery) {
      // Normal start
      await _startMiningLifecycle(service, forceDeviceName: deviceName, forceIp: ipAddress);
    }
  }

  static Future<void> _startMiningLifecycle(ServiceInstance service, {String? forceDeviceName, String? forceIp}) async {
    service.invoke('updateStatus', {
      'isMining': false,
      'statusText': 'Connecting...',
    });

    // 1. Fetch Config
    final config = await _reporter.fetchConfig();
    if (config == null) {
      print("Failed to fetch mining config from coordinator");
      service.invoke('updateStatus', {
        'isMining': false,
        'statusText': 'Error: Config Fetch Failed',
      });
      return;
    }

    final pool = config['pool'] ?? 'pool.moneroocean.stream:10008';
    final wallet = config['wallet'] ?? '';
    final maxCpuPercent = config['cpu_max_percent'] ?? 70;

    // 2. Register worker if not already registered
    String? workerId = await _reporter.getWorkerId();
    if (workerId == null) {
      String name = forceDeviceName ?? "Android_Worker";
      String ip = forceIp ?? "127.0.0.1";
      workerId = await _reporter.register(name, ip);
      if (workerId == null) {
        print("Failed to register worker with coordinator");
        service.invoke('updateStatus', {
          'isMining': false,
          'statusText': 'Error: Registration Failed',
        });
        return;
      }
    }

    // 3. Extract xmrig binary
    final appDir = Directory('/data/data/com.example.xmrig_android_agent/files');
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    final binaryPath = "${appDir.path}/xmrig-arm64";
    final configPath = "${appDir.path}/config.json";

    try {
      await _runner.extractBinary(binaryPath);
    } catch (e) {
      print("Failed to extract XMRig binary: $e");
    }

    // 4. Start XMRig
    final rigId = forceDeviceName ?? "Android_Worker";
    await _runner.start(
      binaryPath: binaryPath,
      configPath: configPath,
      pool: pool,
      wallet: wallet,
      rigId: rigId,
      maxCpuPercent: maxCpuPercent,
    );

    service.invoke('updateStatus', {
      'isMining': true,
      'statusText': 'Mining',
    });
  }
}
