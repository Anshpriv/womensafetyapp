import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

class EmergencyContactsScreen extends StatelessWidget {
  const EmergencyContactsScreen({super.key});

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

  void _showAddContactDialog(BuildContext context, DatabaseService db) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool makePrimary = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text("Add Emergency Contact"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: "Name"),
                ),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: "Phone (10 digits or +91...)",
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Checkbox(
                      value: makePrimary,
                      onChanged: (v) => setState(() => makePrimary = v ?? false),
                    ),
                    const Expanded(
                      child: Text("Set as Primary Contact"),
                    )
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final phone = _cleanPhone(phoneCtrl.text);

                  if (name.isEmpty || phone.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please enter name and phone")),
                    );
                    return;
                  }

                  if (!_isValidPhone(phone)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Invalid phone. Use 10 digits or +91..."),
                      ),
                    );
                    return;
                  }

                  await db.addContact(name, phone, makePrimary);

                  if (context.mounted) Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Contact added ✅")),
                  );
                },
                child: const Text("Add"),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, DatabaseService db, String contactId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Contact?"),
        content: const Text("Are you sure you want to delete this contact?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await db.deleteContact(contactId);
              if (context.mounted) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Contact deleted ✅")),
              );
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthService>().currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    final db = DatabaseService(uid: user.uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Emergency Contacts"),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddContactDialog(context, db),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.contactsStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                "No contacts added yet.\nAdd at least 1 emergency contact ✅",
                textAlign: TextAlign.center,
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();

                    final name = data["name"] ?? "";
                    final phone = data["phone"] ?? "";
                    final isPrimary = data["isPrimary"] == true;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isPrimary ? Colors.green : Colors.blue,
                          child: Icon(
                            isPrimary ? Icons.star : Icons.person,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          name,
                          style: TextStyle(
                            fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(phone),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isPrimary)
                              IconButton(
                                icon: const Icon(Icons.star_border),
                                tooltip: "Set Primary",
                                onPressed: () async {
                                  await db.setPrimaryContact(doc.id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Primary contact updated ⭐")),
                                  );
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _confirmDelete(context, db, doc.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // ✅ Continue button
              Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: () {
                    Navigator.pushReplacementNamed(context, "/home");
                  },
                  icon: const Icon(Icons.check),
                  label: const Text("Done"),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
