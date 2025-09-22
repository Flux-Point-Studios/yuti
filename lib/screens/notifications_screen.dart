import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../widgets/glassmorphism_container.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            GlassmorphismContainer(
              glassType: GlassType.medium,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  ),
                  const SizedBox(width: 8),
                  const Text('Notifications', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  GlassmorphismContainer(
                    glassType: GlassType.light,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('Enable push notifications', style: TextStyle(color: AppColors.textPrimary)),
                        _PlaceholderSwitch(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassmorphismContainer(
                    glassType: GlassType.light,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('Email alerts for swaps', style: TextStyle(color: AppColors.textPrimary)),
                        _PlaceholderSwitch(),
                      ],
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _PlaceholderSwitch extends StatefulWidget {
  const _PlaceholderSwitch();
  @override
  State<_PlaceholderSwitch> createState() => _PlaceholderSwitchState();
}

class _PlaceholderSwitchState extends State<_PlaceholderSwitch> {
  bool _value = false;
  @override
  Widget build(BuildContext context) {
    return Switch(
      value: _value,
      onChanged: (v) => setState(() => _value = v),
      activeColor: AppColors.primaryBlue,
    );
  }
}

