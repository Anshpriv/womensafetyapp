import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/safe_zone.dart';
import 'recording_service.dart';
import 'storage_service.dart';
import 'sos_service.dart';

class GeoFenceService extends ChangeNotifier {
  final String uid;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final RecordingService _recordingService = RecordingService();
  
  Timer? _timer;
  bool _isRunning = false;
  
  // Track zones we are currently outside of and their grace timer end time
  final Map<String, DateTime> _outsideGracePeriods = {};
  
  // Cache of active zones
  List<SafeZone> _activeZones = [];

  GeoFenceService({required this.uid});

  Future<void> startMonitoring() async {
    if (_isRunning) return;
    
    // Initial fetch
    await _fetchSafeZones();
    
    _isRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkLocation();
    });
    
    // Run immediately once
    _checkLocation();
    notifyListeners();
  }

  Future<void> stopMonitoring() async {
    _isRunning = false;
    _timer?.cancel();
    _recordingService.dispose();
    notifyListeners();
  }

  Future<void> _fetchSafeZones() async {
    try {
      final snapshot = await _db
          .collection('safe_zones')
          .where('childId', isEqualTo: uid)
          .where('active', isEqualTo: true)
          .get();
          
      _activeZones = snapshot.docs
          .map((doc) => SafeZone.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('❌ Failed to fetch safe zones: $e');
    }
  }

  Future<void> _checkLocation() async {
    if (!_isRunning) return;
    
    // Refresh safe zones periodically
    await _fetchSafeZones();
    
    if (_activeZones.isEmpty) return;
    
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      
      for (var zone in _activeZones) {
        double distance = Geolocator.distanceBetween(
          pos.latitude, 
          pos.longitude, 
          zone.latitude, 
          zone.longitude
        );
        
        if (distance > zone.radius) {
          // Outside boundary
          if (!_outsideGracePeriods.containsKey(zone.id)) {
            // Start 5 minute grace period
            _outsideGracePeriods[zone.id] = DateTime.now().add(const Duration(minutes: 5));
            debugPrint('⚠️ User left safe zone ${zone.zoneName}. Grace period started.');
          } else {
            // Check if grace period expired
            if (DateTime.now().isAfter(_outsideGracePeriods[zone.id]!)) {
              // Trigger alert!
              await _triggerBoundaryAlert(zone, pos);
              // Prevent duplicate alerts for the next hour
              _outsideGracePeriods[zone.id] = DateTime.now().add(const Duration(hours: 1)); 
            }
          }
        } else {
          // Inside boundary
          if (_outsideGracePeriods.containsKey(zone.id)) {
            _outsideGracePeriods.remove(zone.id);
            debugPrint('✅ User re-entered safe zone ${zone.zoneName}.');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ GeoFence check location error: $e');
    }
  }
  
  Future<void> _triggerBoundaryAlert(SafeZone zone, Position pos) async {
    debugPrint('🚨 BOUNDARY BREACH! Zone: ${zone.zoneName}');
    
    try {
      // 1. Create alert in Firestore
      final alertRef = await _db.collection('boundary_alerts').add({
        'childId': uid,
        'zoneId': zone.id,
        'zoneName': zone.zoneName,
        'status': 'OUTSIDE',
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      // 🚨 Trigger SOS immediately when exiting boundary
      final sos = SOSService(uid: uid);
      await sos.triggerSOS();
      debugPrint('🚨 SOS Triggered automatically by Safe Zone Breach!');
      
      // 2. Start recording if not already recording
      if (!_recordingService.isRecording) {
        bool started = await _recordingService.startRecording();
        if (started) {
          // Stop after 2 mins and upload
          Timer(const Duration(minutes: 2), () async {
            String? path = await _recordingService.stopRecording();
            if (path != null) {
              try {
                StorageService storage = StorageService(uid: uid);
                final result = await storage.uploadRecording(path);
                
                await alertRef.update({'recordingUrl': result.downloadUrl});
              } catch (e) {
                debugPrint('❌ Upload failed for boundary alert recording: $e');
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to trigger boundary alert: $e');
    }
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
