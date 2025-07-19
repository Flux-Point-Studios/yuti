import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/app_colors.dart';
import '../widgets/glassmorphism_container.dart';
import 'dart:ui';

class PermissionScreen extends StatefulWidget {
  final VoidCallback onPermissionsGranted;
  
  const PermissionScreen({
    Key? key,
    required this.onPermissionsGranted,
  }) : super(key: key);
  
  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _cameraGranted = false;
  bool _microphoneGranted = false;
  bool _isChecking = false;
  
  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }
  
  Future<void> _checkPermissions() async {
    setState(() => _isChecking = true);
    
    final cameraStatus = await Permission.camera.status;
    final micStatus = await Permission.microphone.status;
    
    setState(() {
      _cameraGranted = cameraStatus.isGranted;
      _microphoneGranted = micStatus.isGranted;
      _isChecking = false;
    });
    
    // If all permissions granted, proceed
    if (_cameraGranted && _microphoneGranted) {
      widget.onPermissionsGranted();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.darkGradient,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                _buildHeader(),
                const SizedBox(height: 48),
                _buildPermissionsList(),
                const Spacer(),
                _buildActionButton(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.security,
            size: 40,
            color: AppColors.primaryBlue,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'App Permissions',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'We need a few permissions to provide\nthe best experience',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 16,
          ),
        ),
      ],
    );
  }
  
  Widget _buildPermissionsList() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              _buildPermissionItem(
                icon: Icons.camera_alt,
                title: 'Camera',
                description: 'Scan QR codes for wallet addresses',
                isGranted: _cameraGranted,
                onRequest: () => _requestPermission(Permission.camera),
              ),
              const SizedBox(height: 16),
              _buildPermissionItem(
                icon: Icons.mic,
                title: 'Microphone',
                description: 'Use voice commands for hands-free control',
                isGranted: _microphoneGranted,
                onRequest: () => _requestPermission(Permission.microphone),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required VoidCallback onRequest,
  }) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isGranted 
                ? AppColors.success.withOpacity(0.2)
                : Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: isGranted ? AppColors.success : Colors.white.withOpacity(0.7),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        if (!isGranted)
          TextButton(
            onPressed: onRequest,
            child: const Text(
              'Allow',
              style: TextStyle(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        else
          const Icon(
            Icons.check_circle,
            color: AppColors.success,
          ),
      ],
    );
  }
  
  Widget _buildActionButton() {
    final allGranted = _cameraGranted && _microphoneGranted;
    
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: allGranted || _isChecking
            ? widget.onPermissionsGranted
            : _requestAllPermissions,
        style: ElevatedButton.styleFrom(
          backgroundColor: allGranted 
              ? AppColors.success 
              : AppColors.primaryBlue,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: _isChecking
            ? const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              )
            : Text(
                allGranted ? 'Continue' : 'Grant Permissions',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
  
  Future<void> _requestPermission(Permission permission) async {
    final status = await permission.request();
    await _checkPermissions();
  }
  
  Future<void> _requestAllPermissions() async {
    setState(() => _isChecking = true);
    
    // Request permissions sequentially
    if (!_cameraGranted) {
      await Permission.camera.request();
    }
    if (!_microphoneGranted) {
      await Permission.microphone.request();
    }
    
    await _checkPermissions();
  }
} 