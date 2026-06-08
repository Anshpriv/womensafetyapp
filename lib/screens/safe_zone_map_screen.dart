import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class SafeZoneMapScreen extends StatefulWidget {
  final LatLng initialLocation;
  final String? initialName;
  final double? initialRadius;

  const SafeZoneMapScreen({
    super.key,
    required this.initialLocation,
    this.initialName,
    this.initialRadius,
  });

  @override
  State<SafeZoneMapScreen> createState() => _SafeZoneMapScreenState();
}

class _SafeZoneMapScreenState extends State<SafeZoneMapScreen> with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  LatLng? _selectedLocation;
  double _radius = 1000.0; // Default 1000m
  final TextEditingController _nameController = TextEditingController();

  late AnimationController _animationController;
  late Animation<double> _radiusAnimation;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    if (widget.initialName != null) {
      _nameController.text = widget.initialName!;
    }
    if (widget.initialRadius != null) {
      _radius = widget.initialRadius!;
    }

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _radiusAnimation = Tween<double>(begin: 0, end: _radius).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    )..addListener(() {
        setState(() {});
      });

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onMapTapped(LatLng location) {
    setState(() {
      _selectedLocation = location;
    });
    _animationController.reset();
    _animationController.forward();
  }

  void _onRadiusChanged(double value) {
    setState(() {
      _radius = value;
      _radiusAnimation = Tween<double>(begin: _radiusAnimation.value, end: _radius).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
      );
    });
    _animationController.reset();
    _animationController.forward();
  }

  void _saveZone() {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a zone name')),
      );
      return;
    }

    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a location on the map')),
      );
      return;
    }

    Navigator.pop(context, {
      'name': _nameController.text,
      'latitude': _selectedLocation!.latitude,
      'longitude': _selectedLocation!.longitude,
      'radius': _radius,
    });
  }

  @override
  Widget build(BuildContext context) {
    Set<Circle> circles = {};
    Set<Marker> markers = {};

    if (_selectedLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('zone_center'),
          position: _selectedLocation!,
          draggable: true,
          onDragEnd: (newPosition) {
            setState(() {
              _selectedLocation = newPosition;
            });
            _animationController.reset();
            _animationController.forward();
          },
        ),
      );

      circles.add(
        Circle(
          circleId: const CircleId('zone_circle'),
          center: _selectedLocation!,
          radius: _radiusAnimation.value,
          fillColor: Colors.blueAccent.withOpacity(0.3),
          strokeColor: Colors.blue,
          strokeWidth: 2,
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF090014),
      appBar: AppBar(
        title: const Text('Create Safe Zone', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.greenAccent),
            onPressed: _saveZone,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Zone Name (e.g., College, Home)',
                labelStyle: const TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.white24),
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.pinkAccent),
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: const Color(0xFF130922),
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              clipBehavior: Clip.antiAlias,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: widget.initialLocation,
                  zoom: 14,
                ),
                onMapCreated: (controller) => _mapController = controller,
                onTap: _onMapTapped,
                markers: markers,
                circles: circles,
                myLocationEnabled: true,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF130922),
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Radius', style: TextStyle(color: Colors.white70, fontSize: 16)),
                    Text('${_radius.toInt()} m', style: const TextStyle(color: Colors.pinkAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: _radius,
                  min: 100,
                  max: 5000,
                  activeColor: Colors.pinkAccent,
                  inactiveColor: Colors.white24,
                  onChanged: _onRadiusChanged,
                ),
                const Text(
                  'Tap on the map to set location or drag the marker.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveZone,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pinkAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Save Safe Zone', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
