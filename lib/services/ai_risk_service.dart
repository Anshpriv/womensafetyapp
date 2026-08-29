import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum AIRiskLevel { lowRisk, suspicious, highRisk }

extension AIRiskLevelLabel on AIRiskLevel {
  String get storageValue {
    switch (this) {
      case AIRiskLevel.lowRisk:
        return 'LOW_RISK';
      case AIRiskLevel.suspicious:
        return 'SUSPICIOUS';
      case AIRiskLevel.highRisk:
        return 'HIGH_RISK';
    }
  }

  String get userLabel {
    switch (this) {
      case AIRiskLevel.lowRisk:
        return 'Normal Activity';
      case AIRiskLevel.suspicious:
        return 'Suspicious Activity';
      case AIRiskLevel.highRisk:
        return 'High-Risk Activity';
    }
  }

  static AIRiskLevel fromStorageValue(String value) {
    switch (value.toUpperCase()) {
      case 'LOW_RISK':
        return AIRiskLevel.lowRisk;
      case 'SUSPICIOUS':
        return AIRiskLevel.suspicious;
      case 'HIGH_RISK':
        return AIRiskLevel.highRisk;
      default:
        throw FormatException('Invalid AI risk level: $value');
    }
  }
}

class MovementSample {
  final double x;
  final double y;
  final double z;
  final double magnitude;
  final DateTime timestamp;

  const MovementSample({
    required this.x,
    required this.y,
    required this.z,
    required this.magnitude,
    required this.timestamp,
  });
}

class AIRiskContext {
  final String triggerType;
  final int shakeCount;
  final double shakeIntensity;
  final int shakeDurationMs;
  final double movementVariance;
  final double movementFrequency;
  final double speed;
  final double accuracy;
  final bool locationAvailable;
  final bool geofenceViolation;
  final bool distressVoiceDetected;
  final int recentAutomaticTriggerCount;
  final int recentSosCount;
  final int secondsSincePreviousTrigger;
  final DateTime timestamp;

  const AIRiskContext({
    required this.triggerType,
    required this.shakeCount,
    required this.shakeIntensity,
    required this.shakeDurationMs,
    required this.movementVariance,
    required this.movementFrequency,
    required this.speed,
    required this.accuracy,
    required this.locationAvailable,
    required this.geofenceViolation,
    required this.distressVoiceDetected,
    required this.recentAutomaticTriggerCount,
    required this.recentSosCount,
    required this.secondsSincePreviousTrigger,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'trigger_type': triggerType,
      'shake_count': shakeCount,
      'shake_intensity': shakeIntensity,
      'shake_duration_ms': shakeDurationMs,
      'movement_variance': movementVariance,
      'movement_frequency': movementFrequency,
      'speed': speed,
      'accuracy': accuracy,
      'location_available': locationAvailable ? 1 : 0,
      'geofence_violation': geofenceViolation ? 1 : 0,
      'distress_voice_detected': distressVoiceDetected ? 1 : 0,
      'recent_automatic_trigger_count': recentAutomaticTriggerCount,
      'recent_sos_count': recentSosCount,
      'seconds_since_previous_trigger': secondsSincePreviousTrigger,
      'hour_of_day': timestamp.hour,
    };
  }
}

class AIRiskResult {
  final AIRiskLevel level;
  final double score;
  final String modelVersion;
  final String source;
  final String reason;
  final DateTime analyzedAt;
  final Map<String, dynamic> features;

  const AIRiskResult({
    required this.level,
    required this.score,
    required this.modelVersion,
    required this.source,
    required this.reason,
    required this.analyzedAt,
    required this.features,
  });

  Map<String, dynamic> toFirestore({required String triggerType}) {
    return {
      'ai_risk_level': level.storageValue,
      'ai_risk_score': score,
      'ai_model_version': modelVersion,
      'ai_analysis_timestamp': analyzedAt.toIso8601String(),
      'ai_trigger_type': triggerType,
      'ai_analysis_source': source,
      'ai_reason': reason,
    };
  }
}

class AIRiskService {
  static const String modelVersion = 'mobile-context-risk-v1';
  static const Duration defaultTimeout = Duration(seconds: 3);

  final Uri? inferenceEndpoint;
  final Duration timeout;

  AIRiskService({String? inferenceUrl, this.timeout = defaultTimeout})
    : inferenceEndpoint = inferenceUrl == null || inferenceUrl.trim().isEmpty
          ? null
          : Uri.tryParse(inferenceUrl.trim());

