import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/route_tracking_service.dart';
import '../services/speed_monitoring_service.dart';
import '../models/route_model.dart';
import 'route_map_screen.dart';

class TruckMonitoringScreen extends StatefulWidget {
  const TruckMonitoringScreen({super.key});

  @override
  State<TruckMonitoringScreen> createState() => _TruckMonitoringScreenState();
}

class _TruckMonitoringScreenState extends State<TruckMonitoringScreen> {
  RouteTrackingService? _routeService;
  SpeedMonitoringService? _speedService;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    final user = auth.currentUser;

    if (user != null) {
      _routeService = RouteTrackingService(uid: user.uid);
      _speedService = SpeedMonitoringService(uid: user.uid);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _startTrip() async {
    final tripId = await _routeService?.startTrip();

    if (!mounted) return;

    if (tripId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🚛 Trip started! Route tracking active.")),
      );
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Failed to start trip")),
      );
    }
  }

  Future<void> _endTrip() async {
    await _routeService?.endTrip();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🛑 Trip ended. Data will be deleted after 1 day.")),
    );
    setState(() {});
  }

  void _openTripMap(String tripId) {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    
    if (user != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RouteMapScreen(
            tripId: tripId,
            userId: user.uid,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTracking = _routeService?.isTracking ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Truck Monitoring"),
        backgroundColor: Colors.blue.shade700,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Trip Control
            _buildTripControl(isTracking),

            const SizedBox(height: 20),

            // Current Trip Stats (if active)
            if (isTracking) _buildCurrentTripStats(),

            const SizedBox(height: 20),

            // Speed Info
            _buildSpeedInfo(),

            const SizedBox(height: 20),

            // Today's Overspeed Incidents
            _buildOverspeedIncidents(),

            const SizedBox(height: 20),

            // Recent Trips
            _buildRecentTrips(),
          ],
        ),
      ),
    );
  }

  Widget _buildTripControl(bool isTracking) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              isTracking ? "🚛 Trip In Progress" : "📍 Ready to Start",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: isTracking ? Colors.red : Colors.green,
              ),
              onPressed: isTracking ? _endTrip : _startTrip,
              icon: Icon(isTracking ? Icons.stop : Icons.play_arrow),
              label: Text(
                isTracking ? "End Trip" : "Start Trip",
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTripStats() {
    return StreamBuilder(
      stream: _routeService?.getCurrentTripStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final distance = (data['totalDistance'] ?? 0.0).toDouble();
        final maxSpeed = (data['maxSpeed'] ?? 0.0).toDouble();
        final overspeedCount = data['overspeedCount'] ?? 0;

        return Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Current Trip Stats",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    // ✅ Live Map Button for current trip
                    if (_routeService?.currentTripId != null)
                      IconButton(
                        icon: const Icon(Icons.map, color: Colors.blue),
                        tooltip: "View on Map",
                        onPressed: () => _openTripMap(_routeService!.currentTripId!),
                      ),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _statItem("Distance", "${distance.toStringAsFixed(2)} km"),
                    _statItem("Max Speed", "${maxSpeed.toStringAsFixed(1)} km/h"),
                    _statItem("Overspeeds", "$overspeedCount"),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildSpeedInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "⚠️ Speed Monitoring",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text("Speed Limit: ${SpeedMonitoringService.SPEED_LIMIT} km/h"),
            const SizedBox(height: 4),
            const Text(
              "Overspeeding will be automatically logged and tracked per trip.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverspeedIncidents() {
    return StreamBuilder(
      stream: _speedService?.getTodayOverspeedIncidents(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Today's Overspeed Incidents",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text("✅ No incidents today", style: TextStyle(color: Colors.green)),
                ],
              ),
            ),
          );
        }

        final incidents = snapshot.data!.docs;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Today's Overspeed Incidents (${incidents.length})",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...incidents.take(5).map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final speed = (data['speed'] ?? 0.0).toDouble();
                  final timestamp = (data['timestamp'] as dynamic)?.toDate();

                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.warning, color: Colors.red, size: 20),
                    title: Text("${speed.toStringAsFixed(1)} km/h"),
                    subtitle: Text(
                      timestamp != null
                          ? "${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}"
                          : "Unknown time",
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentTrips() {
    return StreamBuilder(
      stream: _routeService?.getTripsStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Recent Trips",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text("No trips yet"),
                ],
              ),
            ),
          );
        }

        final trips = snapshot.data!.docs;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Recent Trips",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...trips.map((doc) {
                  final trip = Trip.fromMap(doc.id, doc.data() as Map<String, dynamic>);

                  return ListTile(
                    dense: true,
                    leading: Icon(
                      trip.isActive ? Icons.directions_car : Icons.check_circle,
                      color: trip.isActive ? Colors.green : Colors.grey,
                    ),
                    title: Text(
                      "${trip.totalDistance.toStringAsFixed(2)} km | Max: ${trip.maxSpeed.toStringAsFixed(1)} km/h",
                    ),
                    subtitle: Text(
                      "Overspeeds: ${trip.overspeedCount} | ${_formatDate(trip.startTime)}",
                    ),
                    // ✅ Map button for completed trips
                    trailing: !trip.isActive
                        ? IconButton(
                            icon: const Icon(Icons.map, color: Colors.blue),
                            tooltip: "View Route",
                            onPressed: () => _openTripMap(trip.id),
                          )
                        : null,
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }
}
