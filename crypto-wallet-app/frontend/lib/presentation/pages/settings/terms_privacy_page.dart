import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

class TermsPrivacyPage extends StatelessWidget {
  const TermsPrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Terms & Privacy'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Terms of Service'),
              Tab(text: 'Privacy Policy'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildTermsOfService(context),
            _buildPrivacyPolicy(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTermsOfService(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Terms of Service',
            style: AppTheme.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Last Updated: ${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}',
            style: AppTheme.bodySmall.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 24),

          _buildSection(
            context,
            title: '1. Acceptance of Terms',
            content: 'By accessing and using Crypto Wallet Pro ("the App"), you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the App.\n\nThese terms constitute a legally binding agreement between you and Crypto Wallet Pro.',
          ),

          _buildSection(
            context,
            title: '2. Wallet Services',
            content: 'Crypto Wallet Pro provides a non-custodial cryptocurrency wallet service. This means:\n\n'
                '• You have full control over your private keys and assets\n'
                '• We do not store or have access to your private keys\n'
                '• You are solely responsible for securing your recovery phrase\n'
                '• We cannot recover lost passwords or recovery phrases\n'
                '• All transactions are irreversible once confirmed on the blockchain',
          ),

          _buildSection(
            context,
            title: '3. User Responsibilities',
            content: 'As a user of the App, you agree to:\n\n'
                '• Keep your recovery phrase and PIN secure and confidential\n'
                '• Not share your private keys or recovery phrase with anyone\n'
                '• Verify all transaction details before confirmation\n'
                '• Comply with all applicable laws and regulations\n'
                '• Use the App only for lawful purposes\n'
                '• Accept full responsibility for your assets and transactions',
          ),

          _buildSection(
            context,
            title: '4. Security',
            content: 'You acknowledge that:\n\n'
                '• The security of your wallet depends on keeping your recovery phrase safe\n'
                '• Anyone with access to your recovery phrase can control your assets\n'
                '• We recommend enabling biometric authentication and using a strong PIN\n'
                '• You should never input your recovery phrase on websites or apps claiming to be Crypto Wallet Pro\n'
                '• We will never ask for your recovery phrase or private keys',
          ),

          _buildSection(
            context,
            title: '5. Transactions',
            content: 'All cryptocurrency transactions are:\n\n'
                '• Final and irreversible once confirmed on the blockchain\n'
                '• Subject to network fees determined by the blockchain network\n'
                '• Your responsibility to verify recipient addresses\n'
                '• Subject to network confirmation times\n'
                '• Not guaranteed to be successful if insufficient network fees are provided',
          ),

          _buildSection(
            context,
            title: '6. Disclaimer of Warranties',
            content: 'The App is provided "as is" without warranties of any kind. We do not guarantee:\n\n'
                '• Uninterrupted or error-free service\n'
                '• That the App will meet your specific requirements\n'
                '• The accuracy of cryptocurrency price information\n'
                '• Protection against all security threats\n'
                '• Compatibility with all devices or networks',
          ),

          _buildSection(
            context,
            title: '7. Limitation of Liability',
            content: 'To the maximum extent permitted by law, Crypto Wallet Pro shall not be liable for:\n\n'
                '• Loss of cryptocurrency due to user error\n'
                '• Losses from unauthorized access to your wallet\n'
                '• Transaction errors or delays\n'
                '• Changes in cryptocurrency value\n'
                '• Technical issues or service interruptions\n'
                '• Third-party actions or blockchain network issues',
          ),

          _buildSection(
            context,
            title: '8. Multi-Signature Wallets',
            content: 'For Multi-Sig wallet features:\n\n'
                '• You understand that multiple signatures are required for transactions\n'
                '• You are responsible for coordinating with co-signers\n'
                '• Smart contract risks apply to multi-sig wallets\n'
                '• Loss of access by required co-signers may make funds inaccessible',
          ),

          _buildSection(
            context,
            title: '9. Updates and Modifications',
            content: 'We reserve the right to:\n\n'
                '• Update the App and add or remove features\n'
                '• Modify these Terms of Service at any time\n'
                '• Notify users of significant changes through the App\n'
                '• Require acceptance of updated terms for continued use',
          ),

          _buildSection(
            context,
            title: '10. Termination',
            content: 'You may stop using the App at any time. We reserve the right to:\n\n'
                '• Terminate or suspend access for violations of these terms\n'
                '• Discontinue the App with reasonable notice\n'
                '• Your wallet assets remain accessible via your recovery phrase even if the App is discontinued',
          ),

          _buildSection(
            context,
            title: '11. Contact Information',
            content: 'For questions about these Terms of Service, contact us at:\n\n'
                'Email: legal@cryptowallet.com\n'
                'Website: https://cryptowallet.com/terms',
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPrivacyPolicy(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Privacy Policy',
            style: AppTheme.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Last Updated: ${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}',
            style: AppTheme.bodySmall.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 24),

          _buildSection(
            context,
            title: '1. Introduction',
            content: 'Crypto Wallet Pro ("we", "our", or "us") is committed to protecting your privacy. This Privacy Policy explains how we handle information when you use our non-custodial cryptocurrency wallet application.',
          ),

          _buildSection(
            context,
            title: '2. Non-Custodial Nature',
            content: 'Our wallet is non-custodial, which means:\n\n'
                '• We do not store your private keys, recovery phrases, or passwords\n'
                '• We cannot access, freeze, or recover your wallet\n'
                '• You have complete control over your cryptocurrency\n'
                '• Your wallet data is stored locally on your device\n'
                '• We cannot view your transaction history or balances',
          ),

          _buildSection(
            context,
            title: '3. Information We Collect',
            content: 'We collect minimal information to provide our services:\n\n'
                'Information Stored Locally:\n'
                '• Encrypted wallet data on your device\n'
                '• App preferences and settings\n'
                '• Transaction history cached on your device\n\n'
                'Anonymous Usage Data:\n'
                '• App crashes and errors (no personal data)\n'
                '• Feature usage statistics (anonymized)\n'
                '• Device type and OS version (for compatibility)',
          ),

          _buildSection(
            context,
            title: '4. Information We Do NOT Collect',
            content: 'We explicitly do not collect:\n\n'
                '• Your private keys or recovery phrases\n'
                '• Your wallet passwords or PINs\n'
                '• Your personal identity information\n'
                '• Your transaction details or amounts\n'
                '• Your wallet addresses or balances\n'
                '• Your browsing history or behavior',
          ),

          _buildSection(
            context,
            title: '5. How We Use Information',
            content: 'The limited information we collect is used to:\n\n'
                '• Provide and improve the App functionality\n'
                '• Fix bugs and technical issues\n'
                '• Understand how users interact with features\n'
                '• Ensure compatibility across devices\n'
                '• Improve user experience and performance',
          ),

          _buildSection(
            context,
            title: '6. Third-Party Services',
            content: 'The App may interact with third-party services:\n\n'
                'Blockchain Networks:\n'
                '• Your transactions are broadcast to public blockchains\n'
                '• These are public and permanent records\n'
                '• We do not control blockchain data\n\n'
                'Price Data Providers:\n'
                '• We fetch cryptocurrency prices from third-party APIs\n'
                '• These requests are anonymous\n'
                '• No personal information is shared',
          ),

          _buildSection(
            context,
            title: '7. Data Security',
            content: 'We implement security measures to protect your data:\n\n'
                '• All sensitive data is encrypted on your device\n'
                '• Biometric authentication support\n'
                '• Secure PIN protection\n'
                '• No central servers storing wallet data\n'
                '• Industry-standard encryption protocols',
          ),

          _buildSection(
            context,
            title: '8. Your Privacy Rights',
            content: 'You have the right to:\n\n'
                '• Access your locally stored data\n'
                '• Delete the App and all local data\n'
                '• Opt-out of anonymous usage statistics\n'
                '• Request information about our data practices\n'
                '• Export your wallet using your recovery phrase',
          ),

          _buildSection(
            context,
            title: '9. Data Retention',
            content: 'Data retention policies:\n\n'
                '• Local wallet data remains until you delete the App\n'
                '• Anonymous usage data is retained for up to 12 months\n'
                '• Crash reports are retained for up to 90 days\n'
                '• You can clear cached data through App settings',
          ),

          _buildSection(
            context,
            title: '10. Children\'s Privacy',
            content: 'The App is not intended for users under 18 years of age. We do not knowingly collect information from children. If you believe a child has used the App, please contact us.',
          ),

          _buildSection(
            context,
            title: '11. International Users',
            content: 'The App is available worldwide. By using the App:\n\n'
                '• You acknowledge that data may be processed in different countries\n'
                '• We comply with applicable international privacy laws\n'
                '• Your data remains under your control on your device',
          ),

          _buildSection(
            context,
            title: '12. Changes to Privacy Policy',
            content: 'We may update this Privacy Policy from time to time. Significant changes will be communicated through the App. Continued use after changes constitutes acceptance of the updated policy.',
          ),

          _buildSection(
            context,
            title: '13. Contact Us',
            content: 'For privacy-related questions or concerns:\n\n'
                'Email: privacy@cryptowallet.com\n'
                'Website: https://cryptowallet.com/privacy\n\n'
                'We aim to respond to all inquiries within 7 business days.',
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, {required String title, required String content}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTheme.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: AppTheme.bodyMedium.copyWith(
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
