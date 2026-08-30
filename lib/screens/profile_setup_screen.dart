import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/storage_service.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  static const MethodChannel _deviceStatsChannel =
      MethodChannel('device_stats_channel');

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bloodGroupController = TextEditingController();
  final _noteController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _initialLoading = true;
  bool _savingProfile = false;
  bool _uploadingPhoto = false;

  String? _photoUrl;
  String? _email;
  Position? _currentPosition;
  String _currentAddress = 'Fetching address...';
  Map<String, dynamic> _deviceStats = const {};
  StreamSubscription<Position>? _positionSubscription;
  Timer? _statsTimer;

  @override
  void initState() {
    super.initState();
    _initializeProfile();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _positionSubscription?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _bloodGroupController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _initializeProfile() async {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) return;

    _email = user.email;

    final db = DatabaseService(uid: user.uid);
    final profile = await db.getUserProfile();

    _nameController.text = (profile?['name'] ?? '').toString();
    _phoneController.text = (profile?['phone'] ?? '').toString();
    _bloodGroupController.text = (profile?['bloodGroup'] ?? '').toString();
    _noteController.text = (profile?['emergencyNote'] ?? '').toString();
    _photoUrl = profile?['photoUrl']?.toString();

    await _startLiveStats();

    if (!mounted) return;
    setState(() => _initialLoading = false);
  }

  Future<void> _startLiveStats() async {
    await Permission.locationWhenInUse.request();
    await Permission.phone.request();

    await _refreshDeviceStats();
    await _refreshCurrentLocation();

    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refreshDeviceStats(),
    );

    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((position) async {
      _currentPosition = position;
      await _reverseGeocode(position);
      if (mounted) setState(() {});
    });
  }

  Future<void> _refreshDeviceStats() async {
    try {
      final stats = await _deviceStatsChannel.invokeMapMethod<String, dynamic>(
        'getDeviceStats',
      );
      if (stats != null && mounted) {
        setState(() => _deviceStats = stats);
      }
    } catch (_) {}
  }

  Future<void> _refreshCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      _currentPosition = position;
      await _reverseGeocode(position);
      if (mounted) setState(() {});
    } catch (_) {
      _currentAddress = 'Location unavailable';
    }
  }

  Future<void> _reverseGeocode(Position position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) {
        _currentAddress = 'Address unavailable';
        return;
      }

      final p = placemarks.first;
      final parts = [
        p.name,
        p.subLocality,
        p.locality,
        p.administrativeArea,
        p.postalCode,
      ].where((part) => part != null && part.trim().isNotEmpty).toList();

      _currentAddress = parts.join(', ');
    } catch (_) {
      _currentAddress = 'Address unavailable';
    }
  }

  Future<void> _pickProfilePhoto(ImageSource source) async {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) return;

    try {
      setState(() => _uploadingPhoto = true);
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1400,
      );

      if (picked == null) {
        if (mounted) setState(() => _uploadingPhoto = false);
        return;
      }

      final file = File(picked.path);
      final downloadUrl = await StorageService(uid: user.uid).uploadProfilePhoto(file);

      if (!mounted) return;
      setState(() {
        _photoUrl = downloadUrl;
        _uploadingPhoto = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Profile picture updated')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Failed to update profile photo: $e')),
      );
    }
  }

  Future<void> _showPhotoOptions() async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickProfilePhoto(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pickProfilePhoto(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) return;

    try {
      setState(() => _savingProfile = true);
      await DatabaseService(uid: user.uid).saveUserProfile(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        bloodGroup: _bloodGroupController.text.trim(),
        emergencyNote: _noteController.text.trim(),
        photoUrl: _photoUrl,
      );

      if (!mounted) return;
      setState(() => _savingProfile = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Profile saved successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingProfile = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Failed to save profile: $e')),
      );
    }
  }

  Widget _buildStatsCard({
    required IconData icon,
    required String title,
    required String value,
    Color color = Colors.white,
    int valueMaxLines = 2,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B0E2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              value,
              maxLines: valueMaxLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF090014);

    if (_initialLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final rawSpeedKmh = ((_currentPosition?.speed ?? 0) * 3.6).clamp(0, 999);
    final isLikelyStationary =
        rawSpeedKmh < 1 || (_currentPosition?.accuracy ?? 100) > 25;
    final speedKmh = isLikelyStationary ? 0.0 : rawSpeedKmh;
    final batteryLevel = _deviceStats['batteryLevel']?.toString() ?? '--';
    final charging = (_deviceStats['isCharging'] == true) ? 'Charging' : 'Not charging';
    final signalLabel = _deviceStats['signalLabel']?.toString() ?? 'Unavailable';
    final connectionType =
        _deviceStats['connectionType']?.toString() ?? 'Unavailable';
    final latitude = _currentPosition?.latitude.toStringAsFixed(5) ?? '--';
    final longitude = _currentPosition?.longitude.toStringAsFixed(5) ?? '--';

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('My Profile'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _uploadingPhoto ? null : _showPhotoOptions,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 56,
                            backgroundColor: Colors.white12,
                            backgroundImage: _photoUrl != null
                                ? NetworkImage(_photoUrl!)
                                : null,
                            child: _photoUrl == null
                                ? const Icon(
                                    Icons.person,
                                    size: 56,
                                    color: Colors.white70,
                                  )
                                : null,
                          ),
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.pinkAccent,
                            child: _uploadingPhoto
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _nameController.text.trim().isEmpty
                          ? 'Complete your safety profile'
                          : _nameController.text.trim(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _email ?? 'No email available',
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Live Device Status',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.15,
                children: [
                  _buildStatsCard(
                    icon: Icons.battery_full,
                    title: 'Battery',
                    value: '$batteryLevel% • $charging',
                    color: Colors.greenAccent,
                  ),
                  _buildStatsCard(
                    icon: Icons.network_cell,
                    title: 'Signal',
                    value: '$signalLabel • $connectionType',
                    color: Colors.lightBlueAccent,
                  ),
                  _buildStatsCard(
                    icon: Icons.speed,
                    title: 'Speed',
                    value: '${speedKmh.toStringAsFixed(1)} km/h',
                    color: Colors.orangeAccent,
                  ),
                  _buildStatsCard(
                    icon: Icons.my_location,
                    title: 'Coordinates',
                    value: 'Lat: $latitude\nLng: $longitude',
                    color: Colors.pinkAccent,
                    valueMaxLines: 3,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B0E2E),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.place, color: Colors.redAccent),
                        SizedBox(width: 8),
                        Text(
                          'Current Location',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _currentAddress,
                      style: const TextStyle(color: Colors.white70, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Profile Details',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              _buildInputField(
                controller: _nameController,
                label: 'Full Name',
                icon: Icons.person,
              ),
              const SizedBox(height: 12),
              _buildInputField(
                controller: _phoneController,
                label: 'Phone Number',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              _buildInputField(
                controller: _bloodGroupController,
                label: 'Blood Group',
                icon: Icons.bloodtype,
              ),
              const SizedBox(height: 12),
              _buildInputField(
                controller: _noteController,
                label: 'Emergency Note',
                icon: Icons.medical_information,
                maxLines: 3,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _savingProfile ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pinkAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _savingProfile
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Profile',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.pinkAccent),
        ),
      ),
    );
  }
}
