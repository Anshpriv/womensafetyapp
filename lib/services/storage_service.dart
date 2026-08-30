import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  StorageService({required this.uid});

  Future<RecordingUploadResult> uploadRecording(String localPath) async {
    final file = File(localPath);
    if (!await file.exists()) {
      debugPrint('❌ Recording file not found at: $localPath');
      throw Exception('Recording file not found');
    }

    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'recording.mp4';
    final dateFolder = _extractDateFolder(file);
    final storagePath = '$uid/$dateFolder/$fileName';

    debugPrint('🚀 Starting upload to Supabase Storage: $storagePath');

    try {
      // Upload to Supabase Storage bucket ('recordings')
      await Supabase.instance.client.storage.from('recordings').upload(
            storagePath,
            file,
            fileOptions: const FileOptions(
              contentType: 'video/mp4',
              upsert: true,
            ),
          );

      final downloadUrl = Supabase.instance.client.storage
          .from('recordings')
          .getPublicUrl(storagePath);

      debugPrint('✅ Supabase upload successful! URL: $downloadUrl');

      await DatabaseService(uid: uid).saveRecordingMetadata(
        fileName: fileName,
        downloadUrl: downloadUrl,
        storagePath: storagePath,
        fileSizeBytes: await file.length(),
        recordedAt: DateTime.now().toIso8601String(),
      );

      debugPrint('💾 Recording metadata saved to Firestore');

      return RecordingUploadResult(
        downloadUrl: downloadUrl,
        storagePath: storagePath,
      );
    } catch (e, stack) {
      debugPrint('❌ Supabase upload ERROR: $e');
      debugPrint('📌 Stack trace: $stack');
      rethrow;
    }
  }

  Future<String> uploadProfilePhoto(File file) async {
    if (!await file.exists()) {
      throw Exception('Photo file not found');
    }

    final storagePath = 'profile_photos/$uid.jpg';

    debugPrint('🚀 Uploading profile photo to Supabase: $storagePath');

    await Supabase.instance.client.storage.from('recordings').upload(
          storagePath,
          file,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    final downloadUrl = Supabase.instance.client.storage
        .from('recordings')
        .getPublicUrl(storagePath);

    debugPrint('✅ Profile photo uploaded! URL: $downloadUrl');

    await DatabaseService(uid: uid).updateProfilePhoto(downloadUrl);

    return downloadUrl;
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
