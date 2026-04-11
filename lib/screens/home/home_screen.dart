import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'package:truck_safety_app/services/auth_service.dart';
import 'package:truck_safety_app/services/database_service.dart';
import 'package:truck_safety_app/services/live_location_service.dart';
import 'package:truck_safety_app/services/sos_service.dart';
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ==========================
  // SHAKE DETECTION
  // ==========================
  StreamSubscription<AccelerometerEvent>? _accelSub;

  final double _shakeThreshold = 18.0;
  final int _shakeRequired = 3;

  int _shakeCount = 0;
  DateTime _lastShakeTime = DateTime.fromMillisecondsSinceEpoch(0);

  // ==========================
  // SOS + LIVE LOCATION
  // ==========================
  bool _sendingSOS = false;

  bool _trackingLive = false;
  LiveLocationService? _liveLocationService;

  @override
  void initState() {
    super.initState();
    _startShakeDetection();
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _liveLocationService?.stop();
    super.dispose();
  }

  // ✅ Shake logic
  void _startShakeDetection() {
    _accelSub = accelerometerEvents.listen((event) async {
      final double magnitude =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

      final now = DateTime.now();

      // ✅ debounce: ignore spikes within 400ms
      if (now.difference(_lastShakeTime).inMilliseconds < 400) return;

      if (magnitude > _shakeThreshold) {
        // ✅ if too much delay reset count
        if (now.difference(_lastShakeTime).inSeconds > 2) {
          _shakeCount = 0;
        }

        _shakeCount++;
        _lastShakeTime = now;

        debugPrint("📳 Shake detected: $_shakeCount/$_shakeRequired");

        if (_shakeCount >= _shakeRequired) {
          _shakeCount = 0;
          await _autoSOS();
        }
      }
    });
  }

  // ✅ Automatic SOS (shake)
  Future<void> _autoSOS() async {
    if (_sendingSOS) return;
    setState(() => _sendingSOS = true);

    try {
      final auth = context.read<AuthService>();
      final user = auth.currentUser;
      if (user == null) return;

      final sos = SOSService(uid: user.uid);
      final result = await sos.triggerSOS();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("📳 Shake SOS: $result")),
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

  // ✅ Manual SOS (button)
  Future<void> _manualSOS() async {
    if (_sendingSOS) return;
    setState(() => _sendingSOS = true);

    try {
      final auth = context.read<AuthService>();
      final user = auth.currentUser;
      if (user == null) return;

      final sos = SOSService(uid: user.uid);
      final result = await sos.triggerSOS();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("🚨 SOS: $result")),
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

  // ✅ START live tracking
  Future<void> _startLiveTracking() async {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) return;

    _liveLocationService = LiveLocationService(uid: user.uid);

    final ok = await _liveLocationService!.start();
    if (!mounted) return;

    if (ok) {
      setState(() => _trackingLive = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("📍 Live tracking started ✅")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Live tracking permission missing")),
      );
    }
  }

  // ✅ STOP live tracking
  Future<void> _stopLiveTracking() async {
    await _liveLocationService?.stop();
    if (!mounted) return;

    setState(() => _trackingLive = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🛑 Live tracking stopped")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;

    // ✅ if not logged in, go login
    if (user == null) {
      Future.microtask(() {
        Navigator.pushReplacementNamed(context, "/login");
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final db = DatabaseService(uid: user.uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text("TRUCK SAFETY"),
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

      // ✅ IMPORTANT: add generic typing to StreamBuilder
      body: StreamBuilder(
        stream: db.userProfileStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // ✅ safe map
          final data = snapshot.data?.data() ?? <String, dynamic>{};

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
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text("Phone: $phone"),
                if (note.toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text("Emergency Note: $note"),
                ],

                const SizedBox(height: 18),

                // ✅ Shake hint
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "📳 Shake phone 3 times to auto trigger SOS.",
                    style: TextStyle(fontSize: 14),
                  ),
                ),

                const SizedBox(height: 20),

                // ✅ LIVE LOCATION BUTTON
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    backgroundColor:
                        _trackingLive ? Colors.red : Colors.green,
                  ),
                  onPressed:
                      _trackingLive ? _stopLiveTracking : _startLiveTracking,
                  icon: Icon(_trackingLive ? Icons.stop : Icons.location_on),
                  label: Text(
                    _trackingLive
                        ? "Stop Live Location Tracking"
                        : "Start Live Location Tracking",
                  ),
                ),

                const SizedBox(height: 25),

                // ✅ SOS BUTTON
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
                          boxShadow: const [
                            BoxShadow(blurRadius: 14, color: Colors.black26)
                          ],
                        ),
                        child: Center(
                          child: _sendingSOS
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
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
