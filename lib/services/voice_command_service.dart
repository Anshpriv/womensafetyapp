import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'sos_service.dart';
import 'call_service.dart';

class VoiceCommandService {
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  bool _shouldKeepListening = false;
  final String uid;
  
  final Function()? onSOSTriggered;
  final Function()? onRecordingStarted;
  final Function()? onPoliceCall;
  
  VoiceCommandService({
    required this.uid,
    this.onSOSTriggered,
    this.onRecordingStarted,
    this.onPoliceCall,
  });

  Future<bool> initialize() async {
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        debugPrint('❌ Microphone permission denied');
        return false;
      }

      final available = await _speech.initialize(
        onError: (error) {
          debugPrint('⚠️ Speech error: $error');
          _isListening = false;
          
          if (_shouldKeepListening) {
            Future.delayed(const Duration(seconds: 2), () {
              if (_shouldKeepListening && !_isListening) {
                debugPrint('🔄 Auto-restarting voice listener...');
                startListening();
              }
            });
          }
        },
        onStatus: (status) {
          debugPrint('🎤 Speech status: $status');
          
          if ((status == 'done' || status == 'notListening') && _shouldKeepListening) {
            _isListening = false;
            Future.delayed(const Duration(seconds: 1), () {
              if (_shouldKeepListening && !_isListening) {
                debugPrint('🔄 Restarting voice listener...');
                startListening();
              }
            });
          }
        },
      );

      if (available) {
        debugPrint('✅ Voice commands initialized');
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ Voice init error: $e');
      return false;
    }
  }

  Future<void> startListening() async {
    if (_isListening) return;
    
    try {
      _shouldKeepListening = true;
      _isListening = true;
      
      await _speech.listen(
        onResult: (result) {
          final text = result.recognizedWords.toLowerCase();
          if (text.isNotEmpty) {
            debugPrint('🎤 Heard: $text');
            _processCommand(text);
          }
        },
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 5),
        partialResults: false,
        cancelOnError: false,
        listenFor: const Duration(seconds: 30),
        onSoundLevelChange: (_) {},
      );
      
      debugPrint('🎤 Voice listening started (SILENT)');
    } catch (e) {
      debugPrint('❌ Listen error: $e');
      _isListening = false;
      
      if (_shouldKeepListening) {
        Future.delayed(const Duration(seconds: 2), () {
          if (_shouldKeepListening) {
            startListening();
          }
        });
      }
    }
  }

  Future<void> stopListening() async {
    debugPrint('🛑 Stopping voice commands...');
    _shouldKeepListening = false;
    _isListening = false;
    
    try {
      await _speech.stop();
      await _speech.cancel();  // ✅ Force cancel
      debugPrint('✅ Voice listening stopped');
    } catch (e) {
      debugPrint('❌ Stop error: $e');
    }
  }

  void _processCommand(String text) {
    if (text.contains('help me') || 
        text.contains('help') || 
        text.contains('emergency') ||
        text.contains('bachao') ||
        text.contains('मदद')) {
      debugPrint('🚨 "HELP ME" DETECTED!');
      _triggerSOS();
    }
    else if (text.contains('call police') || 
             text.contains('police') ||
             text.contains('police bulao') ||
             text.contains('पुलिस')) {
      debugPrint('📞 "CALL POLICE" DETECTED!');
      _callPolice();
    }
    else if (text.contains('start recording') || 
             text.contains('record') ||
             text.contains('recording shuru') ||
             text.contains('रिकॉर्डिंग')) {
      debugPrint('🎥 "START RECORDING" DETECTED!');
      _startRecording();
    }
  }

  Future<void> _triggerSOS() async {
    try {
      final sos = SOSService(uid: uid);
      await sos.triggerSOS();
      onSOSTriggered?.call();
    } catch (e) {
      debugPrint('❌ Voice SOS error: $e');
    }
  }

  Future<void> _callPolice() async {
    try {
      await CallService.makeCall('100');
      onPoliceCall?.call();
    } catch (e) {
      debugPrint('❌ Voice call error: $e');
    }
  }

  void _startRecording() {
    onRecordingStarted?.call();
  }

  bool get isListening => _isListening;

  void dispose() {
    debugPrint('🗑️ Disposing voice service...');
    _shouldKeepListening = false;
    _speech.stop();
    _speech.cancel();
  }
}
