import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../services/address_book_service.dart';

class AddressBookPage extends ConsumerStatefulWidget {
  final String? selectForCoin;
  
  const AddressBookPage({super.key, this.selectForCoin});

  @override
  ConsumerState<AddressBookPage> createState() => _AddressBookPageState();
}

class _AddressBookPageState extends ConsumerState<AddressBookPage> {
  final AddressBookService _addressBookService = AddressBookService();
  final TextEditingController _searchController = TextEditingController();
  
  List<AddressBookEntry> _entries = [];
  List<AddressBookEntry> _filteredEntries = [];
  bool _loading = true;
  String? _selectedCoin;

  final List<Map<String, dynamic>> _coins = [
    {'symbol': 'ALL', 'name': 'All Coins', 'color': Color(0xFF8B5CF6)},
    {'symbol': 'BTC', 'name': 'Bitcoin', 'color': Color(0xFFF7931A)},
    {'symbol': 'ETH', 'name': 'Ethereum', 'color': Color(0xFF627EEA)},
    {'symbol': 'BNB', 'name': 'BNB', 'color': Color(0xFFF3BA2F)},
    {'symbol': 'SOL', 'name': 'Solana', 'color': Color(0xFF00FFA3)},
    {'symbol': 'TRX', 'name': 'TRON', 'color': Color(0xFFEF0027)},
    {'symbol': 'XRP', 'name': 'XRP', 'color': Color(0xFF00AAE4)},
    {'symbol': 'DOGE', 'name': 'Dogecoin', 'color': Color(0xFFC2A633)},
    {'symbol': 'LTC', 'name': 'Litecoin', 'color': Color(0xFFBFBBBB)},
  ];

