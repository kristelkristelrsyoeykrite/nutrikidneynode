class ApiCache {
  static final Map<String, _ApiCacheEntry> _entries = {};
  static final Map<String, Future<Map<String, dynamic>>> _pending = {};

  static String key(List<Object?> parts) {
    return parts.map((part) => part?.toString() ?? 'null').join('|');
  }

  static Future<Map<String, dynamic>> getOrFetch(
    String key,
    Future<Map<String, dynamic>> Function() fetch, {
    Duration ttl = const Duration(minutes: 2),
  }) {
    final cached = _entries[key];
    if (cached != null && cached.isFresh) {
      return Future.value(_copyMap(cached.value));
    }

    final pending = _pending[key];
    if (pending != null) {
      return pending.then(_copyMap);
    }

    final request = fetch().then((value) {
      final response = _copyMap(value);
      if (response["success"] != false) {
        _entries[key] = _ApiCacheEntry(
          value: _copyMap(response),
          expiresAt: DateTime.now().add(ttl),
        );
      }
      return response;
    }).whenComplete(() {
      _pending.remove(key);
    });

    _pending[key] = request;
    return request.then(_copyMap);
  }

  static void invalidate(String key) {
    _entries.remove(key);
    _pending.remove(key);
  }

  static void invalidatePrefixes(Iterable<String> prefixes) {
    final prefixList = prefixes.toList(growable: false);
    _entries.removeWhere(
      (key, _) => prefixList.any((prefix) => key.startsWith(prefix)),
    );
    _pending.removeWhere(
      (key, _) => prefixList.any((prefix) => key.startsWith(prefix)),
    );
  }

  static void clear() {
    _entries.clear();
    _pending.clear();
  }

  static Map<String, dynamic> _copyMap(Map<String, dynamic> source) {
    return source.map((key, value) => MapEntry(key, _copyValue(value)));
  }

  static dynamic _copyValue(dynamic value) {
    if (value is Map<String, dynamic>) {
      return _copyMap(value);
    }
    if (value is Map) {
      return value.map(
        (key, nestedValue) => MapEntry(key.toString(), _copyValue(nestedValue)),
      );
    }
    if (value is List) {
      return value.map(_copyValue).toList(growable: false);
    }
    return value;
  }
}

class _ApiCacheEntry {
  final Map<String, dynamic> value;
  final DateTime expiresAt;

  const _ApiCacheEntry({
    required this.value,
    required this.expiresAt,
  });

  bool get isFresh => DateTime.now().isBefore(expiresAt);
}
