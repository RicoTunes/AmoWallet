import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

class ReportBugPage extends StatefulWidget {
  const ReportBugPage({super.key});

  @override
  State<ReportBugPage> createState() => _ReportBugPageState();
}

class _ReportBugPageState extends State<ReportBugPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _stepsController = TextEditingController();
  String _selectedCategory = 'General';
  String _selectedSeverity = 'Medium';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  Future<void> _submitBugReport() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    // Simulate submission delay
    await Future.delayed(const Duration(seconds: 2));

    // TODO: Integrate with backend API or GitHub Issues
    // Example API call:
    // final response = await http.post(
    //   Uri.parse('https://api.yourbackend.com/bug-reports'),
    //   headers: {'Content-Type': 'application/json'},
    //   body: jsonEncode({
    //     'title': _titleController.text,
    //     'description': _descriptionController.text,
    //     'steps': _stepsController.text,
    //     'category': _selectedCategory,
    //     'severity': _selectedSeverity,
    //     'device_info': await _getDeviceInfo(),
    //     'timestamp': DateTime.now().toIso8601String(),
    //   }),
    // );

    setState(() {
      _isSubmitting = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bug report submitted successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      // Clear form
      _titleController.clear();
      _descriptionController.clear();
      _stepsController.clear();
      setState(() {
        _selectedCategory = 'General';
        _selectedSeverity = 'Medium';
      });

      // Go back after submission
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report a Bug'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Help Us Improve',
                  style: AppTheme.titleLarge.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Report any issues or bugs you encounter',
                  style: AppTheme.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 24),

                // Bug Title
                Text(
                  'Bug Title *',
                  style: AppTheme.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    hintText: 'Brief description of the bug',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.title),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a title';
                    }
                    if (value.length < 5) {
                      return 'Title must be at least 5 characters';
                    }
                    return null;
                  },
                  maxLength: 100,
                ),
                const SizedBox(height: 16),

                // Category
                Text(
                  'Category *',
                  style: AppTheme.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.category),
                  ),
                  items: [
                    'General',
                    'Wallet',
                    'Transactions',
                    'Multi-Sig',
                    'UI/UX',
                    'Security',
                    'Performance',
                    'Other',
                  ].map((category) {
                    return DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategory = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Severity
                Text(
                  'Severity *',
                  style: AppTheme.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedSeverity,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.priority_high),
                  ),
                  items: [
                    {'value': 'Low', 'color': Colors.green},
                    {'value': 'Medium', 'color': Colors.orange},
                    {'value': 'High', 'color': Colors.red},
                    {'value': 'Critical', 'color': Colors.redAccent},
                  ].map((severity) {
                    return DropdownMenuItem(
                      value: severity['value'] as String,
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: severity['color'] as Color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(severity['value'] as String),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedSeverity = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Description
                Text(
                  'Description *',
                  style: AppTheme.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    hintText: 'Describe what happened in detail...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please describe the bug';
                    }
                    if (value.length < 20) {
                      return 'Description must be at least 20 characters';
                    }
                    return null;
                  },
                  maxLength: 500,
                ),
                const SizedBox(height: 16),

                // Steps to Reproduce
                Text(
                  'Steps to Reproduce',
                  style: AppTheme.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _stepsController,
                  decoration: InputDecoration(
                    hintText: 'Step 1: Open wallet\nStep 2: Tap send button\nStep 3: ...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                  maxLength: 500,
                ),
                const SizedBox(height: 24),

                // Device Info
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.defaultPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Device Information',
                              style: AppTheme.titleSmall.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Device information will be included automatically to help us diagnose the issue.',
                          style: AppTheme.bodySmall.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• App Version\n'
                          '• Device Model\n'
                          '• OS Version\n'
                          '• Screen Size',
                          style: AppTheme.bodySmall.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitBugReport,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Submit Bug Report',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
