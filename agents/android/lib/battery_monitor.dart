import 'package:battery_plus/battery_plus.dart';

class BatteryMonitor {
  final Battery _battery = Battery();

  Future<int> getBatteryLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (e) {
      print("Failed to get battery level: $e");
      return 100;
    }
  }

  Stream<BatteryState> get onBatteryStateChanged => _battery.onBatteryStateChanged;
}
