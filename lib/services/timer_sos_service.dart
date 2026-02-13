import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'sos_service.dart';

class TimerSOSService {
  final String uid;
  Timer? _checkTimer;
  static const String _timerKey = 'timer_sos_time';
  static const String _activeKey = 'timer_sos_active';
  
  // ✅ NEW: Callback for showing check-in dialog
  final Function()? onTimerExpired;

  TimerSOSService({
    required this.uid,
    this.onTimerExpired,
  });

  Future<bool> isTimerActive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isActive = prefs.getBool(_activeKey) ?? false;
      final savedTime = prefs.getString(_timerKey);

      if (!isActive || savedTime == null) return false;

      final targetTime = DateTime.parse(savedTime);
      final now = DateTime.now();

      if (now.isAfter(targetTime)) {
        await _handleTimerExpired();
        return false;
      }

      _startMonitoring(targetTime);
      return true;
    } catch (e) {
      debugPrint('❌ isTimerActive error: $e');
      return false;
    }
  }

  Future<void> setTimer(DateTime targetTime) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_timerKey, targetTime.toIso8601String());
      await prefs.setBool(_activeKey, true);

      debugPrint('⏱️ Timer set for: $targetTime');
      _startMonitoring(targetTime);
    } catch (e) {
      debugPrint('❌ setTimer error: $e');
    }
  }

  // ✅ NEW: User checks in - I'm safe!
  Future<void> checkIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_timerKey);
      await prefs.setBool(_activeKey, false);

      _checkTimer?.cancel();
      _checkTimer = null;

      debugPrint('✅ User checked in - Timer cancelled');
    } catch (e) {
      debugPrint('❌ checkIn error: $e');
    }
  }

  Future<void> cancelTimer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_timerKey);
      await prefs.setBool(_activeKey, false);

      _checkTimer?.cancel();
      _checkTimer = null;

      debugPrint('⏱️ Timer cancelled');
    } catch (e) {
      debugPrint('❌ cancelTimer error: $e');
    }
  }

  // ✅ Get remaining time
  Future<Duration?> getRemainingTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTime = prefs.getString(_timerKey);
      
      if (savedTime == null) return null;

      final targetTime = DateTime.parse(savedTime);
      final now = DateTime.now();
      
      if (now.isAfter(targetTime)) return Duration.zero;
      
      return targetTime.difference(now);
    } catch (e) {
      return null;
    }
  }

  void _startMonitoring(DateTime targetTime) {
    _checkTimer?.cancel();

    _checkTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      final now = DateTime.now();

      if (now.isAfter(targetTime)) {
        timer.cancel();
        await _handleTimerExpired();
      } else {
        final remaining = targetTime.difference(now);
        debugPrint('⏱️ Remaining: ${remaining.inMinutes} min');
      }
    });

    debugPrint('⏱️ Monitoring started');
  }

  // ✅ NEW: Handle timer expiration - Show check-in dialog
  Future<void> _handleTimerExpired() async {
    debugPrint('⏱️ TIMER EXPIRED - Waiting for check-in...');
    
    // Notify home screen to show check-in dialog
    onTimerExpired?.call();
  }

  // ✅ Trigger SOS (called from home screen if user doesn't check in)
  Future<void> triggerTimerSOS() async {
    try {
      debugPrint('🚨 Triggering Timer SOS!');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_activeKey, false);
      await prefs.remove(_timerKey);

      final sos = SOSService(uid: uid);
      await sos.triggerSOS();

      debugPrint('✅ Timer SOS triggered');
    } catch (e) {
      debugPrint('❌ Timer SOS error: $e');
    }
  }

  void dispose() {
    _checkTimer?.cancel();
    debugPrint('🗑️ TimerSOSService disposed');
  }
}
