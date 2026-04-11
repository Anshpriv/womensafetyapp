import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class RecordingService {
  static const MethodChannel _dualCameraChannel =
      MethodChannel('dual_camera_channel');

  CameraController? _controller;
  bool _isRecording = false;
  String? _currentVideoPath;
  bool _isDualRecordingActive = false;

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

  Future<bool> _canUseDualRecording() async {
    if (!Platform.isAndroid) return false;

    try {
      final supported = await _dualCameraChannel.invokeMethod<bool>(
        'isDualRecordingSupported',
      );
      return supported ?? false;
    } catch (e) {
      debugPrint('⚠️ Dual camera support check failed: $e');
      return false;
    }
  }

  Future<Directory> _getRecordingsRootDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final recordingsRoot = Directory('${directory.path}${Platform.pathSeparator}recordings');

    if (!await recordingsRoot.exists()) {
      await recordingsRoot.create(recursive: true);
    }

    return recordingsRoot;
  }

  Future<String> _buildRecordingPath() async {
    final now = DateTime.now();
    final recordingsRoot = await _getRecordingsRootDirectory();
    final dateFolderName =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final datedDirectory = Directory(
      '${recordingsRoot.path}${Platform.pathSeparator}$dateFolderName',
    );

    if (!await datedDirectory.exists()) {
      await datedDirectory.create(recursive: true);
    }

    final modeLabel = _isDualRecordingActive ? 'dual' : 'back';
    final fileName =
        'sos_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}_$modeLabel.mp4';

    return '${datedDirectory.path}${Platform.pathSeparator}$fileName';
  }

  CameraDescription? _selectCamera(List<CameraDescription> cameras) {
    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.back) {
        return camera;
      }
    }

    return cameras.isNotEmpty ? cameras.first : null;
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

      final camera = _selectCamera(cameras);
      if (camera == null) {
        debugPrint('❌ No suitable camera found!');
        return false;
      }

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
      if (await _canUseDualRecording()) {
        _isDualRecordingActive = true;
        final path = await _buildRecordingPath();
        final started = await _dualCameraChannel.invokeMethod<bool>(
          'startDualRecording',
          {'outputPath': path},
        );

        if (started == true) {
          _isRecording = true;
          _currentVideoPath = path;
          debugPrint('✅ Native dual recording launched');
          return true;
        }

        _isDualRecordingActive = false;
      }

      final path = await _buildRecordingPath();
      
      debugPrint('📁 Save path: $path');
      debugPrint('🎥 Starting video recording...');
      
      await _controller!.startVideoRecording();
      
      _isRecording = true;
      _isDualRecordingActive = false;
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
      if (_isDualRecordingActive) {
        try {
          await _dualCameraChannel.invokeMethod<bool>('stopDualRecording');
          return _currentVideoPath;
        } catch (e) {
          debugPrint('❌ Dual stop failed: $e');
          return null;
        }
      }

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

  Future<String?> consumeCompletedRecording() async {
    if (!Platform.isAndroid) return null;

    try {
      final path = await _dualCameraChannel.invokeMethod<String>(
        'consumeLastRecordingPath',
      );

      if (path != null && path.isNotEmpty) {
        _isRecording = false;
        _isDualRecordingActive = false;
        _currentVideoPath = null;
        return path;
      }

      return null;
    } catch (e) {
      debugPrint('⚠️ Failed to consume completed recording: $e');
      return null;
    }
  }

  Future<String?> consumeRecordingError() async {
    if (!Platform.isAndroid) return null;

    try {
      return await _dualCameraChannel.invokeMethod<String>(
        'consumeLastRecordingError',
      );
    } catch (e) {
      debugPrint('⚠️ Failed to consume recording error: $e');
      return null;
    }
  }

  Future<bool> refreshRecordingState() async {
    if (!_isDualRecordingActive || !Platform.isAndroid) return false;

    try {
      final isActive = await _dualCameraChannel.invokeMethod<bool>(
        'isDualRecordingActive',
      );

      if (isActive == false) {
        _isRecording = false;
        _isDualRecordingActive = false;
        _currentVideoPath = null;
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to refresh recording state: $e');
    }

    return false;
  }

  // ✅ Get saved recordings with logs
  static Future<List<File>> getSavedRecordings() async {
    try {
      debugPrint('📂 Getting saved recordings...');
      final directory = await getApplicationDocumentsDirectory();
      final recordingsRoot = Directory(
        '${directory.path}${Platform.pathSeparator}recordings',
      );

      debugPrint('📂 Directory: ${recordingsRoot.path}');
      if (!await recordingsRoot.exists()) {
        return [];
      }

      final files = recordingsRoot
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) => f.path.endsWith('.mp4') && f.path.contains('sos_'),
          )
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

      await _cleanupEmptyRecordingFolders();
    } catch (e) {
      debugPrint('❌ Cleanup failed: $e');
    }
  }

  static Future<void> cleanupAfterDeletion(File file) async {
    try {
      await file.delete();
      await _cleanupEmptyRecordingFolders();
    } catch (e) {
      debugPrint('❌ Cleanup after deletion failed: $e');
      rethrow;
    }
  }

  static Future<void> _cleanupEmptyRecordingFolders() async {
    final directory = await getApplicationDocumentsDirectory();
    final recordingsRoot = Directory(
      '${directory.path}${Platform.pathSeparator}recordings',
    );

    if (!await recordingsRoot.exists()) return;

    final datedDirectories = recordingsRoot
        .listSync()
        .whereType<Directory>()
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final datedDirectory in datedDirectories) {
      if (datedDirectory.listSync().isEmpty) {
        await datedDirectory.delete();
        debugPrint('🗑️ Deleted empty folder: ${datedDirectory.path}');
      }
    }
  }
}
