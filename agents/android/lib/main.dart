import 'package:flutter/material';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'miner_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MinerService.initializeService();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '⛏ Miner Agent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.amber,
        scaffoldBackgroundColor: const Color(0xFF0F0F12),
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          secondary: Colors.amberAccent,
          surface: Color(0xFF1A1A24),
          background: Color(0xFF0F0F12),
        ),
        cardTheme: const CardTheme(
          color: Color(0xFF1A1A24),
          elevation: 4,
        ),
      ),
      home: const MinerHomePage(),
    );
  }
}

class MinerHomePage extends StatefulWidget {
  const MinerHomePage({super.key});

  @override
  State<MinerHomePage> createState() => _MinerHomePageState();
}

class _MinerHomePageState extends State<MinerHomePage> {
  String _statusText = "Stopped";
  bool _isMining = false;
  double _hashrate = 0.0;
  int _uptimeSecs = 0;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    FlutterBackgroundService().on('updateStatus').listen((event) {
      if (event != null && mounted) {
        setState(() {
          _isMining = event['isMining'] ?? false;
          _statusText = event['statusText'] ?? 'Stopped';
          if (!_isMining && _statusText == 'Mining') {
             _statusText = 'Stopped';
          }
        });
      }
    });

    FlutterBackgroundService().on('updateStats').listen((event) {
      if (event != null && mounted) {
        setState(() {
          _hashrate = event['hashrate'] ?? 0.0;
          _uptimeSecs = event['uptimeSecs'] ?? 0;
        });
      }
    });
  }

  String _formatUptime(int seconds) {
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (d > 0) return "${d}d ${h}h ${m}m";
    if (h > 0) return "${h}h ${m}m ${s}s";
    return "${m}m ${s}s";
  }

  void _toggleMining() {
    if (_isMining) {
      FlutterBackgroundService().invoke('stopMining');
      setState(() {
        _isMining = false;
        _statusText = "Stopped";
        _hashrate = 0.0;
      });
    } else {
      FlutterBackgroundService().invoke('startMining');
      setState(() {
        _statusText = "Connecting...";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.terminal, color: Colors.amber),
            SizedBox(width: 10),
            Text(
              "XMRIG AGENT",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1A1A24),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A24), Color(0xFF0F0F12)],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Icon & Label
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _isMining ? Colors.amber.withOpacity(0.1) : Colors.redAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isMining ? Colors.amber : Colors.redAccent,
                    width: 2,
                  ),
                ),
                child: Icon(
                  _isMining ? Icons.dns : Icons.dns_outlined,
                  size: 64,
                  color: _isMining ? Colors.amber : Colors.redAccent,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                _statusText.toUpperCase(),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                  color: _isMining 
                      ? Colors.amber 
                      : (_statusText == 'Connecting...' ? Colors.blueAccent : Colors.redAccent),
                ),
              ),
            ),
            const SizedBox(height: 40),
            
            // Statistics Card
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const Text(
                      "CURRENT HASHRATE",
                      style: TextStyle(
                        fontSize: 12, 
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Colors.grey
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${_hashrate.toStringAsFixed(2)} H/s",
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const Divider(height: 32, color: Colors.white10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Text("UPTIME", style: TextStyle(color: Colors.grey, fontSize: 12)),
                            const SizedBox(height: 6),
                            Text(
                              _formatUptime(_uptimeSecs),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                        Container(width: 1, height: 30, color: Colors.white10),
                        Column(
                          children: [
                            const Text("ALGORITHM", style: TextStyle(color: Colors.grey, fontSize: 12)),
                            const SizedBox(height: 6),
                            const Text(
                              "RandomX",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amber),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 48),
            
            // Control Button
            ElevatedButton(
              onPressed: _toggleMining,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isMining ? Colors.redAccent : Colors.amber,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                shadowColor: (_isMining ? Colors.redAccent : Colors.amber).withOpacity(0.3),
              ),
              child: Text(
                _isMining ? "STOP MINING" : "START MINING",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Mining Monero (XMR) on background thread.\nService automatically pauses when battery level < 20%.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
