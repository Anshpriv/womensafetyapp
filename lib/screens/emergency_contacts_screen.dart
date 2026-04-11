import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/call_service.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // ✅ Clean phone number input
  String _cleanPhone(String input) {
    var p = input.trim();

    // remove spaces, dashes, brackets
    p = p.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // If starts with 0 remove it
    if (p.startsWith("0")) {
      p = p.substring(1);
    }

    // If user enters just 10 digits, auto add +91
    if (RegExp(r'^\d{10}$').hasMatch(p)) {
      p = "+91$p";
    }

    // If user enters 91xxxxxxxxxx, convert
    if (RegExp(r'^91\d{10}$').hasMatch(p)) {
      p = "+$p";
    }

    return p;
  }

  bool _isValidPhone(String phone) {
    // Accept +91xxxxxxxxxx OR international +xxxxxxxxxx
    return RegExp(r'^\+\d{10,15}$').hasMatch(phone);
  }

  Future<void> _addContact(DatabaseService db) async {
    final name = _nameController.text.trim();
    final phone = _cleanPhone(_phoneController.text);

    if (name.isEmpty || phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Please enter both name and phone')),
      );
      return;
    }

    if (!_isValidPhone(phone)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Invalid phone. Use 10 digits or +91...')),
      );
      return;
    }

    try {
      await db.addContact(name, phone, false);

      _nameController.clear();
      _phoneController.clear();

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Contact added')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Failed to add contact: $e')),
      );
    }
  }

  Future<void> _showAddDialog(DatabaseService db) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Emergency Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone (10 digits or +91...)',
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _nameController.clear();
              _phoneController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _addContact(db),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(DatabaseService db, String docId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Contact?'),
        content: Text('Remove "$name" from emergency contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await db.deleteContact(docId);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Contact deleted')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Delete failed: $e')),
        );
      }
    }
  }

  // ✅ NEW: Make call with confirmation
  Future<void> _makeCall(String name, String phone) async {
    try {
      // Show confirmation dialog
      final confirm = await CallService.confirmCall(context, name, phone);
      
      if (confirm && mounted) {
        final success = await CallService.makeCall(phone);
        
        if (!success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Failed to make call')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;

    if (user == null) {
      Future.microtask(() {
        Navigator.pushReplacementNamed(context, "/login");
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final db = DatabaseService(uid: user.uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.contactsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final contacts = snapshot.data?.docs ?? [];

          if (contacts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.contact_phone, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No emergency contacts yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to add contacts',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final doc = contacts[index];
              final data = doc.data() as Map<String, dynamic>;
              final name = data['name'] ?? 'No Name';
              final phone = data['phone'] ?? 'No Phone';
              final isPrimary = data['isPrimary'] == true;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isPrimary ? Colors.green : Colors.blue.shade100,
                    child: Icon(
                      isPrimary ? Icons.star : Icons.person,
                      color: isPrimary ? Colors.white : Colors.blue.shade700,
                    ),
                  ),
                  title: Text(
                    name,
                    style: TextStyle(
                      fontWeight: isPrimary ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(phone),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ✅ NEW: Call Button
                      IconButton(
                        icon: const Icon(Icons.call, color: Colors.green),
                        onPressed: () => _makeCall(name, phone),
                        tooltip: 'Call',
                      ),
                      // Primary Star Button
                      if (!isPrimary)
                        IconButton(
                          icon: const Icon(Icons.star_border, color: Colors.orange),
                          onPressed: () async {
                            await db.setPrimaryContact(doc.id);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('⭐ Primary contact updated')),
                            );
                          },
                          tooltip: 'Set Primary',
                        ),
                      // Delete Button
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDelete(db, doc.id, name),
                        tooltip: 'Delete',
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(db),
        child: const Icon(Icons.add),
      ),
    );
  }
}
