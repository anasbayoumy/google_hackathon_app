import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionDialogWidget {
  static Future<void> showPermissionDialog(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.emergency,
                color: Color(0xFFE53935),
                size: 28,
              ),
              SizedBox(width: 12),
              Text(
                'Aidy Needs Permissions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                ),
              ),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To help you in emergencies, Aidy needs access to:',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              PermissionItem(
                icon: Icons.mic,
                title: 'Microphone',
                description: 'For voice emergency descriptions',
              ),
              SizedBox(height: 12),
              PermissionItem(
                icon: Icons.camera_alt,
                title: 'Camera',
                description: 'To capture emergency scenes',
              ),
              SizedBox(height: 12),
              PermissionItem(
                icon: Icons.photo_library,
                title: 'Storage/Photos',
                description: 'To select images from gallery',
              ),
              SizedBox(height: 12),
              PermissionItem(
                icon: Icons.location_on,
                title: 'Location',
                description: 'To include your location in emergency messages',
              ),
              SizedBox(height: 16),
              Text(
                'These permissions help Aidy provide the best emergency assistance.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
              child: const Text(
                'Open Settings',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Grant Permissions'),
            ),
          ],
        );
      },
    );
  }
}

class PermissionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const PermissionItem({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFE3F2FD),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF3F51B5),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
