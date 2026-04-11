import 'dart:io';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class RecordingService {
  CameraController? _controller;
  bool _isRecording = false;
  String? _currentVideoPath;

  bool get isRecording => _isRecording;
  String? get currentVideoPath => _currentVideoPath;

  // ✅ Request permissions with detailed logs
  Future<bool> requestPermissions() async {
    debugPrint('🔐 Requesting permissions...');
    
    final cameraStatus = await Permission.camera.request();
    debugPrint('📷 Camera permission: $cameraStatus');
    
    final micStatus = await Permission.microphone.request();
    debugPrint('🎤 Microphone permission: $micStatus');
    
    final storageStatus = await Permission.storage.request();
    debugPrint('💾 Storage permission: $storageStatus');

    final granted = cameraStatus.isGranted && micStatus.isGranted;
    debugPrint('✅ All permissions granted: $granted');
    
    if (!granted) {
      debugPrint('❌ Permission denied - Camera: $cameraStatus, Mic: $micStatus');
    }
    
    return granted;
  }

  // ✅ Initialize camera with detailed logs
  Future<bool> initializeCamera() async {
    try {
      debugPrint('📸 Getting available cameras...');
      final cameras = await availableCameras();
      debugPrint('📸 Found ${cameras.length} cameras');
      
      if (cameras.isEmpty) {
        debugPrint('❌ No cameras found!');
        return false;
      }

      // Use back camera (index 0)
      final camera = cameras.first;
      debugPrint('📸 Using camera: ${camera.name} (${camera.lensDirection})');

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: true,
      );

      debugPrint('📸 Initializing camera controller...');
      await _controller!.initialize();
      debugPrint('✅ Camera initialized successfully!');
      debugPrint('📸 Camera size: ${_controller!.value.previewSize}');
      
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ Camera init failed: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      return false;
    }
  }

  // ✅ Start recording with detailed logs
  Future<bool> startRecording() async {
    debugPrint('🎬 startRecording() called');
    
    if (_controller == null || !_controller!.value.isInitialized) {
      debugPrint('🎬 Controller not initialized, requesting permissions...');
      
      final permOk = await requestPermissions();
      if (!permOk) {
        debugPrint('❌ Permissions denied!');
        return false;
      }

      debugPrint('🎬 Permissions OK, initializing camera...');
      final initOk = await initializeCamera();
      if (!initOk) {
        debugPrint('❌ Camera initialization failed!');
        return false;
      }
    }

    if (_isRecording) {
      debugPrint('⚠️ Already recording!');
      return false;
    }

    try {
      debugPrint('📁 Getting app directory...');
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${directory.path}/sos_$timestamp.mp4';
      
      debugPrint('📁 Save path: $path');
      debugPrint('🎥 Starting video recording...');
      
      await _controller!.startVideoRecording();
      
      _isRecording = true;
      _currentVideoPath = path;

      debugPrint('✅ Recording started successfully!');
      debugPrint('🎥 Recording to: $path');
      
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ Start recording failed: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      return false;
    }
  }

  // ✅ Stop recording with detailed logs
  Future<String?> stopRecording() async {
    debugPrint('⏹️ stopRecording() called');
    
    if (!_isRecording || _controller == null) {
      debugPrint('⚠️ Not recording or controller null');
      return null;
    }

    try {
      debugPrint('⏹️ Stopping video recording...');
      final file = await _controller!.stopVideoRecording();
      _isRecording = false;

      debugPrint('📁 Temp file path: ${file.path}');
      debugPrint('📁 Target path: $_currentVideoPath');

      // Move to permanent location
      if (_currentVideoPath != null) {
        final newFile = File(_currentVideoPath!);
        debugPrint('📁 Copying file to permanent location...');
        
        await File(file.path).copy(newFile.path);
        await File(file.path).delete();

        final exists = await newFile.exists();
        final size = await newFile.length();
        
        debugPrint('✅ File saved: ${newFile.path}');
        debugPrint('✅ File exists: $exists');
        debugPrint('✅ File size: ${size} bytes');
        
        return _currentVideoPath;
      }

      return file.path;
    } catch (e, stackTrace) {
      debugPrint('❌ Stop recording failed: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      _isRecording = false;
      return null;
    }
  }

  // ✅ Dispose
  void dispose() {
    debugPrint('🗑️ Disposing camera controller');
    _controller?.dispose();
    _controller = null;
  }

  // ✅ Get saved recordings with logs
  static Future<List<File>> getSavedRecordings() async {
    try {
      debugPrint('📂 Getting saved recordings...');
      final directory = await getApplicationDocumentsDirectory();
      debugPrint('📂 Directory: ${directory.path}');
      
      final files = directory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.mp4') && f.path.contains('sos_'))
          .toList();

      debugPrint('📂 Found ${files.length} recordings');
      
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      return files;
    } catch (e) {
      debugPrint('❌ Get recordings failed: $e');
      return [];
    }
  }

  // ✅ Cleanup
  static Future<void> cleanupOldRecordings() async {
    try {
      final files = await getSavedRecordings();
      if (files.length <= 10) return;

      debugPrint('🗑️ Cleaning up old recordings...');
      for (var i = 10; i < files.length; i++) {
        await files[i].delete();
        debugPrint('🗑️ Deleted: ${files[i].path}');
      }
    } catch (e) {
      debugPrint('❌ Cleanup failed: $e');
    }
  }
}
