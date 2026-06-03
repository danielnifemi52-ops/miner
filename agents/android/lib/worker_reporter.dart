import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class WorkerReporter {
  // Constants to edit before building:
  static const String defaultCoordinatorUrl = "http://YOUR_COORDINATOR_IP:3000";
  static const String defaultAgentSecret = "YOUR_AGENT_SECRET";

  final _storage = const FlutterSecureStorage();

  // Getters for configuration
  Future<String> getCoordinatorUrl() async {
    String? url = await _storage.read(key: "coordinator_url");
    if (url == null || url.isEmpty) {
      url = defaultCoordinatorUrl;
      await _storage.write(key: "coordinator_url", value: url);
    }
    return url;
  }

  Future<String> getAgentSecret() async {
    String? secret = await _storage.read(key: "agent_secret");
    if (secret == null || secret.isEmpty) {
      secret = defaultAgentSecret;
      await _storage.write(key: "agent_secret", value: secret);
    }
    return secret;
  }

  Future<String?> getWorkerId() async {
    return await _storage.read(key: "worker_id");
  }

  Future<void> setWorkerId(String workerId) async {
    await _storage.write(key: "worker_id", value: workerId);
  }

  // Register worker
  Future<String?> register(String name, String ip) async {
    try {
      final baseUrl = await getCoordinatorUrl();
      final secret = await getAgentSecret();
      final url = Uri.parse("$baseUrl/api/register");
      
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "X-Agent-Secret": secret,
        },
        body: jsonEncode({
          "name": name,
          "platform": "android",
          "ip": ip,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final workerId = data["id"].toString();
        await setWorkerId(workerId);
        return workerId;
      } else {
        print("Registration failed: ${response.statusCode} - ${response.body}");
        return null;
      }
    } catch (e) {
      print("Error registering worker: $e");
      return null;
    }
  }

  // Report stats
  Future<bool> reportStats({
    required String workerId,
    required double hashrate,
    required double cpuPercent,
    required int uptimeSecs,
  }) async {
    try {
      final baseUrl = await getCoordinatorUrl();
      final secret = await getAgentSecret();
      final url = Uri.parse("$baseUrl/api/stats");

      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "X-Agent-Secret": secret,
        },
        body: jsonEncode({
          "worker_id": int.parse(workerId),
          "hashrate": hashrate,
          "cpu_percent": cpuPercent,
          "uptime_secs": uptimeSecs,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data["success"] == true;
      } else {
        print("Reporting stats failed: ${response.statusCode} - ${response.body}");
        return false;
      }
    } catch (e) {
      print("Error reporting stats: $e");
      return false;
    }
  }

  // Get config
  Future<Map<String, dynamic>?> fetchConfig() async {
    try {
      final baseUrl = await getCoordinatorUrl();
      final secret = await getAgentSecret();
      final url = Uri.parse("$baseUrl/api/config");

      final response = await http.get(
        url,
        headers: {
          "X-Agent-Secret": secret,
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        print("Fetching config failed: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("Error fetching config: $e");
      return null;
    }
  }
}
