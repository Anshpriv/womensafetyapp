import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'video_player_screen.dart'; // ✅ Add at top

import 'package:truck_safety_app/services/auth_service.dart';
import 'package:truck_safety_app/services/database_service.dart';
import 'package:truck_safety_app/services/live_location_service.dart';
import 'package:truck_safety_app/services/sos_service.dart';
import 'package:truck_safety_app/services/translation_service.dart';

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
        SnackBar(content: Text("📳 Shake ${TranslationService.t('sos')}: $result")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(TranslationService.t('sos_failed'))),
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
        SnackBar(content: Text("${TranslationService.t('sos_sent')}: $result")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(TranslationService.t('sos_failed'))),
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
        SnackBar(content: Text(TranslationService.t('live_tracking_started'))),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(TranslationService.t('permission_missing'))),
      );
    }
  }

  // ✅ STOP live tracking
  Future<void> _stopLiveTracking() async {
    await _liveLocationService?.stop();
    if (!mounted) return;

    setState(() => _trackingLive = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(TranslationService.t('live_tracking_stopped'))),
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
        title: Text(TranslationService.t('Truck Saftey')),
        backgroundColor: Colors.blue.shade800,
        elevation: 0,
        actions: [


           IconButton(
      icon: const Text(
        '🎥',
        style: TextStyle(fontSize: 24),
      ),
      tooltip: 'Watch Safety Video',
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const VideoPlayerScreen(),
          ),
        );
      },
    ),
          // ✅ LANGUAGE SELECTOR
          PopupMenuButton<String>(
            icon: const Icon(Icons.language),
            tooltip: TranslationService.t('select_language'),
            onSelected: (String languageCode) async {
              await TranslationService.changeLanguage(languageCode);
              
              // ✅ FORCE REBUILD
              if (context.mounted) {
                setState(() {});
                
                final langName = languageCode == 'en' 
                    ? 'English' 
                    : languageCode == 'hi' 
                        ? 'हिंदी' 
                        : 'मराठी';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Language changed to $langName ✅'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem(
                  value: 'en',
                  child: Row(
                    children: [
                      Text('🇬🇧', style: TextStyle(fontSize: 24)),
                      SizedBox(width: 12),
                      Text('English'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'hi',
                  child: Row(
                    children: [
                      Text('🇮🇳', style: TextStyle(fontSize: 24)),
                      SizedBox(width: 12),
                      Text('हिंदी'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'mr',
                  child: Row(
                    children: [
                      Text('🇮🇳', style: TextStyle(fontSize: 24)),
                      SizedBox(width: 12),
                      Text('मराठी'),
                    ],
                  ),
                ),
              ];
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: TranslationService.t('logout'),
            onPressed: () async {
              await auth.logout();
              if (!context.mounted) return;
              Navigator.pushReplacementNamed(context, "/login");
            },
          ),
        ],
      ),

      body: StreamBuilder(
        stream: db.userProfileStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data?.data() ?? <String, dynamic>{};
          final name = data["name"] ?? "No Name";
          final phone = data["phone"] ?? "No Phone";
          final note = data["emergencyNote"] ?? "";

          return SingleChildScrollView(
            child: Column(
              children: [
                // ✅ HEADER SECTION
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade800,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(30),
                      bottomRight: Radius.circular(30),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${TranslationService.t('hello')}, $name 👋",
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "📱 $phone",
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                      if (note.toString().trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: Colors.white, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  note,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ✅ SHAKE HINT
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.vibration, color: Colors.orange.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          TranslationService.t('shake_hint'),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ✅ LIVE LOCATION TOGGLE
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _trackingLive
                            ? [Colors.red.shade400, Colors.red.shade600]
                            : [Colors.green.shade400, Colors.green.shade600],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: (_trackingLive ? Colors.red : Colors.green).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: InkWell(
                      onTap: _trackingLive ? _stopLiveTracking : _startLiveTracking,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _trackingLive ? Icons.stop_circle : Icons.location_on,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              _trackingLive
                                  ? TranslationService.t('stop_live_tracking')
                                  : TranslationService.t('start_live_tracking'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // ✅ SOS BUTTON
                GestureDetector(
                  onTap: _manualSOS,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 200,
                    width: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: _sendingSOS
                            ? [Colors.grey.shade400, Colors.grey.shade600]
                            : [Colors.red.shade400, Colors.red.shade700],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Center(
                      child: _sendingSOS
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 5,
                            )
                          : Text(
                              TranslationService.t('sos'),
                              style: const TextStyle(
                                fontSize: 52,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 4,
                              ),
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // ✅ FEATURE GRID
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.3,
                    children: [
                      _buildFeatureCard(
                        icon: Icons.people,
                        title: TranslationService.t('emergency_contacts'),
                        color: Colors.purple,
                        onTap: () => Navigator.pushNamed(context, "/contacts"),
                      ),
                      _buildFeatureCard(
                        icon: Icons.local_shipping,
                        title: TranslationService.t('truck_monitoring'),
                        color: Colors.blue,
                        onTap: () => Navigator.pushNamed(context, "/monitoring"),
                      ),
                      _buildFeatureCard(
                        icon: Icons.people_alt,
                        title: TranslationService.t('shared_locations'),
                        color: Colors.orange,
                        onTap: () => Navigator.pushNamed(context, "/shared_locations"),
                      ),
                      _buildFeatureCard(
                        icon: Icons.person,
                        title: TranslationService.t('edit_profile'),
                        color: Colors.teal,
                        onTap: () => Navigator.pushNamed(context, "/profile"),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),
              ],
            ),
          );
        },
      ),
    );
  }

  // ✅ HELPER METHOD - Feature Card Widget
  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