  @override
  void initState() {
    super.initState();
    _selectedCoin = widget.selectForCoin ?? 'ALL';
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() => _loading = true);
    final entries = await _addressBookService.getEntries();
    setState(() {
      _entries = entries;
      _filterEntries();
      _loading = false;
    });
  }

  void _filterEntries() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredEntries = _entries.where((e) {
        final matchesCoin = _selectedCoin == 'ALL' || e.coin == _selectedCoin;
        final matchesSearch = query.isEmpty ||
            e.name.toLowerCase().contains(query) ||
            e.address.toLowerCase().contains(query);
        return matchesCoin && matchesSearch;
      }).toList();
    });
  }

  Color _getCoinColor(String symbol) {
    return _coins.firstWhere(
      (c) => c['symbol'] == symbol,
      orElse: () => {'color': const Color(0xFF8B5CF6)},
    )['color'] as Color;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1421) : const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),
            
            // Search bar
            _buildSearchBar(),
            
            // Coin filter chips
            _buildCoinFilter(),
            
            // Entries list
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
                  : _filteredEntries.isEmpty
                      ? _buildEmptyState()
                      : _buildEntriesList(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEntryDialog(),
        backgroundColor: const Color(0xFF8B5CF6),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              context.pop();
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1F2E) : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: isDark ? Colors.white : Colors.black87,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Address Book',
                  style: TextStyle(

                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_entries.length} saved contacts',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1F2E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isDark ? null : Border.all(color: Colors.grey[300]!),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => _filterEntries(),
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: 'Search by name or address...',
          hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey[400]),
          border: InputBorder.none,
          icon: Icon(Icons.search, color: isDark ? Colors.white38 : Colors.grey[400]),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: isDark ? Colors.white38 : Colors.grey[400]),
                  onPressed: () {
                    _searchController.clear();
                    _filterEntries();
                  },
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildCoinFilter() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _coins.length,
        itemBuilder: (context, index) {
          final coin = _coins[index];
          final isSelected = _selectedCoin == coin['symbol'];
          final color = coin['color'] as Color;
          
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedCoin = coin['symbol']);
              _filterEntries();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.2) : (isDark ? const Color(0xFF1A1F2E) : Colors.white),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? color : (isDark ? Colors.transparent : Colors.grey[300]!),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  coin['symbol'] as String,
                  style: TextStyle(
                    color: isSelected ? color : (isDark ? Colors.white60 : Colors.grey[600]),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.contacts_outlined,
            size: 80,
            color: isDark ? Colors.white24 : Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No saved addresses',
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.grey[700],
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to add your first contact',
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.grey[500],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntriesList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredEntries.length,
      itemBuilder: (context, index) {
        final entry = _filteredEntries[index];
        return _buildEntryCard(entry);
      },
    );
  }

  Widget _buildEntryCard(AddressBookEntry entry) {
    final color = _getCoinColor(entry.coin);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: () {
        if (widget.selectForCoin != null) {
          // Return the selected address
          Navigator.pop(context, entry.address);
        } else {
          _showEntryOptionsSheet(entry);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1F2E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? color.withOpacity(0.2) : Colors.grey[200]!,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  entry.name.isNotEmpty ? entry.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.name,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          entry.coin,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.address.substring(0, 10)}...${entry.address.substring(entry.address.length - 8)}',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.grey[600],
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (entry.notes != null && entry.notes!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.notes!,
                      style: TextStyle(
                        color: isDark ? Colors.white38 : Colors.grey[500],
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: isDark ? Colors.white24 : Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  void _showEntryOptionsSheet(AddressBookEntry entry) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1F2E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            
            // Name and address
            Text(
              entry.name,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0D1421) : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                entry.address,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.grey[700],
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            
            // Actions
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    color: const Color(0xFF8B5CF6),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: entry.address));
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Address copied!'),
                          backgroundColor: const Color(0xFF10B981),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.send_rounded,
                    label: 'Send',
                    color: const Color(0xFF10B981),
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/send?coin=${entry.coin}&address=${entry.address}');
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.edit_rounded,
                    label: 'Edit',
                    color: const Color(0xFFF3BA2F),
                    onTap: () {
                      Navigator.pop(context);
                      _showAddEntryDialog(existingEntry: entry);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.delete_rounded,
                    label: 'Delete',
                    color: const Color(0xFFEF4444),
                    onTap: () async {
                      Navigator.pop(context);
                      await _addressBookService.deleteEntry(entry.id);
                      _loadEntries();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddEntryDialog({AddressBookEntry? existingEntry}) {
    final nameController = TextEditingController(text: existingEntry?.name ?? '');
    final addressController = TextEditingController(text: existingEntry?.address ?? '');
    final notesController = TextEditingController(text: existingEntry?.notes ?? '');
    String selectedCoin = existingEntry?.coin ?? 'BTC';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Builder(
            builder: (context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1F2E) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                Text(
                  existingEntry == null ? 'Add Contact' : 'Edit Contact',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Name field
                _buildTextField(
                  controller: nameController,
                  label: 'Name',
                  hint: 'e.g. John Doe',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 16),
                
                // Coin selector
                Text(
                  'Network',
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600], fontSize: 14),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _coins.length - 1, // Skip 'ALL'
                    itemBuilder: (context, index) {
                      final coin = _coins[index + 1];
                      final isSelected = selectedCoin == coin['symbol'];
                      final color = coin['color'] as Color;
                      
                      return GestureDetector(
                        onTap: () => setModalState(() => selectedCoin = coin['symbol']),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? color.withOpacity(0.2) : (isDark ? const Color(0xFF0D1421) : Colors.grey[100]),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? color : (isDark ? Colors.transparent : Colors.grey[300]!),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              coin['symbol'] as String,
                              style: TextStyle(
                                color: isSelected ? color : (isDark ? Colors.white60 : Colors.grey[600]),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                
                // Address field
                _buildTextField(
                  controller: addressController,
                  label: 'Wallet Address',
                  hint: 'Paste wallet address',
                  icon: Icons.account_balance_wallet_outlined,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                
                // Notes field
                _buildTextField(
                  controller: notesController,
                  label: 'Notes (optional)',
                  hint: 'Add a note',
                  icon: Icons.note_outlined,
                ),
                const SizedBox(height: 24),
                
                // Save button
                GestureDetector(
                  onTap: () async {
                    if (nameController.text.isEmpty || addressController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Name and address are required'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    
                    final entry = AddressBookEntry(
                      id: existingEntry?.id ?? const Uuid().v4(),
                      name: nameController.text,
                      address: addressController.text,
                      coin: selectedCoin,
                      createdAt: existingEntry?.createdAt ?? DateTime.now(),
                      notes: notesController.text.isEmpty ? null : notesController.text,
                    );
                    
                    bool success;
                    if (existingEntry == null) {
                      success = await _addressBookService.addEntry(entry);
                    } else {
                      success = await _addressBookService.updateEntry(entry);
                    }
                    
                    if (success) {
                      Navigator.pop(context);
                      _loadEntries();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Address already exists'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      existingEntry == null ? 'Save Contact' : 'Update Contact',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600], fontSize: 14),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0D1421) : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? Colors.white12 : Colors.grey[300]!),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.grey[400]),
              border: InputBorder.none,
              icon: Icon(icon, color: isDark ? Colors.white38 : Colors.grey[500]),
            ),
          ),
        ),
      ],
    );
  }
}
