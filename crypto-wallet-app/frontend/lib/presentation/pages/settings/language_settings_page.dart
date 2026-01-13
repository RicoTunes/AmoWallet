import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

// Provider for selected language
final selectedLanguageProvider = StateNotifierProvider<SelectedLanguageNotifier, String>((ref) {
  return SelectedLanguageNotifier();
});

class SelectedLanguageNotifier extends StateNotifier<String> {
  SelectedLanguageNotifier() : super('English') {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('selected_language') ?? 'English';
  }

  Future<void> setLanguage(String language) async {
    state = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_language', language);
  }
}

class LanguageSettingsPage extends ConsumerWidget {
  const LanguageSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedLanguage = ref.watch(selectedLanguageProvider);

    final languages = [
      {'name': 'English', 'nativeName': 'English', 'flag': '🇺🇸'},
      {'name': 'Spanish', 'nativeName': 'Español', 'flag': '🇪🇸'},
      {'name': 'French', 'nativeName': 'Français', 'flag': '🇫🇷'},
      {'name': 'German', 'nativeName': 'Deutsch', 'flag': '🇩🇪'},
      {'name': 'Chinese', 'nativeName': '中文', 'flag': '🇨🇳'},
      {'name': 'Japanese', 'nativeName': '日本語', 'flag': '🇯🇵'},
      {'name': 'Korean', 'nativeName': '한국어', 'flag': '🇰🇷'},
      {'name': 'Portuguese', 'nativeName': 'Português', 'flag': '🇵🇹'},
      {'name': 'Russian', 'nativeName': 'Русский', 'flag': '🇷🇺'},
      {'name': 'Arabic', 'nativeName': 'العربية', 'flag': '🇸🇦'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Language'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Language',
                style: AppTheme.titleLarge.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your preferred language',
                style: AppTheme.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.builder(
                  itemCount: languages.length,
                  itemBuilder: (context, index) {
                    final language = languages[index];
                    final isSelected = selectedLanguage == language['name'];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Text(
                          language['flag']!,
                          style: const TextStyle(fontSize: 32),
                        ),
                        title: Text(
                          language['name']!,
                          style: AppTheme.titleMedium.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          language['nativeName']!,
                          style: AppTheme.bodySmall.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          ref.read(selectedLanguageProvider.notifier).setLanguage(language['name']!);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Language changed to ${language['name']}'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
