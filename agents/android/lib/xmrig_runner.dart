import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

class XmrigRunner {
  Process? _process;
  bool _isMining = false;

  bool get isMining => _isMining;

  Future<void> extractBinary(String targetPath) async {
    final file = File(targetPath);
    if (!await file.exists()) {
      final byteData = await rootBundle.load('assets/xmrig-arm64');
      final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
      await file.writeAsBytes(bytes);
      // Make it executable
      await Process.run('chmod', ['755', targetPath]);
    }
  }

  Future<void> start({
    required String binaryPath,
    required String configPath,
    required String pool,
    required String wallet,
    required String rigId,
    required int maxCpuPercent,
  }) async {
    if (_isMining) return;

    // 1. Rebuild config.json from template or write it directly
    final configData = {
      "api": {
        "id": null,
        "worker-id": null
      },
      "http": {
        "enabled": true,
        "host": "127.0.0.1",
        "port": 3333,
        "access-token": null,
        "restricted": true
      },
      "autosave": true,
      "background": false,
      "colors": false,
      "title": false,
      "randomx": {
        "init": -1,
        "init-kms": -1,
        "mode": "auto",
        "1gb-pages": false,
        "rdmsr": false, // Must be false on Android (requires root)
        "wrmsr": false, // Must be false on Android (requires root)
        "cache_qos": false,
        "numa": false,
        "scratchpad_prefetch_mode": 1
      },
      "cpu": {
        "enabled": true,
        "huge-pages": false,
        "huge-pages-jit": false,
        "hw-aes": null,
        "priority": null,
        "memory-pool": false,
        "yield": true,
        "max-threads-hint": maxCpuPercent,
        "asm": true
      },
      "pools": [
        {
          "algo": null,
          "coin": null,
          "url": pool,
          "user": wallet,
          "pass": "x",
          "rig-id": rigId,
          "nicehash": false,
          "keepalive": true,
          "enabled": true,
          "tls": false,
          "tls-fingerprint": null,
          "daemon": false,
          "socks5": null,
          "self-select": null,
          "submit-to-origin": false
        }
      ]
    };

    final configFile = File(configPath);
    await configFile.writeAsString(jsonEncode(configData));

    // 2. Launch process
    try {
      _process = await Process.start(
        binaryPath,
        ['--config=$configPath'],
        workingDirectory: File(binaryPath).parent.path,
      );

      _isMining = true;

      // Handle output logging
      _process!.stdout.transform(utf8.decoder).listen((data) {
        print("[XMRig OUT] ${data.trim()}");
      });

      _process!.stderr.transform(utf8.decoder).listen((data) {
        print("[XMRig ERR] ${data.trim()}");
      });

      // Monitor exit
      _process!.exitCode.then((exitCode) {
        print("XMRig exited with code $exitCode");
        _isMining = false;
        _process = null;
      });
    } catch (e) {
      print("Failed to start XMRig: $e");
      _isMining = false;
      _process = null;
    }
  }

  Future<void> stop() async {
    if (_process != null) {
      _process!.kill();
      _process = null;
      _isMining = false;
    }
  }

  Future<double> getHashrate() async {
    if (!_isMining) return 0.0;
    try {
      final response = await http.get(Uri.parse("http://127.0.0.1:3333/1/summary")).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final hashrate = data["hashrate"]?["total"]?[0] ?? 0.0;
        return (hashrate as num).toDouble();
      }
    } catch (e) {
      print("Failed to get hashrate from local HTTP API: $e");
    }
    return 0.0;
  }
}
