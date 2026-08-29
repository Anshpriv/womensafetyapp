import 'package:flutter_test/flutter_test.dart';
import 'package:truck_safety_app/services/ai_risk_service.dart';

void main() {
  group('AIRiskService local contextual classification', () {
    final service = AIRiskService();

    test('walking is low risk', () {
      final result = service.analyzeLocally(
        _context(
          shakeCount: 1,
          shakeIntensity: 5,
          movementVariance: 3,
          speed: 1.2,
        ),
      );

      expect(result.level, AIRiskLevel.lowRisk);
    });

    test('running is low risk', () {
      final result = service.analyzeLocally(
        _context(
          shakeCount: 2,
          shakeIntensity: 9,
          movementVariance: 8,
          speed: 3.5,
        ),
      );

      expect(result.level, AIRiskLevel.lowRisk);
    });

    test('dancing is low risk and should not force SOS', () {
      final result = service.analyzeLocally(
        _context(
          shakeCount: 3,
          shakeIntensity: 15,
          movementVariance: 18,
          speed: 0.8,
        ),
      );

      expect(result.level, AIRiskLevel.lowRisk);
    });

    test('vehicle movement is low risk without other distress indicators', () {
      final result = service.analyzeLocally(
        _context(
          shakeCount: 2,
          shakeIntensity: 12,
          movementVariance: 9,
          speed: 13,
        ),
      );

      expect(result.level, AIRiskLevel.lowRisk);
    });

    test('accidental shake is low risk', () {
      final result = service.analyzeLocally(
        _context(shakeCount: 1, shakeIntensity: 16, movementVariance: 12),
      );

      expect(result.level, AIRiskLevel.lowRisk);
    });

    test('repeated shaking is suspicious', () {
      final result = service.analyzeLocally(
        _context(
          shakeCount: 5,
          shakeIntensity: 20,
          movementVariance: 42,
          recentAutomaticTriggerCount: 2,
          secondsSincePreviousTrigger: 60,
        ),
      );

      expect(result.level, AIRiskLevel.suspicious);
    });

    test('unusual movement is suspicious', () {
      final result = service.analyzeLocally(
        _context(
          shakeCount: 4,
          shakeIntensity: 19,
          movementVariance: 48,
          speed: 6,
        ),
      );

      expect(result.level, AIRiskLevel.suspicious);
    });

    test('geofence violation increases risk to suspicious', () {
      final result = service.analyzeLocally(
        _context(
          shakeCount: 3,
          shakeIntensity: 18,
          movementVariance: 32,
          geofenceViolation: true,
        ),
      );

      expect(result.level, AIRiskLevel.suspicious);
    });

    test('multiple emergency indicators are high risk', () {
      final result = service.analyzeLocally(
        _context(
          shakeCount: 6,
          shakeIntensity: 26,
          movementVariance: 80,
          speed: 15,
          distressVoiceDetected: true,
          recentAutomaticTriggerCount: 3,
          recentSosCount: 1,
        ),
      );

      expect(result.level, AIRiskLevel.highRisk);
    });

    test('high-risk scenario is high risk', () {
      final result = service.analyzeLocally(
        _context(
          shakeCount: 5,
          shakeIntensity: 24,
          movementVariance: 70,
          geofenceViolation: true,
          distressVoiceDetected: true,
        ),
      );

      expect(result.level, AIRiskLevel.highRisk);
    });

    test('missing sensor data remains valid and does not crash', () {
      final result = service.analyzeLocally(
        _context(shakeCount: 0, shakeIntensity: 0, movementVariance: 0),
      );

      expect(result.level, AIRiskLevel.lowRisk);
    });

    test(
      'missing GPS data remains valid and slightly raises context score',
      () {
        final result = service.analyzeLocally(
          _context(locationAvailable: false),
        );

        expect(result.level, AIRiskLevel.lowRisk);
        expect(result.score, greaterThan(0));
      },
    );

    test('invalid remote response falls back to local analysis', () async {
      final service = AIRiskService(inferenceUrl: 'not-a-url');
      final result = await service.analyze(_context());

      expect(result.source, 'local_fallback');
    });

    test('AI unavailable falls back to local analysis', () async {
      final service = AIRiskService(
        inferenceUrl: 'http://127.0.0.1:9/predict',
        timeout: const Duration(milliseconds: 100),
      );
      final result = await service.analyze(_context());

      expect(result.source, 'local_fallback');
    });

    test('AI timeout falls back to local analysis', () async {
      final service = AIRiskService(
        inferenceUrl: 'http://10.255.255.1/predict',
        timeout: const Duration(milliseconds: 100),
      );
      final result = await service.analyze(_context());

      expect(result.source, 'local_fallback');
    });
  });
}

AIRiskContext _context({
  int shakeCount = 3,
  double shakeIntensity = 12,
  int shakeDurationMs = 1600,
  double movementVariance = 10,
  double movementFrequency = 20,
  double speed = 0,
  double accuracy = 10,
  bool locationAvailable = true,
  bool geofenceViolation = false,
  bool distressVoiceDetected = false,
  int recentAutomaticTriggerCount = 0,
  int recentSosCount = 0,
  int secondsSincePreviousTrigger = 9999,
}) {
  return AIRiskContext(
    triggerType: 'shake',
    shakeCount: shakeCount,
    shakeIntensity: shakeIntensity,
    shakeDurationMs: shakeDurationMs,
    movementVariance: movementVariance,
    movementFrequency: movementFrequency,
    speed: speed,
    accuracy: accuracy,
    locationAvailable: locationAvailable,
    geofenceViolation: geofenceViolation,
    distressVoiceDetected: distressVoiceDetected,
    recentAutomaticTriggerCount: recentAutomaticTriggerCount,
    recentSosCount: recentSosCount,
    secondsSincePreviousTrigger: secondsSincePreviousTrigger,
    timestamp: DateTime(2026, 8, 29, 21),
  );
}
