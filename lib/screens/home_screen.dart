import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/sos_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<UserAccelerometerEvent>? _accelSub;

  // ✅ Shake settings
  final double _shakeThreshold = 13.0; // tuned for userAccelerometerEvents
  final int _shakeRequired = 3;

  int _shakeCount = 0;

  // ✅ Shake timing
  DateTime _lastShakeTime = DateTime.fromMillisecondsSinceEpoch(0);

  // ✅ Cooldown after SOS
  DateTime _lastSOSTime = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _sosCooldown = const Duration(seconds: 10);

  bool _sendingSOS = false;

  @override
  void initState() {
    super.initState();
    _startShakeDetection();
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    super.dispose();
  }

  void _startShakeDetection() {
    _accelSub = userAccelerometerEvents.listen((event) {
      final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      final now = DateTime.now();

      // ✅ Debounce (ignore quick spikes within 400ms)
      if (now.difference(_lastShakeTime).inMilliseconds < 400) return;

      if (magnitude > _shakeThreshold) {
        final prevShakeTime = _lastShakeTime;

        // ✅ update shake time
        _lastShakeTime = now;

        // ✅ if time gap too large, reset counter
        if (now.difference(prevShakeTime).inSeconds > 2) {
          _shakeCount = 0;
        }

        _shakeCount++;

        debugPrint("📳 Shake detected: $_shakeCount/(_shakeRequired)");

        if (_shakeCount >= _shakeRequired) {
          _shakeCount = 0;
          _autoSOS();
        }
      }
    });
  }

  Future<void> _autoSOS() async {
    // ✅ cooldown
    if (DateTime.now().difference(_lastSOSTime) < _sosCooldown) return;
    if (_sendingSOS) return;

    setState(() => _sendingSOS = true);

    try {
      final auth = context.read<AuthService>();
      final user = auth.currentUser;
      if (user == null) return;

      final sos = SOSService(uid: user.uid);
      final result = await sos.triggerSOS();

      _lastSOSTime = DateTime.now();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("📳 Shake SOS ✅: $result")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Shake SOS failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _sendingSOS = false);
    }
  }

  Future<void> _manualSOS() async {
    if (_sendingSOS) return;

    setState(() => _sendingSOS = true);

    try {
      final auth = context.read<AuthService>();
      final user = auth.currentUser;
      if (user == null) return;

      final sos = SOSService(uid: user.uid);
      final result = await sos.triggerSOS();

      _lastSOSTime = DateTime.now();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("🚨 SOS ✅: $result")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ SOS failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _sendingSOS = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;

    if (user == null) {
      Future.microtask(() {
        Navigator.pushReplacementNamed(context, "/login");
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final db = DatabaseService(uid: user.uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Women Safety"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await auth.logout();
              if (!context.mounted) return;
              Navigator.pushReplacementNamed(context, "/login");
            },
          )
        ],
      ),
      body: StreamBuilder(
        stream: db.userProfileStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data?.data() ?? {};
          final name = data["name"] ?? "No Name";
          final phone = data["phone"] ?? "No Phone";
          final note = data["emergencyNote"] ?? "";

          return Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Hello, $name 👋",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text("Phone: $phone"),
                if (note.toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text("Emergency Note: $note"),
                ],
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "📳 Shake 3 times to trigger SOS automatically.",
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(height: 25),
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      onTap: _manualSOS,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 180,
                        width: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _sendingSOS ? Colors.grey : Colors.red.shade600,
                          boxShadow: const [BoxShadow(blurRadius: 14, color: Colors.black26)],
                        ),
                        child: Center(
                          child: _sendingSOS
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text(
                                  "SOS",
                                  style: TextStyle(
                                    fontSize: 44,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, "/contacts"),
                  icon: const Icon(Icons.people),
                  label: const Text("Emergency Contacts"),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, "/profile"),
                  icon: const Icon(Icons.person),
                  label: const Text("Edit Profile"),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
