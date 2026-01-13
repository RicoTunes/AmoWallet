import 'package:flutter/material.dart';
import '../../../services/wallet_service.dart';

class PinSettingsPage extends StatefulWidget {
  const PinSettingsPage({super.key});

  @override
  State<PinSettingsPage> createState() => _PinSettingsPageState();
}

class _PinSettingsPageState extends State<PinSettingsPage> {
  final WalletService _wallet = WalletService();
  bool _hasPin = false;
  List<Map<String, dynamic>> _audit = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final has = await _wallet.hasPin();
    final audit = await _wallet.getRevealAudit();
    setState(() {
      _hasPin = has;
      _audit = audit.reversed.toList();
      _loading = false;
    });
  }

  Future<void> _promptSetPin() async {
    final p1 = await _askForPin('Enter new 6-digit PIN');
    if (p1 == null) return;
    final p2 = await _askForPin('Confirm new 6-digit PIN');
    if (p2 == null) return;
    if (p1 != p2) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PINs do not match')));
      return;
    }
    await _wallet.setPin(p1);
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN set')));
  }

  Future<void> _promptChangePin() async {
    final old = await _askForPin('Enter current PIN');
    if (old == null) return;
    final ok = await _wallet.verifyPin(old);
    if (!ok) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect current PIN')));
      return;
    }
    await _promptSetPin();
  }

  Future<void> _removePin() async {
    final confirmed = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Remove PIN'),
      content: const Text('Are you sure you want to remove the PIN? This will disable the gated reveal protection.'),
      actions: [TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Remove'))],
    ));
    if (confirmed != true) return;
  await _wallet.deletePin();
    await _load();
  }

  Future<String?> _askForPin(String title) async {
    final ctl = TextEditingController();
    final res = await showDialog<String?>(context: context, builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctl, keyboardType: TextInputType.number, obscureText: true, maxLength: 6),
      actions: [TextButton(onPressed: () => Navigator.of(c).pop(null), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.of(c).pop(ctl.text.trim()), child: const Text('OK'))],
    ));
    if (res == null) return null;
    if (res.length != 6) return null;
    return res;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PIN & Reveal Audit')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PIN', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (!_hasPin)
                    ElevatedButton(onPressed: _promptSetPin, child: const Text('Set 6-digit PIN'))
                  else
                    Row(children: [ElevatedButton(onPressed: _promptChangePin, child: const Text('Change PIN')), const SizedBox(width: 12), OutlinedButton(onPressed: _removePin, child: const Text('Remove PIN'))]),
                  const SizedBox(height: 24),
                  Text('Reveal Audit', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _audit.isEmpty
                        ? const Center(child: Text('No reveal events recorded'))
                        : ListView.separated(
                            itemCount: _audit.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final e = _audit[index];
                              final ts = e['timestamp'] ?? '';
                              final chain = e['chain'] ?? '';
                              final addr = e['address'] ?? '';
                              final ok = e['success'] == true;
                              return ListTile(
                                leading: Icon(ok ? Icons.check_circle : Icons.error, color: ok ? Colors.green : Colors.red),
                                title: Text('$chain • $addr', overflow: TextOverflow.ellipsis),
                                subtitle: Text(ts),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
