import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Enhanced Address Book Entry with tags, usage tracking, and verification
class AddressBookEntry {
  final String id;
  final String name;
  final String address;
  final String coin;
  final DateTime createdAt;
  final String? notes;
  final List<String> tags;
  final bool isFavorite;
  final bool isVerified;
  final int useCount;
  final DateTime? lastUsed;
  final String? avatarUrl;
  final String? ens; // ENS domain if applicable

  AddressBookEntry({
    required this.id,
    required this.name,
    required this.address,
    required this.coin,
    required this.createdAt,
    this.notes,
    this.tags = const [],
    this.isFavorite = false,
    this.isVerified = false,
    this.useCount = 0,
    this.lastUsed,
    this.avatarUrl,
    this.ens,
  });

  AddressBookEntry copyWith({
    String? name,
    String? notes,
    List<String>? tags,
    bool? isFavorite,
    bool? isVerified,
    int? useCount,
    DateTime? lastUsed,
    String? avatarUrl,
    String? ens,
  }) {
    return AddressBookEntry(
      id: id,
      name: name ?? this.name,
      address: address,
      coin: coin,
      createdAt: createdAt,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      isVerified: isVerified ?? this.isVerified,
      useCount: useCount ?? this.useCount,
      lastUsed: lastUsed ?? this.lastUsed,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      ens: ens ?? this.ens,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'coin': coin,
    'createdAt': createdAt.toIso8601String(),
    'notes': notes,
    'tags': tags,
    'isFavorite': isFavorite,
    'isVerified': isVerified,
    'useCount': useCount,
    'lastUsed': lastUsed?.toIso8601String(),
    'avatarUrl': avatarUrl,
    'ens': ens,
  };

  factory AddressBookEntry.fromJson(Map<String, dynamic> json) => AddressBookEntry(
    id: json['id'],
    name: json['name'],
    address: json['address'],
    coin: json['coin'],
    createdAt: DateTime.parse(json['createdAt']),
    notes: json['notes'],
    tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
    isFavorite: json['isFavorite'] ?? false,
    isVerified: json['isVerified'] ?? false,
    useCount: json['useCount'] ?? 0,
    lastUsed: json['lastUsed'] != null ? DateTime.parse(json['lastUsed']) : null,
    avatarUrl: json['avatarUrl'],
    ens: json['ens'],
  );
}

/// Enhanced Address Book Service with advanced features
class AddressBookService {
  static const String _storageKey = 'address_book';
  static const String _recentKey = 'recent_addresses';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Singleton
  static final AddressBookService _instance = AddressBookService._internal();
  factory AddressBookService() => _instance;
  AddressBookService._internal();

  // Cache
  List<AddressBookEntry>? _cache;

  /// Get all address book entries
  Future<List<AddressBookEntry>> getEntries() async {
    if (_cache != null) return _cache!;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_storageKey);
      if (data == null || data.isEmpty) return [];
      
