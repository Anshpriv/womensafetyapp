import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/route_model.dart';

class RouteMapScreen extends StatefulWidget {
  final String tripId;
  final String userId;

  const RouteMapScreen({
    super.key,
    required this.tripId,
    required this.userId,
  });

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  List<RoutePoint> _routePoints = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRouteData();
  }

  Future<void> _loadRouteData() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection("users")
          .doc(widget.userId)
          .collection("trips")
          .doc(widget.tripId)
          .collection("route_points")
          .orderBy('timestamp')
          .get();

      _routePoints = snapshot.docs
          .map((doc) => RoutePoint.fromMap(doc.data()))
          .toList();

      if (_routePoints.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      // Create polyline
      final polylineCoordinates = _routePoints
          .map((p) => LatLng(p.lat, p.lng))
          .toList();

      _polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: polylineCoordinates,
        color: Colors.blue,
        width: 5,
      ));

      // Add start marker
      _markers.add(Marker(
        markerId: const MarkerId('start'),
        position: LatLng(_routePoints.first.lat, _routePoints.first.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: '🟢 Start'),
      ));

      // Add end marker
      _markers.add(Marker(
        markerId: const MarkerId('end'),
        position: LatLng(_routePoints.last.lat, _routePoints.last.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: '🔴 End'),
      ));

      // Add overspeed markers
      for (int i = 0; i < _routePoints.length; i++) {
        if (_routePoints[i].speedKmh > 80) {
          _markers.add(Marker(
            markerId: MarkerId('overspeed_$i'),
            position: LatLng(_routePoints[i].lat, _routePoints[i].lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange,
            ),
            infoWindow: InfoWindow(
              title: '⚠️ Overspeed',
              snippet: '${_routePoints[i].speedKmh.toStringAsFixed(0)} km/h',
            ),
          ));
        }
      }

      setState(() => _loading = false);
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Route Map"),
          backgroundColor: Colors.blue.shade800,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_routePoints.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Route Map"),
          backgroundColor: Colors.blue.shade800,
        ),
        body: const Center(
          child: Text(
            "No route data available yet.\nStart tracking to see your route!",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Route Map"),
        backgroundColor: Colors.blue.shade800,
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(_routePoints.first.lat, _routePoints.first.lng),
          zoom: 14,
        ),
        markers: _markers,
        polylines: _polylines,
        onMapCreated: (controller) {
          _mapController = controller;
          _fitMapBounds();
        },
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        mapType: MapType.normal,
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "fit",
            mini: true,
            onPressed: _fitMapBounds,
            child: const Icon(Icons.fit_screen),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "info",
            mini: true,
            onPressed: _showRouteInfo,
            child: const Icon(Icons.info),
          ),
        ],
      ),
    );
  }

  void _fitMapBounds() {
    if (_routePoints.isEmpty || _mapController == null) return;

    double minLat = _routePoints.first.lat;
    double maxLat = _routePoints.first.lat;
    double minLng = _routePoints.first.lng;
    double maxLng = _routePoints.first.lng;

    for (var point in _routePoints) {
      if (point.lat < minLat) minLat = point.lat;
      if (point.lat > maxLat) maxLat = point.lat;
      if (point.lng < minLng) minLng = point.lng;
      if (point.lng > maxLng) maxLng = point.lng;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        50,
      ),
    );
  }

  void _showRouteInfo() {
    final overspeedCount = _routePoints.where((p) => p.speedKmh > 80).length;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Route Information"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("🟢 Start: ${_formatTime(_routePoints.first.timestamp)}"),
            Text("🔴 End: ${_formatTime(_routePoints.last.timestamp)}"),
            const Divider(),
            Text("📍 Total Points: ${_routePoints.length}"),
            Text("⚠️ Overspeed Instances: $overspeedCount"),
            const SizedBox(height: 8),
            const Text(
              "Legend:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text("🟢 Green = Start"),
            const Text("🔴 Red = End"),
            const Text("🟠 Orange = Overspeed"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return "${time.hour}:${time.minute.toString().padLeft(2, '0')}";
  }
}
