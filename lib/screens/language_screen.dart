import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../widgets/glassmorphism_container.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({Key? key}) : super(key: key);

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String _selected = 'en';

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
                  const Text('Language', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildLangTile('English', 'en'),
                  const SizedBox(height: 8),
                  _buildLangTile('Español', 'es'),
                  const SizedBox(height: 8),
                  _buildLangTile('Deutsch', 'de'),
                  const SizedBox(height: 8),
                  _buildLangTile('Français', 'fr'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLangTile(String label, String code) {
    final selected = _selected == code;
    return GlassmorphismContainer(
      glassType: GlassType.light,
      padding: const EdgeInsets.all(12),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(color: AppColors.textPrimary)),
        trailing: Radio<String>(
          value: code,
          groupValue: _selected,
          activeColor: AppColors.primaryBlue,
          onChanged: (v) => setState(() => _selected = v ?? _selected),
        ),
        onTap: () => setState(() => _selected = code),
        selected: selected,
        selectedTileColor: AppColors.primaryBlue.withOpacity(0.06),
      ),
    );
  }
}