      final List<dynamic> jsonList = jsonDecode(data);
      _cache = jsonList.map((e) => AddressBookEntry.fromJson(e)).toList();
      return _cache!;
    } catch (e) {
      print('Error loading address book: $e');
      return [];
    }
  }

  /// Get entries filtered by coin
  Future<List<AddressBookEntry>> getEntriesByCoin(String coin) async {
    final all = await getEntries();
    return all.where((e) => e.coin == coin || e.coin == 'ALL').toList();
  }

  /// Get favorite entries
  Future<List<AddressBookEntry>> getFavorites() async {
    final all = await getEntries();
    return all.where((e) => e.isFavorite).toList()
      ..sort((a, b) => b.useCount.compareTo(a.useCount));
  }

  /// Get recent/frequently used entries
  Future<List<AddressBookEntry>> getFrequentlyUsed({int limit = 5}) async {
    final all = await getEntries();
    return (all..sort((a, b) => b.useCount.compareTo(a.useCount)))
      .take(limit)
      .toList();
  }

  /// Get recently used entries
  Future<List<AddressBookEntry>> getRecentlyUsed({int limit = 5}) async {
    final all = await getEntries();
    final withLastUsed = all.where((e) => e.lastUsed != null).toList();
    return (withLastUsed..sort((a, b) => b.lastUsed!.compareTo(a.lastUsed!)))
      .take(limit)
      .toList();
  }

  /// Get entries by tag
  Future<List<AddressBookEntry>> getByTag(String tag) async {
    final all = await getEntries();
    return all.where((e) => e.tags.contains(tag.toLowerCase())).toList();
  }

  /// Get all unique tags
  Future<List<String>> getAllTags() async {
    final all = await getEntries();
    final tags = <String>{};
    for (final entry in all) {
      tags.addAll(entry.tags);
    }
    return tags.toList()..sort();
  }

  /// Add a new entry
  Future<bool> addEntry(AddressBookEntry entry) async {
    try {
      final entries = await getEntries();
      
      // Check for duplicate address
      if (entries.any((e) => e.address.toLowerCase() == entry.address.toLowerCase() && e.coin == entry.coin)) {
        return false;
      }
      
      entries.add(entry);
      await _saveEntries(entries);
      return true;
    } catch (e) {
      print('Error adding address: $e');
      return false;
    }
  }

  /// Update an entry
  Future<bool> updateEntry(AddressBookEntry entry) async {
    try {
      final entries = await getEntries();
      final index = entries.indexWhere((e) => e.id == entry.id);
      
      if (index == -1) return false;
      
      entries[index] = entry;
      await _saveEntries(entries);
      return true;
    } catch (e) {
      print('Error updating address: $e');
      return false;
    }
  }

  /// Toggle favorite status
  Future<bool> toggleFavorite(String id) async {
    final entries = await getEntries();
    final index = entries.indexWhere((e) => e.id == id);
    
    if (index == -1) return false;
    
    entries[index] = entries[index].copyWith(isFavorite: !entries[index].isFavorite);
    await _saveEntries(entries);
    return true;
  }

  /// Add tags to an entry
  Future<bool> addTags(String id, List<String> newTags) async {
    final entries = await getEntries();
    final index = entries.indexWhere((e) => e.id == id);
    
    if (index == -1) return false;
    
    final updatedTags = {...entries[index].tags, ...newTags.map((t) => t.toLowerCase())}.toList();
    entries[index] = entries[index].copyWith(tags: updatedTags);
    await _saveEntries(entries);
    return true;
  }

  /// Remove a tag from an entry
  Future<bool> removeTag(String id, String tag) async {
    final entries = await getEntries();
    final index = entries.indexWhere((e) => e.id == id);
    
    if (index == -1) return false;
    
    final updatedTags = entries[index].tags.where((t) => t != tag.toLowerCase()).toList();
    entries[index] = entries[index].copyWith(tags: updatedTags);
    await _saveEntries(entries);
    return true;
  }

  /// Record usage of an address (call when sending to this address)
  Future<void> recordUsage(String id) async {
    final entries = await getEntries();
    final index = entries.indexWhere((e) => e.id == id);
    
    if (index == -1) return;
    
    entries[index] = entries[index].copyWith(
      useCount: entries[index].useCount + 1,
      lastUsed: DateTime.now(),
    );
    await _saveEntries(entries);
  }

  /// Record usage by address (when address might not be in book yet)
  Future<void> recordAddressUsage(String address, String coin, {String? name}) async {
    final entries = await getEntries();
    final index = entries.indexWhere(
      (e) => e.address.toLowerCase() == address.toLowerCase() && e.coin == coin
    );
    
    if (index != -1) {
      // Update existing
      entries[index] = entries[index].copyWith(
        useCount: entries[index].useCount + 1,
        lastUsed: DateTime.now(),
      );
    } else if (name != null) {
      // Add new entry
      entries.add(AddressBookEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        address: address,
        coin: coin,
        createdAt: DateTime.now(),
        useCount: 1,
        lastUsed: DateTime.now(),
      ));
    }
    
    await _saveEntries(entries);
  }

  /// Delete an entry
  Future<bool> deleteEntry(String id) async {
    try {
      final entries = await getEntries();
      entries.removeWhere((e) => e.id == id);
      await _saveEntries(entries);
      return true;
    } catch (e) {
      print('Error deleting address: $e');
      return false;
    }
  }

  /// Delete multiple entries
  Future<bool> deleteMultiple(List<String> ids) async {
    try {
      final entries = await getEntries();
      entries.removeWhere((e) => ids.contains(e.id));
      await _saveEntries(entries);
      return true;
    } catch (e) {
      print('Error deleting addresses: $e');
      return false;
    }
  }

  /// Search entries by name, address, or notes
  Future<List<AddressBookEntry>> search(String query) async {
    final entries = await getEntries();
    final lowerQuery = query.toLowerCase();
    
    return entries.where((e) => 
      e.name.toLowerCase().contains(lowerQuery) ||
      e.address.toLowerCase().contains(lowerQuery) ||
      (e.notes?.toLowerCase().contains(lowerQuery) ?? false) ||
      (e.ens?.toLowerCase().contains(lowerQuery) ?? false) ||
      e.tags.any((t) => t.contains(lowerQuery))
    ).toList();
  }

  /// Advanced search with filters
  Future<List<AddressBookEntry>> advancedSearch({
    String? query,
    String? coin,
    List<String>? tags,
    bool? favoritesOnly,
    bool? verifiedOnly,
    String? sortBy, // 'name', 'recent', 'frequent', 'created'
    bool ascending = true,
  }) async {
    var entries = await getEntries();
    
    // Apply filters
    if (query != null && query.isNotEmpty) {
      final lowerQuery = query.toLowerCase();
      entries = entries.where((e) => 
        e.name.toLowerCase().contains(lowerQuery) ||
        e.address.toLowerCase().contains(lowerQuery)
      ).toList();
    }
    
    if (coin != null && coin != 'ALL') {
      entries = entries.where((e) => e.coin == coin).toList();
    }
    
    if (tags != null && tags.isNotEmpty) {
      entries = entries.where((e) => 
        tags.any((t) => e.tags.contains(t.toLowerCase()))
      ).toList();
    }
    
    if (favoritesOnly == true) {
      entries = entries.where((e) => e.isFavorite).toList();
    }
    
    if (verifiedOnly == true) {
      entries = entries.where((e) => e.isVerified).toList();
    }
    
    // Apply sorting
    switch (sortBy) {
      case 'name':
        entries.sort((a, b) => ascending 
          ? a.name.compareTo(b.name) 
          : b.name.compareTo(a.name));
        break;
      case 'recent':
        entries.sort((a, b) {
          final aTime = a.lastUsed ?? a.createdAt;
          final bTime = b.lastUsed ?? b.createdAt;
          return ascending ? aTime.compareTo(bTime) : bTime.compareTo(aTime);
        });
        break;
      case 'frequent':
        entries.sort((a, b) => ascending 
          ? a.useCount.compareTo(b.useCount) 
          : b.useCount.compareTo(a.useCount));
        break;
      case 'created':
      default:
        entries.sort((a, b) => ascending 
          ? a.createdAt.compareTo(b.createdAt) 
          : b.createdAt.compareTo(a.createdAt));
    }
    
    return entries;
  }

  /// Import entries from JSON
  Future<int> importEntries(String jsonString) async {
    try {
      final List<dynamic> importedList = jsonDecode(jsonString);
      final entries = await getEntries();
      int imported = 0;
      
      for (final json in importedList) {
        final entry = AddressBookEntry.fromJson(json);
        // Check for duplicate
        if (!entries.any((e) => e.address.toLowerCase() == entry.address.toLowerCase() && e.coin == entry.coin)) {
          entries.add(entry);
          imported++;
        }
      }
      
      await _saveEntries(entries);
      return imported;
    } catch (e) {
      print('Error importing addresses: $e');
      return 0;
    }
  }

  /// Export entries to JSON
  Future<String> exportEntries({String? coin, bool favoritesOnly = false}) async {
    var entries = await getEntries();
    
    if (coin != null && coin != 'ALL') {
      entries = entries.where((e) => e.coin == coin).toList();
    }
    
    if (favoritesOnly) {
      entries = entries.where((e) => e.isFavorite).toList();
    }
    
    return jsonEncode(entries.map((e) => e.toJson()).toList());
  }

  /// Clear cache
  void clearCache() {
    _cache = null;
  }  Future<void> _saveEntries(List<AddressBookEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = entries.map((e) => e.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }
}
