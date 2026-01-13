import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How can we help you?',
                style: AppTheme.titleLarge.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              
              // Getting Started Section
              _buildSection(
                context,
                icon: Icons.play_circle_outline,
                title: 'Getting Started',
                description: 'Learn the basics of using your crypto wallet',
                onTap: () => _showHelpDialog(
                  context,
                  'Getting Started',
                  'Welcome to Crypto Wallet Pro!\n\n'
                  '1. Create or Import Wallet: Start by creating a new wallet or importing an existing one using your recovery phrase.\n\n'
                  '2. Secure Your Wallet: Set up a PIN or biometric authentication for added security.\n\n'
                  '3. Receive Funds: Use the Receive function to get your wallet address and share it with others.\n\n'
                  '4. Send Funds: Use the Send function to transfer crypto to other addresses.\n\n'
                  '5. Check Portfolio: View your assets and their current values in the Portfolio tab.',
                ),
              ),
              
              // Security Tips
              _buildSection(
                context,
                icon: Icons.security,
                title: 'Security Tips',
                description: 'Best practices to keep your wallet secure',
                onTap: () => _showHelpDialog(
                  context,
                  'Security Tips',
                  '🔐 Important Security Tips:\n\n'
                  '• Never share your recovery phrase with anyone\n'
                  '• Always backup your wallet in a secure location\n'
                  '• Enable biometric authentication\n'
                  '• Use a strong PIN code\n'
                  '• Double-check recipient addresses before sending\n'
                  '• Keep your app updated\n'
                  '• Be cautious of phishing attempts\n'
                  '• Use Multi-Sig wallets for large amounts',
                ),
              ),
              
              // Wallet Management
              _buildSection(
                context,
                icon: Icons.account_balance_wallet,
                title: 'Wallet Management',
                description: 'Create, import, and manage your wallets',
                onTap: () => _showHelpDialog(
                  context,
                  'Wallet Management',
                  'Managing Your Wallets:\n\n'
                  'Create New Wallet:\n'
                  '• Generate a new wallet with a unique recovery phrase\n'
                  '• Write down your 12-word recovery phrase\n'
                  '• Store it securely offline\n\n'
                  'Import Existing Wallet:\n'
                  '• Use your recovery phrase to restore a wallet\n'
                  '• All your assets will be accessible\n\n'
                  'Multiple Wallets:\n'
                  '• Create multiple wallets for different purposes\n'
                  '• Switch between wallets easily\n'
                  '• Each wallet has its own recovery phrase',
                ),
              ),
              
              // Sending & Receiving
              _buildSection(
                context,
                icon: Icons.swap_horiz,
                title: 'Sending & Receiving',
                description: 'How to send and receive cryptocurrency',
                onTap: () => _showHelpDialog(
                  context,
                  'Sending & Receiving',
                  'Sending Crypto:\n'
                  '1. Tap "Send" on the Dashboard\n'
                  '2. Enter recipient address or scan QR code\n'
                  '3. Enter amount to send\n'
                  '4. Review transaction details\n'
                  '5. Confirm and authorize\n\n'
                  'Receiving Crypto:\n'
                  '1. Tap "Receive" on the Dashboard\n'
                  '2. Select the cryptocurrency\n'
                  '3. Share your address or QR code\n'
                  '4. Wait for confirmation\n\n'
                  'Network Fees:\n'
                  '• Fees vary by network congestion\n'
                  '• Higher fees = faster confirmation\n'
                  '• You can adjust fee priority',
                ),
              ),
              
              // Multi-Sig Wallets
              _buildSection(
                context,
                icon: Icons.people,
                title: 'Multi-Sig Wallets',
                description: 'Shared wallets with multiple signers',
                onTap: () => _showHelpDialog(
                  context,
                  'Multi-Sig Wallets',
                  'Multi-Signature Wallets:\n\n'
                  'What is Multi-Sig?\n'
                  '• Requires multiple signatures to approve transactions\n'
                  '• Enhanced security for shared funds\n'
                  '• Example: 2-of-3 requires 2 approvals from 3 owners\n\n'
                  'Creating a Multi-Sig:\n'
                  '1. Tap "Create Multi-Sig" on Dashboard\n'
                  '2. Add co-signers addresses\n'
                  '3. Set required signatures threshold\n'
                  '4. Deploy the wallet contract\n\n'
                  'Using Multi-Sig:\n'
                  '• Propose transactions\n'
                  '• Wait for approvals from co-signers\n'
                  '• Execute when threshold is met',
                ),
              ),
              
              // Transaction History
              _buildSection(
                context,
                icon: Icons.history,
                title: 'Transaction History',
                description: 'View and track your transactions',
                onTap: () => _showHelpDialog(
                  context,
                  'Transaction History',
                  'Transaction History:\n\n'
                  'Viewing Transactions:\n'
                  '• Tap "History" to view all transactions\n'
                  '• Filter by type: Sent, Received, All\n'
                  '• Sort by date or amount\n\n'
                  'Transaction Details:\n'
                  '• Transaction hash\n'
                  '• Status (Pending, Confirmed, Failed)\n'
                  '• Amount and fees\n'
                  '• Date and time\n'
                  '• Block confirmations\n\n'
                  'View on Blockchain:\n'
                  '• Tap transaction to view details\n'
                  '• Open in blockchain explorer',
                ),
              ),
              
              // Troubleshooting
              _buildSection(
                context,
                icon: Icons.build,
                title: 'Troubleshooting',
                description: 'Common issues and solutions',
                onTap: () => _showHelpDialog(
                  context,
                  'Troubleshooting',
                  'Common Issues:\n\n'
                  'Transaction Pending Too Long:\n'
                  '• Network congestion may cause delays\n'
                  '• Wait for confirmation\n'
                  '• You can speed up with higher fees\n\n'
                  'Can\'t See My Balance:\n'
                  '• Check network connection\n'
                  '• Switch networks (Mainnet/Testnet)\n'
                  '• Force refresh the app\n\n'
                  'Forgot PIN:\n'
                  '• Use biometric authentication\n'
                  '• Restore wallet with recovery phrase\n\n'
                  'Wrong Network:\n'
                  '• Go to Settings > Networks\n'
                  '• Select correct network (Mainnet/Testnet)',
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Contact Support
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.defaultPadding),
                  child: Column(
                    children: [
                      Icon(
                        Icons.support_agent,
                        size: 48,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Still Need Help?',
                        style: AppTheme.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Contact our support team',
                        style: AppTheme.bodyMedium.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Opening support email...'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                          // TODO: Integrate with email client or support system
                          // launch('mailto:support@cryptowallet.com');
                        },
                        icon: const Icon(Icons.email),
                        label: const Text('Email Support'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          title,
          style: AppTheme.titleMedium.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          description,
          style: AppTheme.bodySmall.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
        ),
        onTap: onTap,
      ),
    );
  }

  void _showHelpDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(content),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
