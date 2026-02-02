import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/location_sharing_service.dart';
import '../models/location_sharing_model.dart';

class SharedLocationsScreen extends StatefulWidget {
  const SharedLocationsScreen({super.key});

  @override
  State<SharedLocationsScreen> createState() => _SharedLocationsScreenState();
}

class _SharedLocationsScreenState extends State<SharedLocationsScreen> {
  LocationSharingService? _shareService;
  String? _myPhone;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user != null) {
      _shareService = LocationSharingService(uid: user.uid);
      
      // Get phone from Firestore directly
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();
      
      setState(() {
        _myPhone = doc.data()?['phone'] ?? '';
      });
    }
  }

  Future<void> _openMap(double lat, double lng) async {
    final url = 'https://maps.google.com/?q=$lat,$lng';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_shareService == null || _myPhone == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Shared Locations"),
        backgroundColor: Colors.purple.shade700,
      ),
      body: StreamBuilder(
        stream: _shareService!.getPeopleSharingWithMe(_myPhone!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.location_off, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "No one is sharing location with you",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final shares = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: shares.length,
            itemBuilder: (context, index) {
              final share = LocationShare.fromMap(
                shares[index].id,
                shares[index].data() as Map<String, dynamic>,
              );

              return _buildLocationShareCard(share);
            },
          );
        },
      ),
    );
  }

  Widget _buildLocationShareCard(LocationShare share) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: StreamBuilder(
        stream: _shareService!.getPersonLocation(share.sharedByUid),
        builder: (context, locSnapshot) {
          if (!locSnapshot.hasData || !locSnapshot.data!.exists) {
            return ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.person),
              ),
              title: Text(share.sharedByName),
              subtitle: const Text("Location not available"),
            );
          }

          final locData = locSnapshot.data!.data() as Map<String, dynamic>;
          final location = SharedLocation.fromMap(locData);

          if (!location.isSharing) {
            return ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.grey,
                child: Icon(Icons.location_off, color: Colors.white),
              ),
              title: Text(share.sharedByName),
              subtitle: const Text("Not currently sharing"),
            );
          }

          final timeDiff = DateTime.now().difference(location.updatedAt);
          final isRecent = timeDiff.inMinutes < 5;

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: isRecent ? Colors.green : Colors.orange,
              child: const Icon(Icons.location_on, color: Colors.white),
            ),
            title: Text(share.sharedByName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Updated: ${_formatTime(location.updatedAt)}"),
                Text(
                  isRecent ? "🟢 Live" : "⚠️ ${timeDiff.inMinutes} min ago",
                  style: TextStyle(
                    color: isRecent ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.map, color: Colors.blue),
              onPressed: () => _openMap(location.lat, location.lng),
            ),
          );
        },
      ),
    );
  }

  String _formatTime(DateTime time) {
    return "${time.hour}:${time.minute.toString().padLeft(2, '0')}";
  }
}
