import 'dart:async';
import 'package:flutter/material.dart';
import 'package:volume_controller/volume_controller.dart';
import 'sos_service.dart';

class PowerButtonService {
  final VolumeController _volumeController = VolumeController();
  StreamSubscription? _volumeSubscription;
  
  final String uid;
  final Function()? onSOSTriggered;
  
  int _pressCount = 0;
  DateTime _lastPressTime = DateTime.now();
  Timer? _resetTimer;
  
  PowerButtonService({
    required this.uid,
    this.onSOSTriggered,
  });

  // ✅ Start monitoring power button (via volume buttons)
  Future<void> startMonitoring() async {
    try {
      // Listen to volume changes (alternative to power button)
      _volumeSubscription = _volumeController.listener((volume) {
        _handleVolumePress();
      });
      
      debugPrint('✅ Power button monitoring started');
    } catch (e) {
      debugPrint('❌ Power button error: $e');
    }
  }

  // ✅ Handle volume button press (simulates power button)
  void _handleVolumePress() {
    final now = DateTime.now();
    
    // Reset if more than 3 seconds since last press
    if (now.difference(_lastPressTime).inSeconds > 3) {
      _pressCount = 0;
    }
    
    _pressCount++;
    _lastPressTime = now;
    
    debugPrint('🔘 Button press: $_pressCount/5');
    
    // Trigger SOS after 5 presses
    if (_pressCount >= 5) {
      debugPrint('🚨 5 PRESSES DETECTED! Triggering SOS');
      _triggerSOS();
      _pressCount = 0;
    }
    
    // Auto-reset after 3 seconds
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 3), () {
      _pressCount = 0;
    });
  }

  // ✅ Trigger SOS
  Future<void> _triggerSOS() async {
    try {
      final sos = SOSService(uid: uid);
      await sos.triggerSOS();
      onSOSTriggered?.call();
    } catch (e) {
      debugPrint('❌ Power button SOS error: $e');
    }
  }

  // ✅ Stop monitoring
  void stopMonitoring() {
    _volumeSubscription?.cancel();
    _resetTimer?.cancel();
    debugPrint('🔘 Power button monitoring stopped');
  }

  // ✅ Dispose
  void dispose() {
    stopMonitoring();
  }
}
