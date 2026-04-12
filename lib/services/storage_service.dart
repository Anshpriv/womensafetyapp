import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import 'database_service.dart';

class RecordingUploadResult {
  final String downloadUrl;
  final String storagePath;

  const RecordingUploadResult({
    required this.downloadUrl,
    required this.storagePath,
  });
}

class StorageService {
  final String uid;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  StorageService({required this.uid});

  Future<RecordingUploadResult> uploadRecording(String localPath) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('Recording file not found');
    }

    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'recording.mp4';
    final dateFolder = _extractDateFolder(file);
    final storagePath = 'recordings/$uid/$dateFolder/$fileName';

    final ref = _storage.ref().child(storagePath);
    await ref.putFile(
      file,
      SettableMetadata(contentType: 'video/mp4'),
    );

    final downloadUrl = await ref.getDownloadURL();

    await DatabaseService(uid: uid).saveRecordingMetadata(
      fileName: fileName,
      downloadUrl: downloadUrl,
      storagePath: storagePath,
      fileSizeBytes: await file.length(),
      recordedAt: DateTime.now().toIso8601String(),
    );

    return RecordingUploadResult(
      downloadUrl: downloadUrl,
      storagePath: storagePath,
    );
  }

  String _extractDateFolder(File file) {
    final segments = file.path.split(Platform.pathSeparator);
    final recordingsIndex = segments.lastIndexOf('recordings');

    if (recordingsIndex >= 0 && recordingsIndex + 1 < segments.length) {
      return segments[recordingsIndex + 1];
    }

    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
