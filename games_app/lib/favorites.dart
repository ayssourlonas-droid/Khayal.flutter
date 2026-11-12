import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'colors.dart';

/// المفضلة وآخر لعبة فُتحت — محفوظتان على الجهاز فقط (لا تُرسَلان لأي خادم).
class Favorites extends ChangeNotifier {
  Favorites._();
  static final Favorites instance = Favorites._();

  static const _favKey = 'fav_ids';
  static const _lastKey = 'last_game_id';

  List<String> _ids = [];
  String _last = '';
  Future<void>? _loading;

  List<String> get ids => List.unmodifiable(_ids);
  String get lastId => _last;
  bool isFav(String id) => _ids.contains(id);

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _ids = p.getStringList(_favKey) ?? [];
      _last = p.getString(_lastKey) ?? '';
    } catch (_) {}
    notifyListeners();
  }

  Future<void> toggle(String id) async {
    if (id.isEmpty) return;
    _ids = isFav(id) ? (_ids.where((e) => e != id).toList()) : [id, ..._ids]; // الأحدث أولاً
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_favKey, _ids);
    } catch (_) {}
  }

  Future<void> setLast(String id) async {
    if (id.isEmpty || id == _last) return;
    _last = id;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_lastKey, id);
    } catch (_) {}
  }
}

/// نجمة المفضلة (تُوضع فوق البطاقات).
class FavStar extends StatelessWidget {
  final String id;
  final double size;
  const FavStar({super.key, required this.id, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Favorites.instance,
      builder: (_, __) {
        final on = Favorites.instance.isFav(id);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Favorites.instance.toggle(id),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              shape: BoxShape.circle,
              border: Border.all(color: on ? AppColors.yellowLabel : Colors.white54, width: 2.5),
            ),
            child: Icon(on ? Icons.star : Icons.star_border,
                size: size * 0.62, color: on ? AppColors.yellowLabel : Colors.white),
          ),
        );
      },
    );
  }
}
