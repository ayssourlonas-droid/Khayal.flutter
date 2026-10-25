import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'config.dart';
import 'game_library.dart';

/// يقابل منطق MovieLoader.gd للبيانات: ذاكرة ← قرص ← شبكة، مع تحديث صامت بالخلفية.
class DataRepository {
  DataRepository._();

  static const _timeout = Duration(seconds: 15);

  static String urlFor(String category) =>
      category == 'series' ? Config.gamesAltJsonUrl : Config.gamesJsonUrl;

  static String _diskKey(String category) => 'cache_list_$category';

  /// يستدعي [onData] فوراً بما في الذاكرة/القرص (إن وُجد) ثم بنتيجة الشبكة إن اختلفت.
  /// يرجع true إن وصلت بيانات (من أي مصدر).
  static Future<bool> load(
    String category,
    void Function(List<Map<String, dynamic>> games, {required bool fromNetwork}) onData, {
    bool forceNetwork = false,
  }) async {
    var delivered = false;
    String? shownSig;

    if (!forceNetwork) {
      final mem = AppState.cachedLists[category];
      if (mem != null && mem.isNotEmpty) {
        onData(mem, fromNetwork: false);
        shownSig = jsonEncode(mem);
        delivered = true;
      } else {
        final disk = await _readDisk(category);
        if (disk != null && disk.isNotEmpty) {
          AppState.cachedLists[category] = disk;
          onData(disk, fromNetwork: false);
          shownSig = jsonEncode(disk);
          delivered = true;
        }
      }
    }

    final fresh = await _fetchNetwork(category);
    if (fresh != null) {
      AppState.cachedLists[category] = fresh;
      _writeDisk(category, fresh);
      final sig = jsonEncode(fresh);
      if (sig != shownSig) {
        onData(fresh, fromNetwork: true);
      }
      delivered = true;
    }
    return delivered;
  }

  static Future<List<Map<String, dynamic>>?> _fetchNetwork(String category) async {
    try {
      final url = '${urlFor(category)}?v=${DateTime.now().millisecondsSinceEpoch}';
      final res = await http.get(Uri.parse(url)).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! List) return null; // يجب أن يكون JSON مصفوفة
      return GameLibrary.filterValid(data);
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>?> _readDisk(String category) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_diskKey(category));
      if (s == null) return null;
      final data = jsonDecode(s);
      if (data is! List) return null;
      // إعادة التحقق عند القراءة: قواعد الرخص قد تتغير بين الإصدارات
      return GameLibrary.filterValid(data);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeDisk(String category, List<Map<String, dynamic>> list) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_diskKey(category), jsonEncode(list));
    } catch (_) {}
  }
}

/// تنزيل الصور مع ذاكرة مؤقتة وحد أقصى تنزيلين متوازيين (كما في MovieLoader).
class ImageStore {
  ImageStore._();

  static const _maxParallel = 2;
  static int _running = 0;
  static final Queue<Completer<void>> _waiters = Queue();
  static final Map<String, Future<Uint8List?>> _inflight = {};

  static Uint8List? peek(String url) => AppState.imageCache[url];

  static Future<Uint8List?> get(String url) {
    url = url.trim();
    if (!url.startsWith('http')) return Future.value(null);
    final hit = AppState.imageCache[url];
    if (hit != null) return Future.value(hit);
    return _inflight.putIfAbsent(url, () async {
      try {
        await _acquire();
        try {
          final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            AppState.imageCache[url] = res.bodyBytes;
            return res.bodyBytes;
          }
          return null;
        } finally {
          _release();
        }
      } catch (_) {
        return null;
      } finally {
        _inflight.remove(url);
      }
    });
  }

  static Future<void> _acquire() async {
    if (_running < _maxParallel) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  static void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(); // ينتقل الدور دون تغيير العدّاد
    } else {
      _running--;
    }
  }
}
