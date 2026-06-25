import 'dart:async';
import 'package:flutter/foundation.dart';

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  final Map<String, _CacheEntry> _cache = {};
  final Map<String, List<VoidCallback>> _listeners = {};

  void set(String key, dynamic value, {Duration? ttl}) {
    final entry = _CacheEntry(
      value: value,
      timestamp: DateTime.now(),
      ttl: ttl,
    );
    _cache[key] = entry;
    _notifyListeners(key);
  }

  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;

    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }

    return entry.value as T?;
  }

  bool has(String key) {
    final entry = _cache[key];
    if (entry == null) return false;
    if (entry.isExpired) {
      _cache.remove(key);
      return false;
    }
    return true;
  }

  void remove(String key) {
    _cache.remove(key);
    _notifyListeners(key);
  }

  void clear() {
    _cache.clear();
  }

  void clearExpired() {
    final now = DateTime.now();
    _cache.removeWhere((key, entry) {
      if (entry.ttl != null) {
        final expiry = entry.timestamp.add(entry.ttl!);
        return now.isAfter(expiry);
      }
      return false;
    });
  }

  Stream<T?> watch<T>(String key) {
    final controller = StreamController<T?>();
    
    void listener() {
      controller.add(get<T>(key));
    }

    _listeners.putIfAbsent(key, () => []).add(listener);
    controller.add(get<T>(key));

    controller.onCancel = () {
      _listeners[key]?.remove(listener);
      if (_listeners[key]?.isEmpty ?? false) {
        _listeners.remove(key);
      }
    };

    return controller.stream;
  }

  void _notifyListeners(String key) {
    final listeners = _listeners[key];
    if (listeners != null) {
      for (final listener in listeners) {
        listener();
      }
    }
  }

  // Statistics
  int get size => _cache.length;
  int get expiredCount => _cache.values.where((e) => e.isExpired).length;
}

class _CacheEntry {
  final dynamic value;
  final DateTime timestamp;
  final Duration? ttl;

  _CacheEntry({
    required this.value,
    required this.timestamp,
    this.ttl,
  });

  bool get isExpired {
    if (ttl == null) return false;
    final expiry = timestamp.add(ttl!);
    return DateTime.now().isAfter(expiry);
  }
}
