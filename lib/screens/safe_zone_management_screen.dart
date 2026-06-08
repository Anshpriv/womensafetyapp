import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../models/safe_zone.dart';
import '../models/boundary_alert.dart';
import '../services/safe_zone_service.dart';
import '../services/auth_service.dart';
import 'safe_zone_map_screen.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';

class SafeZoneManagementScreen extends StatefulWidget {
  const SafeZoneManagementScreen({super.key});

  @override
  State<SafeZoneManagementScreen> createState() => _SafeZoneManagementScreenState();
}

class _SafeZoneManagementScreenState extends State<SafeZoneManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late SafeZoneService _safeZoneService;
  LatLng? _currentLocation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    _safeZoneService = SafeZoneService(guardianId: user?.uid ?? '');
    
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      debugPrint("Error getting location: $e");
      setState(() {
        _currentLocation = const LatLng(18.5204, 73.8567); // Default to Pune
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _addNewZone() async {
    if (_currentLocation == null) return;
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SafeZoneMapScreen(initialLocation: _currentLocation!),
      ),
    );

    if (result != null) {
      final user = context.read<AuthService>().currentUser;
      final newZone = SafeZone(
        id: '',
        childId: 'child_default', // In a real app, pick the child
        guardianId: user?.uid ?? '',
        zoneName: result['name'],
        latitude: result['latitude'],
        longitude: result['longitude'],
        radius: result['radius'],
        active: true,
      );
      await _safeZoneService.addSafeZone(newZone);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Safe Zone Added')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090014),
      appBar: AppBar(
        title: const Text('Safe Zone Management', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.pinkAccent,
          labelColor: Colors.pinkAccent,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.security), text: 'Safe Zones'),
            Tab(icon: Icon(Icons.notifications_active), text: 'Boundary Alerts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSafeZonesTab(),
          _buildAlertsTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _addNewZone,
              backgroundColor: Colors.pinkAccent,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Add Zone', style: TextStyle(color: Colors.white)),
            )
          : null,
    );
  }

  Widget _buildSafeZonesTab() {
    return StreamBuilder<List<SafeZone>>(
      stream: _safeZoneService.getSafeZones(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.pinkAccent));
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
        }

        final zones = snapshot.data ?? [];
        
        if (zones.isEmpty) {
          return _buildEmptyState('No Safe Zones configured.', Icons.location_off);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: zones.length,
          itemBuilder: (context, index) {
            final zone = zones[index];
            return Card(
              color: const Color(0xFF130922),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: zone.active ? Colors.blueAccent.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                  child: Icon(Icons.location_on, color: zone.active ? Colors.blueAccent : Colors.grey),
                ),
                title: Text(zone.zoneName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('Radius: ${zone.radius.toInt()}m', style: const TextStyle(color: Colors.white54)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: zone.active,
                      activeColor: Colors.pinkAccent,
                      onChanged: (val) => _safeZoneService.toggleSafeZone(zone.id, val),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blueAccent),
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SafeZoneMapScreen(
                              initialLocation: LatLng(zone.latitude, zone.longitude),
                              initialName: zone.zoneName,
                              initialRadius: zone.radius,
                            ),
                          ),
                        );
                        if (result != null) {
                          final updatedZone = SafeZone(
                            id: zone.id,
                            childId: zone.childId,
                            guardianId: zone.guardianId,
                            zoneName: result['name'],
                            latitude: result['latitude'],
                            longitude: result['longitude'],
                            radius: result['radius'],
                            active: zone.active,
                            createdAt: zone.createdAt,
                          );
                          await _safeZoneService.updateSafeZone(updatedZone);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Safe Zone Updated')));
                          }
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () => _safeZoneService.deleteSafeZone(zone.id),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAlertsTab() {
    return StreamBuilder<List<BoundaryAlert>>(
      stream: _safeZoneService.getBoundaryAlerts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.pinkAccent));
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
        }

        final alerts = snapshot.data ?? [];
        
        if (alerts.isEmpty) {
          return _buildEmptyState('No recent boundary alerts.', Icons.notifications_none);
        }

        return Column(
          children: [
            _buildRealTimeStatus(alerts),
            const Divider(color: Colors.white24, height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: alerts.length,
                itemBuilder: (context, index) {
                  final alert = alerts[index];
                  final isEntry = alert.type == 'entered';
                  final timeStr = DateFormat('hh:mm a').format(alert.timestamp);
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF130922),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isEntry ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isEntry ? Icons.login : Icons.logout,
                            color: isEntry ? Colors.greenAccent : Colors.redAccent,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$timeStr → ${isEntry ? 'Entered' : 'Exited'} ${alert.zoneName}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Child: ${alert.childName}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRealTimeStatus(List<BoundaryAlert> alerts) {
    // Determine current status based on latest alerts per zone
    Map<String, BoundaryAlert> latestAlertPerZone = {};
    for (var alert in alerts) {
      if (!latestAlertPerZone.containsKey(alert.zoneId)) {
        latestAlertPerZone[alert.zoneId] = alert;
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Real-Time Status', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...latestAlertPerZone.values.map((alert) {
            final isInside = alert.type == 'entered';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Icon(
                    isInside ? Icons.check_circle : Icons.warning_rounded,
                    color: isInside ? Colors.greenAccent : Colors.redAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${alert.zoneName}: ',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    isInside ? '🟢 Inside Boundary' : '🔴 Outside Boundary',
                    style: TextStyle(
                      color: isInside ? Colors.greenAccent : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.white54, fontSize: 16)),
        ],
      ),
    );
  }
}
