import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../services/geofence_service.dart';
import '../services/ai_risk_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  StreamSubscription? _accelSub;
  GoogleMapController? _mapController;
  Position? _currentPosition;
  final Set<Marker> _markers = {};

  // Shake detection
  final double _shakeThreshold = 13.0;
  final int _shakeRequired = 3;
  int _shakeCount = 0;
  DateTime _lastShakeTime = DateTime.fromMillisecondsSinceEpoch(0);
  final List<MovementSample> _movementWindow = [];

  // SOS cooldown
  DateTime _lastSOSTime = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _sosCooldown = const Duration(seconds: 10);
  bool _sendingSOS = false;
  final List<DateTime> _recentAutomaticTriggerTimes = [];
  int _recentSosCount = 0;

  // AI-Based Contextual Threat & Risk Detection
  final AIRiskService _aiRiskService = AIRiskService(
    inferenceUrl: const String.fromEnvironment('AI_RISK_API_URL'),
  );
  AIRiskResult? _lastAIRiskResult;
  bool _analyzingRisk = false;

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

  // GeoFence
  GeoFenceService? _geoFenceService;

  // Map Animation
  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: false);

    _pulseAnimation =
        Tween<double>(begin: 0, end: 150).animate(
          CurvedAnimation(parent: _pulseController!, curve: Curves.easeOut),
        )..addListener(() {
          if (mounted) setState(() {});
        });

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
    _geoFenceService?.dispose();
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb && state == AppLifecycleState.resumed) {
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('📞 Calling Police...')));
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('🔘 Power Button SOS!')));
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

    _geoFenceService = GeoFenceService(uid: user.uid);
    await _geoFenceService!.startMonitoring();
    debugPrint('✅ GeoFence Monitoring started');
  }

  Future<void> _toggleVoiceCommands() async {
    if (_voiceService == null) return;

    if (_isVoiceActive) {
      await _voiceService!.stopListening();
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() => _isVoiceActive = false);
      if (mounted) {
        _showVoiceCommandFeedback(enabled: false);
      }
    } else {
      await _voiceService!.startListening();
      setState(() => _isVoiceActive = true);
      if (mounted) {
        _showVoiceCommandFeedback(enabled: true);
      }
    }
  }

  void _showVoiceCommandFeedback({required bool enabled}) {
    BuildContext? feedbackContext;

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss voice command status',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        feedbackContext = dialogContext;
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 460),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBFC),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFF1D6E0)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x2ED9366E),
                        blurRadius: 28,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFE5EE),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          enabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                          color: const Color(0xFFD9366E),
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              enabled
                                  ? 'Voice commands are on'
                                  : 'Voice commands are off',
                              style: const TextStyle(
                                color: Color(0xFF202A3B),
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              enabled
                                  ? 'Listening for your safety commands.'
                                  : 'Voice listening has been paused.',
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                        color: const Color(0xFFD9366E),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.24),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
    );

    Future<void>.delayed(const Duration(milliseconds: 2600), () {
      final dialogContext = feedbackContext;
      if (dialogContext != null && dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
    });
  }

  void _startShakeDetection() {
    _accelSub = userAccelerometerEvents.listen((event) {
      final magnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      final now = DateTime.now();
      _recordMovementSample(event.x, event.y, event.z, magnitude, now);

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
          final detectedShakeCount = _shakeCount;
          _shakeCount = 0;
          _handleAutomaticShakeTrigger(detectedShakeCount);
        }
      }
    });
  }

  void _recordMovementSample(
    double x,
    double y,
    double z,
    double magnitude,
    DateTime timestamp,
  ) {
    _movementWindow.add(
      MovementSample(
        x: x,
        y: y,
        z: z,
        magnitude: magnitude,
        timestamp: timestamp,
      ),
    );

    final cutoff = timestamp.subtract(const Duration(seconds: 4));
    _movementWindow.removeWhere((sample) => sample.timestamp.isBefore(cutoff));
  }

  Future<void> _handleAutomaticShakeTrigger(int detectedShakeCount) async {
    if (DateTime.now().difference(_lastSOSTime) < _sosCooldown) return;
    if (_sendingSOS || _analyzingRisk) return;

    final now = DateTime.now();
    final previousAutomaticTrigger = _recentAutomaticTriggerTimes.isEmpty
        ? null
        : _recentAutomaticTriggerTimes.last;
    _recentAutomaticTriggerTimes.add(now);
    _recentAutomaticTriggerTimes.removeWhere(
      (time) => now.difference(time) > const Duration(minutes: 5),
    );

    setState(() => _analyzingRisk = true);

    try {
      final riskContext = AIRiskService.buildShakeContext(
        samples: List<MovementSample>.from(_movementWindow),
        shakeCount: detectedShakeCount,
        position: _currentPosition,
        recentAutomaticTriggerCount: _recentAutomaticTriggerTimes.length,
        recentSosCount: _recentSosCount,
        secondsSincePreviousTrigger: previousAutomaticTrigger == null
            ? 9999
            : now.difference(previousAutomaticTrigger).inSeconds,
      );

      final result = await _aiRiskService.analyze(riskContext);
      if (mounted) {
        setState(() => _lastAIRiskResult = result);
      }

      switch (result.level) {
        case AIRiskLevel.lowRisk:
          debugPrint('AI risk LOW_RISK for shake: ${result.reason}');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Normal activity detected. Monitoring continues.'),
              backgroundColor: Colors.green,
            ),
          );
          return;
        case AIRiskLevel.suspicious:
          await _showSuspiciousActivityDialog(result);
          return;
        case AIRiskLevel.highRisk:
          await _autoSOS(aiResult: result);
          return;
      }
    } catch (e) {
      debugPrint('AI risk analysis failed; using existing shake SOS flow: $e');
      await _autoSOS();
    } finally {
      if (mounted) setState(() => _analyzingRisk = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final permissionCheck = Geolocator.checkPermission();
      final permission = kIsWeb
          ? await permissionCheck.timeout(const Duration(seconds: 3))
          : await permissionCheck;
      if (permission == LocationPermission.denied) {
        final permissionRequest = Geolocator.requestPermission();
        if (kIsWeb) {
          await permissionRequest.timeout(const Duration(seconds: 3));
        } else {
          await permissionRequest;
        }
      }

      final locationRequest = Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final position = kIsWeb
          ? await locationRequest.timeout(const Duration(seconds: 8))
          : await locationRequest;

      if (!mounted) return;
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
      if (!mounted) return;
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
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(
          title: 'You',
          snippet: 'Your current location',
        ),
      ),
    );
  }

  Future<void> _autoSOS({AIRiskResult? aiResult}) async {
    if (DateTime.now().difference(_lastSOSTime) < _sosCooldown) return;
    if (_sendingSOS) return;

    debugPrint('📳 AUTO SOS triggered by shake');
    setState(() => _sendingSOS = true);

    try {
      final auth = context.read<AuthService>();
      final user = auth.currentUser;
      if (user == null) return;

      await _startRecording();

      final sos = SOSService(uid: user.uid);
      final result = await sos.triggerSOS(
        eventMetadata: {
          'trigger_type': 'automatic_shake',
          if (aiResult != null)
            ...aiResult.toFirestore(triggerType: 'automatic_shake'),
        },
      );
      _lastSOSTime = DateTime.now();
      _recentSosCount++;

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("📳 Shake SOS ✅: $result")));
    } catch (e) {
      debugPrint('❌ AUTO SOS exception: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("❌ SOS failed: $e")));
    } finally {
      if (mounted) setState(() => _sendingSOS = false);
    }
  }

  Future<void> _manualSOS() async {
    if (_sendingSOS) return;

    debugPrint('🚨 MANUAL SOS button pressed');
    setState(() => _sendingSOS = true);

    try {
      final auth = context.read<AuthService>();
      final user = auth.currentUser;
      if (user == null) return;

      await _startRecording();

      final sos = SOSService(uid: user.uid);
      final result = await sos.triggerSOS();
      _lastSOSTime = DateTime.now();
      _recentSosCount++;

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("🚨 SOS ✅: $result")));
    } catch (e) {
      debugPrint('❌ MANUAL SOS exception: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("❌ SOS failed: $e")));
    } finally {
      if (mounted) setState(() => _sendingSOS = false);
    }
  }

  Future<void> _showSuspiciousActivityDialog(AIRiskResult aiResult) async {
    if (!mounted) return;

    Timer? escalationTimer;
    escalationTimer = Timer(const Duration(seconds: 30), () {
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
                size: 30,
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
          content: const Text(
            'Unusual movement was detected. Please confirm you are safe.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'safe'),
              icon: const Icon(Icons.check_circle),
              label: const Text('I am Safe'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'emergency'),
              icon: const Icon(Icons.warning),
              label: const Text('SOS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    escalationTimer.cancel();

    if (response == 'safe') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks. Monitoring continues.'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    await _autoSOS(aiResult: aiResult);
  }

  Future<void> _startRecording() async {
    debugPrint('🎥 _startRecording() CALLED');

    try {
      final started = await _recordingService.startRecording();

      if (started) {
        debugPrint('✅ Recording started!');
        if (mounted) setState(() {});

        _recordingTimer?.cancel();
        _recordingTimer = Timer(
          const Duration(minutes: 10),
          () async => _stopRecording(),
        );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Recording failed: $error')));
    }
  }

  Future<void> _handleSavedRecording(String path) async {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Recording saved: ${path.split('/').last}')),
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
          const SnackBar(content: Text('✅ Recording uploaded to Firebase')),
        );
      }
    } catch (e) {
      debugPrint('❌ Upload error in home_screen: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Upload failed: $e')));
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
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

    autoTriggerTimer.cancel();

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
                        selectedTime = selectedTime.add(
                          const Duration(days: 1),
                        );
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('📞 Calling $name...')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Failed to make call')),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Call error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;

    if (user == null) {
      Future.microtask(() => Navigator.pushReplacementNamed(context, "/login"));
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    const background = Color(0xFFFFF8FB);
    const accent = Color(0xFFD9366E);
    const ink = Color(0xFF202A3B);

    return Scaffold(
      backgroundColor: background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        toolbarHeight: 88,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFF1D6E0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1FD9366E),
                blurRadius: 22,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Color(0xFFFCEAF0),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_outlined, color: accent),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Shrimati Setu",
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: ink,
                  ),
                ),
              ),
              if (_recordingService.isRecording)
                const Icon(
                  Icons.fiber_manual_record,
                  color: Colors.redAccent,
                  size: 18,
                ),
            ],
          ),
        ),
        actions: [
          Container(
            width: 48,
            height: 48,
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFF1D6E0)),
              boxShadow: const [
                BoxShadow(color: Color(0x1FD9366E), blurRadius: 18),
              ],
            ),
            child: IconButton(
              tooltip: 'Safety Menu',
              icon: const Icon(Icons.menu),
              onPressed: () {
                showGeneralDialog(
                  context: context,
                  barrierDismissible: true,
                  barrierLabel: 'Close safety menu',
                  barrierColor: const Color(0x3D202A3B),
                  transitionDuration: const Duration(milliseconds: 650),
                  pageBuilder: (context, animation, secondaryAnimation) => BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: FadeTransition(
                      opacity: CurvedAnimation(
                        parent: animation,
                        curve: const Interval(
                          0,
                          0.72,
                          curve: Curves.easeOutCubic,
                        ),
                        reverseCurve: Curves.easeInCubic,
                      ),
                      child: SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(0, -0.16),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                                reverseCurve: Curves.easeInCubic,
                              ),
                            ),
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.94, end: 1).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutBack,
                              reverseCurve: Curves.easeInCubic,
                            ),
                          ),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.pop(context),
                            child: Material(
                              color: const Color(0xFAFFF9FB),
                              child: SafeArea(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    22,
                                    24,
                                    26,
                                  ),
                                  child: ListTileTheme(
                                    data: ListTileThemeData(
                                      minVerticalPadding: 10,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 2,
                                          ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      tileColor: const Color(0xFFFFF1F6),
                                      textColor: const Color(0xFF202A3B),
                                    ),
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        return SingleChildScrollView(
                                          physics:
                                              const BouncingScrollPhysics(),
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              minHeight: constraints.maxHeight,
                                            ),
                                            child: IntrinsicHeight(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.shield_outlined,
                                                        color: Color(
                                                          0xFFD9366E,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      const Expanded(
                                                        child: Text(
                                                          'Safety Menu',
                                                          style: TextStyle(
                                                            fontSize: 26,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: Color(
                                                              0xFF202A3B,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      IconButton(
                                                        tooltip: 'Close',
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              context,
                                                            ),
                                                        icon: const Icon(
                                                          Icons.close_rounded,
                                                          size: 28,
                                                        ),
                                                        style:
                                                            IconButton.styleFrom(
                                                              backgroundColor:
                                                                  const Color(
                                                                    0xFFF8DEE7,
                                                                  ),
                                                              foregroundColor:
                                                                  const Color(
                                                                    0xFFD9366E,
                                                                  ),
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 18),
                                                  const Divider(
                                                    color: Color(0xFFF1D6E0),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  // Timer SOS card
                                                  _MenuEntrance(
                                                    animation: animation,
                                                    index: 0,
                                                    child: Card(
                                                      color: const Color(
                                                        0xFFFFF6F9,
                                                      ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              16,
                                                            ),
                                                      ),
                                                      child: ListTile(
                                                        leading: CircleAvatar(
                                                          backgroundColor:
                                                              _isTimerActive
                                                              ? Colors.orange
                                                              : Colors.grey,
                                                          child: Icon(
                                                            _isTimerActive
                                                                ? Icons.timer
                                                                : Icons
                                                                      .timer_off,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                        title: const Text(
                                                          'Timer SOS',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFF202A3B,
                                                            ),
                                                          ),
                                                        ),
                                                        subtitle: Text(
                                                          _isTimerActive
                                                              ? 'Active - Timer running'
                                                              : 'Start Safety Timer',
                                                          style: TextStyle(
                                                            color:
                                                                _isTimerActive
                                                                ? Colors.orange
                                                                : Color(
                                                                    0xFF667085,
                                                                  ),
                                                          ),
                                                        ),
                                                        trailing: ElevatedButton(
                                                          onPressed: () async {
                                                            Navigator.pop(
                                                              context,
                                                            );
                                                            if (_isTimerActive) {
                                                              await _timerSOSService
                                                                  ?.cancelTimer();
                                                              setState(
                                                                () =>
                                                                    _isTimerActive =
                                                                        false,
                                                              );
                                                              if (mounted) {
                                                                ScaffoldMessenger.of(
                                                                  context,
                                                                ).showSnackBar(
                                                                  const SnackBar(
                                                                    content: Text(
                                                                      '⏱️ Timer Cancelled',
                                                                    ),
                                                                    backgroundColor:
                                                                        Colors
                                                                            .orange,
                                                                  ),
                                                                );
                                                              }
                                                            } else {
                                                              _showTimerDialog();
                                                            }
                                                          },
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                _isTimerActive
                                                                ? Colors.red
                                                                : Colors.orange,
                                                            foregroundColor:
                                                                Colors.white,
                                                          ),
                                                          child: Text(
                                                            _isTimerActive
                                                                ? 'Cancel'
                                                                : 'Start',
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  _MenuEntrance(
                                                    animation: animation,
                                                    index: 1,
                                                    child: SwitchListTile(
                                                      secondary: Icon(
                                                        Icons.mic,
                                                        color: _isVoiceActive
                                                            ? Colors.green
                                                            : const Color(
                                                                0xFF98A2B3,
                                                              ),
                                                      ),
                                                      title: const Text(
                                                        'Voice Commands',
                                                        style: TextStyle(
                                                          color: Color(
                                                            0xFF202A3B,
                                                          ),
                                                        ),
                                                      ),
                                                      subtitle: Text(
                                                        _isVoiceActive
                                                            ? 'Listening for help words'
                                                            : 'Tap to enable',
                                                        style: const TextStyle(
                                                          color: Color(
                                                            0xFF667085,
                                                          ),
                                                        ),
                                                      ),
                                                      value: _isVoiceActive,
                                                      onChanged: (value) async {
                                                        Navigator.pop(context);
                                                        await _toggleVoiceCommands();
                                                      },
                                                    ),
                                                  ),
                                                  _MenuEntrance(
                                                    animation: animation,
                                                    index: 2,
                                                    child: ListTile(
                                                      leading: const Icon(
                                                        Icons.people,
                                                        color:
                                                            Colors.blueAccent,
                                                      ),
                                                      title: const Text(
                                                        'Emergency Contacts',
                                                        style: TextStyle(
                                                          color: Color(
                                                            0xFF202A3B,
                                                          ),
                                                        ),
                                                      ),
                                                      onTap: () {
                                                        Navigator.pop(context);
                                                        Navigator.pushNamed(
                                                          context,
                                                          '/contacts',
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                  _MenuEntrance(
                                                    animation: animation,
                                                    index: 3,
                                                    child: ListTile(
                                                      leading: const Icon(
                                                        Icons.security,
                                                        color:
                                                            Colors.pinkAccent,
                                                      ),
                                                      title: const Text(
                                                        'Safe Zones',
                                                        style: TextStyle(
                                                          color: Color(
                                                            0xFF202A3B,
                                                          ),
                                                        ),
                                                      ),
                                                      onTap: () {
                                                        Navigator.pop(context);
                                                        Navigator.pushNamed(
                                                          context,
                                                          '/safe_zones',
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                  _MenuEntrance(
                                                    animation: animation,
                                                    index: 4,
                                                    child: ListTile(
                                                      leading: const Icon(
                                                        Icons.video_library,
                                                        color:
                                                            Colors.orangeAccent,
                                                      ),
                                                      title: const Text(
                                                        'View Recordings',
                                                        style: TextStyle(
                                                          color: Color(
                                                            0xFF202A3B,
                                                          ),
                                                        ),
                                                      ),
                                                      onTap: () {
                                                        Navigator.pop(context);
                                                        Navigator.pushNamed(
                                                          context,
                                                          '/recordings',
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                  _MenuEntrance(
                                                    animation: animation,
                                                    index: 5,
                                                    child: ListTile(
                                                      leading: const Icon(
                                                        Icons.person,
                                                        color:
                                                            Colors.greenAccent,
                                                      ),
                                                      title: const Text(
                                                        'Edit Profile',
                                                        style: TextStyle(
                                                          color: Color(
                                                            0xFF202A3B,
                                                          ),
                                                        ),
                                                      ),
                                                      onTap: () {
                                                        Navigator.pop(context);
                                                        Navigator.pushNamed(
                                                          context,
                                                          '/profile',
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                  Divider(
                                                    color: Color(0xFFF1D6E0),
                                                  ),
                                                  _MenuEntrance(
                                                    animation: animation,
                                                    index: 6,
                                                    child: ListTile(
                                                      leading: const Icon(
                                                        Icons.logout,
                                                        color: Colors.redAccent,
                                                      ),
                                                      title: const Text(
                                                        'Logout',
                                                        style: TextStyle(
                                                          color:
                                                              Colors.redAccent,
                                                          fontWeight:
                                                              FontWeight.w600,
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
                                                  ),
                                                  const SizedBox(height: 8),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: const Color(0xFFF8EEF2),
            child: _currentPosition == null
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: accent),
                        SizedBox(height: 16),
                        Text(
                          'Locking on to your location...',
                          style: TextStyle(
                            color: Color(0xFF667085),
                            fontWeight: FontWeight.w500,
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
                    circles: {
                      Circle(
                        circleId: const CircleId('pulse'),
                        center: LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        ),
                        radius: _pulseAnimation?.value ?? 0,
                        fillColor: accent.withOpacity(
                          (1.0 - (_pulseController?.value ?? 0.0)).clamp(
                                0.0,
                                1.0,
                              ) *
                              0.3,
                        ),
                        strokeWidth: 1,
                        strokeColor: accent.withOpacity(
                          (1.0 - (_pulseController?.value ?? 0.0)).clamp(
                            0.0,
                            1.0,
                          ),
                        ),
                      ),
                    },
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
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFF1D6E0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x260B1220),
                      blurRadius: 30,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7CCD6),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SafetyStatusBanner(
                      isAnalyzing: _analyzingRisk,
                      result: _lastAIRiskResult,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _BottomAction(
                          label: _recordingService.isRecording
                              ? 'Stop'
                              : 'Record',
                          icon: _recordingService.isRecording
                              ? Icons.stop_circle
                              : Icons.videocam,
                          color: _recordingService.isRecording
                              ? Colors.redAccent
                              : const Color(0xFF667085),
                          onTap: () async {
                            if (_recordingService.isRecording) {
                              await _stopRecording();
                            } else {
                              await _startRecording();
                            }
                          },
                        ),
                        GestureDetector(
                          onTap: _manualSOS,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  color: _sendingSOS ? Colors.grey : accent,
                                  shape: BoxShape.circle,
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x59D9366E),
                                      blurRadius: 22,
                                      offset: Offset(0, 8),
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
                                          'SOS',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 2,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              const Text(
                                'SOS',
                                style: TextStyle(
                                  color: ink,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _BottomAction(
                          label: 'Call',
                          icon: Icons.phone,
                          color: const Color(0xFF3AA981),
                          onTap: _triggerRealCall,
                        ),
                        _BottomAction(
                          label: 'Profile',
                          icon: Icons.person,
                          color: const Color(0xFF5476A8),
                          onTap: () {
                            Navigator.pushNamed(context, '/profile');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuEntrance extends StatelessWidget {
  final Animation<double> animation;
  final int index;
  final Widget child;

  const _MenuEntrance({
    required this.animation,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final start = (0.12 + index * 0.075).clamp(0.0, 0.72);
    final itemAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(start, 1, curve: Curves.easeOutBack),
      reverseCurve: const Interval(0, 0.76, curve: Curves.easeInCubic),
    );

    return FadeTransition(
      opacity: itemAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.22),
          end: Offset.zero,
        ).animate(itemAnimation),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: child,
        ),
      ),
    );
  }
}

class _SafetyStatusBanner extends StatelessWidget {
  final bool isAnalyzing;
  final AIRiskResult? result;

  const _SafetyStatusBanner({required this.isAnalyzing, required this.result});

  @override
  Widget build(BuildContext context) {
    final level = result?.level ?? AIRiskLevel.lowRisk;
    final statusColor = isAnalyzing
        ? Colors.blueAccent
        : switch (level) {
            AIRiskLevel.lowRisk => const Color(0xFF3AA981),
            AIRiskLevel.suspicious => Colors.orangeAccent,
            AIRiskLevel.highRisk => Colors.redAccent,
          };
    final icon = isAnalyzing
        ? Icons.radar
        : switch (level) {
            AIRiskLevel.lowRisk => Icons.check_circle,
            AIRiskLevel.suspicious => Icons.warning_amber_rounded,
            AIRiskLevel.highRisk => Icons.emergency,
          };
    final label = isAnalyzing ? 'Checking Activity' : level.userLabel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6F9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1D6E0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: statusColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF202A3B),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
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
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2F6),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF475467),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
