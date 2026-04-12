import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/sos_service.dart';
import '../services/recording_service.dart';
import '../services/storage_service.dart';
import '../services/call_service.dart';
import '../services/timer_sos_service.dart';
import '../services/voice_command_service.dart';
import '../services/power_button_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  StreamSubscription? _accelSub;
  GoogleMapController? _mapController;
  Position? _currentPosition;
  final Set<Marker> _markers = {};

  // Shake detection
  final double _shakeThreshold = 13.0;
  final int _shakeRequired = 3;
  int _shakeCount = 0;
  DateTime _lastShakeTime = DateTime.fromMillisecondsSinceEpoch(0);

  // SOS cooldown
  DateTime _lastSOSTime = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _sosCooldown = const Duration(seconds: 10);
  bool _sendingSOS = false;

  // Recording
  final RecordingService _recordingService = RecordingService();
  Timer? _recordingTimer;

  // Voice Commands
  VoiceCommandService? _voiceService;
  bool _isVoiceActive = false;

  // Power Button Service
  PowerButtonService? _powerButtonService;

  // Timer SOS
  TimerSOSService? _timerSOSService;
  bool _isTimerActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startShakeDetection();
    _getCurrentLocation();
    _initializeNewServices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accelSub?.cancel();
    _recordingTimer?.cancel();
    _recordingService.dispose();
    _mapController?.dispose();
    _voiceService?.stopListening();
    _voiceService?.dispose();
    _powerButtonService?.dispose();
    _timerSOSService?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncRecordingState();
    }
  }

  Future<void> _initializeNewServices() async {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) return;

    _voiceService = VoiceCommandService(
      uid: user.uid,
      onSOSTriggered: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🎤 Voice SOS Triggered!')),
          );
        }
      },
      onRecordingStarted: () => _startRecording(),
      onPoliceCall: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('📞 Calling Police...')),
          );
        }
      },
    );

    await _voiceService!.initialize();
    setState(() => _isVoiceActive = false);
    debugPrint('✅ Voice initialized (OFF by default)');

    _powerButtonService = PowerButtonService(
      uid: user.uid,
      onSOSTriggered: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🔘 Power Button SOS!')),
          );
        }
      },
    );
    await _powerButtonService!.startMonitoring();
    debugPrint('✅ Power button monitoring started');

    _timerSOSService = TimerSOSService(
      uid: user.uid,
      onTimerExpired: () {
        _showCheckInDialog();
      },
    );
    final isTimerActive = await _timerSOSService!.isTimerActive();
    setState(() => _isTimerActive = isTimerActive);
    debugPrint('✅ Timer SOS initialized (Active: $isTimerActive)');
  }

  Future<void> _toggleVoiceCommands() async {
    if (_voiceService == null) return;

    if (_isVoiceActive) {
      await _voiceService!.stopListening();
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() => _isVoiceActive = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔇 Voice commands OFF'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else {
      await _voiceService!.startListening();
      setState(() => _isVoiceActive = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎤 Voice commands ON'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _startShakeDetection() {
    _accelSub = userAccelerometerEvents.listen((event) {
      final magnitude =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      final now = DateTime.now();

      if (now.difference(_lastShakeTime).inMilliseconds < 400) return;

      if (magnitude > _shakeThreshold) {
        final prevShakeTime = _lastShakeTime;
        _lastShakeTime = now;

        if (now.difference(prevShakeTime).inSeconds > 2) {
          _shakeCount = 0;
        }

        _shakeCount++;
        debugPrint("📳 Shake detected: $_shakeCount/$_shakeRequired");

        if (_shakeCount >= _shakeRequired) {
          _shakeCount = 0;
          _autoSOS();
        }
      }
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
        _updateMarker(position);
      });

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          16,
        ),
      );
    } catch (e) {
      debugPrint('❌ Location error: $e');
      setState(() {
        _currentPosition = Position(
          latitude: 18.5204,
          longitude: 73.8567,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
        _updateMarker(_currentPosition!);
      });
    }
  }

  void _updateMarker(Position position) {
    _markers.clear();
    _markers.add(
      Marker(
        markerId: const MarkerId('current_location'),
        position: LatLng(position.latitude, position.longitude),
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(
          title: 'You',
          snippet: 'Your current location',
        ),
      ),
    );
  }

  Future<void> _autoSOS() async {
    if (DateTime.now().difference(_lastSOSTime) < _sosCooldown) return;
    if (_sendingSOS) return;

    debugPrint('📳 AUTO SOS triggered by shake');
    setState(() => _sendingSOS = true);

    try {
      await _startRecording();

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
      debugPrint('❌ AUTO SOS exception: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ SOS failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _sendingSOS = false);
    }
  }

  Future<void> _manualSOS() async {
    if (_sendingSOS) return;

    debugPrint('🚨 MANUAL SOS button pressed');
    setState(() => _sendingSOS = true);

    try {
      await _startRecording();

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
      debugPrint('❌ MANUAL SOS exception: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ SOS failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _sendingSOS = false);
    }
  }

  Future<void> _startRecording() async {
    debugPrint('🎥 _startRecording() CALLED');

    try {
      final started = await _recordingService.startRecording();

      if (started) {
        debugPrint('✅ Recording started!');
        if (mounted) setState(() {});

        _recordingTimer?.cancel();
        _recordingTimer =
            Timer(const Duration(minutes: 10), () async => _stopRecording());
      }
    } catch (e) {
      debugPrint('❌ _startRecording() EXCEPTION: $e');
    }
  }

  Future<void> _syncRecordingState() async {
    final completedPath = await _recordingService.consumeCompletedRecording();
    final error = await _recordingService.consumeRecordingError();
    final stateChanged = await _recordingService.refreshRecordingState();

    if (!mounted) return;

    if (stateChanged) {
      setState(() {});
    }

    if (completedPath != null) {
      setState(() {});
      await _handleSavedRecording(completedPath);
    }

    if (error != null && error.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Recording failed: $error')),
      );
    }
  }

  Future<void> _handleSavedRecording(String path) async {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Recording saved: ${path.split('/').last}'),
      ),
    );

    try {
      final user = context.read<AuthService>().currentUser;
      if (user != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('☁️ Uploading recording to Firebase...'),
            duration: Duration(seconds: 2),
          ),
        );

        await StorageService(uid: user.uid).uploadRecording(path);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Recording uploaded to Firebase'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Firebase upload failed: $e'),
        ),
      );
    } finally {
      await RecordingService.cleanupOldRecordings();
    }
  }

  Future<void> _stopRecording() async {
    debugPrint('⏹️ _stopRecording() CALLED');

    try {
      final path = await _recordingService.stopRecording();
      _recordingTimer?.cancel();

      if (mounted) setState(() {});

      if (path != null && mounted) {
        await _handleSavedRecording(path);
      }
    } catch (e) {
      debugPrint('❌ _stopRecording() EXCEPTION: $e');
    }
  }

  Future<void> _showCheckInDialog() async {
    if (!mounted) return;

    Timer? autoTriggerTimer;

    autoTriggerTimer = Timer(const Duration(seconds: 60), () {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop('timeout');
      }
    });

    final response = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          backgroundColor: Colors.orange.shade50,
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange.shade700,
                size: 32,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Are You Safe?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Your safety timer has expired!',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Please confirm you are safe.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(
                'SOS will be triggered automatically in 60 seconds if you don\'t respond.',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'safe'),
              icon: const Icon(Icons.check_circle),
              label: const Text('I\'m Safe'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'emergency'),
              icon: const Icon(Icons.warning),
              label: const Text('EMERGENCY!'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
          actionsAlignment: MainAxisAlignment.spaceEvenly,
        ),
      ),
    );

    autoTriggerTimer?.cancel();

    if (response == 'safe') {
      await _timerSOSService?.checkIn();
      setState(() => _isTimerActive = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Glad you\'re safe!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      await _timerSOSService?.triggerTimerSOS();
      setState(() => _isTimerActive = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response == 'emergency'
                  ? '🚨 Emergency SOS Triggered!'
                  : '⚠️ No response - SOS Triggered!',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showTimerDialog() async {
    final now = DateTime.now();
    DateTime selectedTime = now.add(const Duration(hours: 1));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('⏱️ Set Safety Timer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Set your expected return time.\nIf you don\'t check in by then, we\'ll ask if you\'re safe.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(selectedTime),
                  );
                  if (picked != null) {
                    setDialogState(() {
                      selectedTime = DateTime(
                        now.year,
                        now.month,
                        now.day,
                        picked.hour,
                        picked.minute,
                      );
                      if (selectedTime.isBefore(now)) {
                        selectedTime =
                            selectedTime.add(const Duration(days: 1));
                      }
                    });
                  }
                },
                icon: const Icon(Icons.access_time),
                label: Text(
                  '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Duration: ${selectedTime.difference(now).inMinutes} minutes',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Start Timer'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      await _timerSOSService?.setTimer(selectedTime);
      setState(() => _isTimerActive = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⏱️ Timer set for ${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _triggerRealCall() async {
    try {
      final auth = context.read<AuthService>();
      final user = auth.currentUser;
      if (user == null) return;

      final db = DatabaseService(uid: user.uid);
      final contacts = await db.getEmergencyContacts();

      if (contacts.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('❌ No emergency contacts added!'),
            action: SnackBarAction(
              label: 'Add Now',
              onPressed: () {
                Navigator.pushNamed(context, '/contacts');
              },
            ),
          ),
        );
        return;
      }

      final primaryContact = contacts.firstWhere(
        (c) => c['isPrimary'] == true,
        orElse: () => contacts.first,
      );

      final name = primaryContact['name'] ?? 'Emergency Contact';
      final phone = primaryContact['phone'] ?? '';

      if (phone.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Invalid phone number!')),
        );
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Emergency Call'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Call your primary emergency contact?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.person, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(child: Text(name)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.phone, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(child: Text(phone)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.call),
              label: const Text('Call Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        final success = await CallService.makeCall(phone);

        if (!mounted) return;
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('📞 Calling $name...')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Failed to make call')),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Call error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;

    if (user == null) {
      Future.microtask(
        () => Navigator.pushReplacementNamed(context, "/login"),
      );
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    const background = Color(0xFF090014);
    final accent = Colors.pinkAccent;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.shield, size: 24),
            const SizedBox(width: 8),
            const Text(
              "Shrimati Setu",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const Spacer(),
            if (_recordingService.isRecording)
              const Icon(
                Icons.fiber_manual_record,
                color: Colors.redAccent,
                size: 18,
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: const Color(0xFF140624),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                builder: (context) => DraggableScrollableSheet(
                  initialChildSize: 0.7,
                  minChildSize: 0.5,
                  maxChildSize: 0.95,
                  expand: false,
                  builder: (context, scrollController) => Padding(
                    padding: const EdgeInsets.all(20),
                    child: ListView(
                      controller: scrollController,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.menu, color: Colors.white70),
                            SizedBox(width: 8),
                            Text(
                              'Safety Menu',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(color: Colors.white24),
                        // Timer SOS card
                        Card(
                          color: const Color(0xFF1E0E36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  _isTimerActive ? Colors.orange : Colors.grey,
                              child: Icon(
                                _isTimerActive
                                    ? Icons.timer
                                    : Icons.timer_off,
                                color: Colors.white,
                              ),
                            ),
                            title: const Text(
                              'Timer SOS',
                              style: TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              _isTimerActive
                                  ? 'Active - Timer running'
                                  : 'Start Safety Timer',
                              style: TextStyle(
                                color: _isTimerActive
                                    ? Colors.orange
                                    : Colors.white54,
                              ),
                            ),
                            trailing: ElevatedButton(
                              onPressed: () async {
                                Navigator.pop(context);
                                if (_isTimerActive) {
                                  await _timerSOSService?.cancelTimer();
                                  setState(() => _isTimerActive = false);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('⏱️ Timer Cancelled'),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                  }
                                } else {
                                  _showTimerDialog();
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    _isTimerActive ? Colors.red : Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                              child:
                                  Text(_isTimerActive ? 'Cancel' : 'Start'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          secondary: Icon(
                            Icons.mic,
                            color: _isVoiceActive
                                ? Colors.green
                                : Colors.white54,
                          ),
                          title: const Text(
                            'Voice Commands',
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            _isVoiceActive
                                ? 'Listening for help words'
                                : 'Tap to enable',
                            style: const TextStyle(color: Colors.white60),
                          ),
                          value: _isVoiceActive,
                          onChanged: (value) async {
                            Navigator.pop(context);
                            await _toggleVoiceCommands();
                          },
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.people,
                            color: Colors.blueAccent,
                          ),
                          title: const Text(
                            'Emergency Contacts',
                            style: TextStyle(color: Colors.white),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushNamed(context, '/contacts');
                          },
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.video_library,
                            color: Colors.orangeAccent,
                          ),
                          title: const Text(
                            'View Recordings',
                            style: TextStyle(color: Colors.white),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushNamed(context, '/recordings');
                          },
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.person,
                            color: Colors.greenAccent,
                          ),
                          title: const Text(
                            'Edit Profile',
                            style: TextStyle(color: Colors.white),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushNamed(context, '/profile');
                          },
                        ),
                        Divider(color: Colors.white24),
                        ListTile(
                          leading: const Icon(
                            Icons.logout,
                            color: Colors.redAccent,
                          ),
                          title: const Text(
                            'Logout',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () async {
                            Navigator.pop(context);
                            await auth.logout();
                            Navigator.pushReplacementNamed(
                              context,
                              '/login',
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding:
            const EdgeInsets.only(left: 16, right: 16, bottom: 8, top: 4),
        child: Column(
          children: [
            // Only map card on top
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF130922),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: _currentPosition == null
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                                color: Colors.pinkAccent),
                            SizedBox(height: 16),
                            Text(
                              'Locking on to your location...',
                              style: TextStyle(
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(
                            _currentPosition!.latitude,
                            _currentPosition!.longitude,
                          ),
                          zoom: 16,
                        ),
                        markers: _markers,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        compassEnabled: true,
                        mapToolbarEnabled: true,
                        zoomControlsEnabled: false,
                        onMapCreated: (controller) {
                          _mapController = controller;
                          debugPrint('🗺️ Map created successfully');
                        },
                      ),
              ),
            ),
            const SizedBox(height: 10),

            // Bottom controls
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF130922),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Record
                    _BottomAction(
                      label:
                          _recordingService.isRecording ? 'Stop' : 'Record',
                      icon: _recordingService.isRecording
                          ? Icons.stop_circle
                          : Icons.videocam,
                      color: _recordingService.isRecording
                          ? Colors.redAccent
                          : Colors.white70,
                      onTap: () async {
                        if (_recordingService.isRecording) {
                          await _stopRecording();
                        } else {
                          await _startRecording();
                        }
                      },
                    ),

                    // SOS
                    GestureDetector(
                      onTap: _manualSOS,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color:
                                  _sendingSOS ? Colors.grey : accent,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withOpacity(0.7),
                                  blurRadius: 25,
                                  spreadRadius: 3,
                                ),
                              ],
                            ),
                            child: Center(
                              child: _sendingSOS
                                  ? const CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 3,
                                    )
                                  : const Text(
                                      "SOS",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 2,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'SOS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Call
                    _BottomAction(
                      label: 'Call',
                      icon: Icons.phone,
                      color: Colors.greenAccent,
                      onTap: _triggerRealCall,
                    ),

                    // Profile
                    _BottomAction(
                      label: 'Profile',
                      icon: Icons.person,
                      color: Colors.lightBlueAccent,
                      onTap: () {
                        Navigator.pushNamed(context, '/profile');
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _BottomAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