  static AIRiskContext buildShakeContext({
    required List<MovementSample> samples,
    required int shakeCount,
    required Position? position,
    required int recentAutomaticTriggerCount,
    required int recentSosCount,
    required int secondsSincePreviousTrigger,
    bool geofenceViolation = false,
    bool distressVoiceDetected = false,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();
    final magnitudes = samples.map((sample) => sample.magnitude).toList();
    final maxMagnitude = magnitudes.isEmpty ? 0.0 : magnitudes.reduce(max);
    final variance = _variance(magnitudes);
    final durationMs = samples.length < 2
        ? 0
        : samples.last.timestamp
              .difference(samples.first.timestamp)
              .inMilliseconds;
    final durationSeconds = max(durationMs, 1) / 1000.0;

    return AIRiskContext(
      triggerType: 'shake',
      shakeCount: shakeCount,
      shakeIntensity: double.parse(maxMagnitude.toStringAsFixed(3)),
      shakeDurationMs: durationMs,
      movementVariance: double.parse(variance.toStringAsFixed(3)),
      movementFrequency: double.parse(
        (samples.length / durationSeconds).toStringAsFixed(3),
      ),
      speed: position?.speed ?? 0.0,
      accuracy: position?.accuracy ?? 0.0,
      locationAvailable: position != null,
      geofenceViolation: geofenceViolation,
      distressVoiceDetected: distressVoiceDetected,
      recentAutomaticTriggerCount: recentAutomaticTriggerCount,
      recentSosCount: recentSosCount,
      secondsSincePreviousTrigger: secondsSincePreviousTrigger,
      timestamp: now,
    );
  }

  Future<AIRiskResult> analyze(AIRiskContext context) async {
    if (inferenceEndpoint != null &&
        (inferenceEndpoint!.scheme == 'http' ||
            inferenceEndpoint!.scheme == 'https')) {
      try {
        return await _analyzeRemotely(context).timeout(timeout);
      } catch (e) {
        debugPrint('AI risk remote analysis unavailable: $e');
      }
    }

    return analyzeLocally(context);
  }

  AIRiskResult analyzeLocally(AIRiskContext context) {
    final features = context.toJson();
    var score = 0.0;
    final reasons = <String>[];

    if (context.shakeCount >= 5) {
      score += 0.22;
      reasons.add('repeated shake pattern');
    }
    if (context.shakeIntensity >= 22) {
      score += 0.18;
      reasons.add('high shake intensity');
    } else if (context.shakeIntensity >= 18) {
      score += 0.1;
      reasons.add('elevated shake intensity');
    }
    if (context.movementVariance >= 45) {
      score += 0.25;
      reasons.add('irregular movement variance');
    }
    if (context.speed >= 12) {
      score += 0.14;
      reasons.add('rapid movement');
    }
    if (context.geofenceViolation) {
      score += 0.3;
      reasons.add('safe-zone boundary risk');
    }
    if (context.distressVoiceDetected) {
      score += 0.28;
      reasons.add('distress voice indicator');
    }
    if (context.recentAutomaticTriggerCount >= 2) {
      score += 0.18;
      reasons.add('recent automatic triggers');
    }
    if (context.recentSosCount > 0) {
      score += 0.12;
      reasons.add('recent SOS activity');
    }
    if (!context.locationAvailable) {
      score += 0.05;
      reasons.add('location unavailable');
    }

    final normalizedScore = score.clamp(0.0, 1.0);
    final level = normalizedScore >= 0.7
        ? AIRiskLevel.highRisk
        : normalizedScore >= 0.35
        ? AIRiskLevel.suspicious
        : AIRiskLevel.lowRisk;

    return AIRiskResult(
      level: level,
      score: double.parse(normalizedScore.toStringAsFixed(3)),
      modelVersion: modelVersion,
      source: 'local_fallback',
      reason: reasons.isEmpty ? 'normal movement context' : reasons.join(', '),
      analyzedAt: DateTime.now(),
      features: features,
    );
  }

  Future<AIRiskResult> _analyzeRemotely(AIRiskContext context) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(inferenceEndpoint!);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'features': context.toJson()}));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Risk API returned ${response.statusCode}');
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final level = AIRiskLevelLabel.fromStorageValue(
        decoded['risk_level']?.toString() ?? '',
      );
      final score = (decoded['risk_score'] as num?)?.toDouble() ?? 0.0;

      return AIRiskResult(
        level: level,
        score: score.clamp(0.0, 1.0).toDouble(),
        modelVersion:
            decoded['model_version']?.toString() ?? 'remote-risk-model',
        source: 'remote_inference',
        reason: decoded['reason']?.toString() ?? 'remote model response',
        analyzedAt: DateTime.now(),
        features: context.toJson(),
      );
    } finally {
      client.close(force: true);
    }
  }

  static double _variance(List<double> values) {
    if (values.length < 2) return 0.0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final squaredDiffs = values.map((value) => pow(value - mean, 2).toDouble());
    return squaredDiffs.reduce((a, b) => a + b) / values.length;
  }
}
