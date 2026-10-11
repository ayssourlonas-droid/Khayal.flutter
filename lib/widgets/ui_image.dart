import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/data_repository.dart';

/// تحميل صور الأصول كـ ui.Image (للرسم المخصص بالأقنعة والشيدرات).
class AssetUiImages {
  AssetUiImages._();
  static final Map<String, Future<ui.Image>> _cache = {};

  static Future<ui.Image> load(String asset) => _cache.putIfAbsent(asset, () async {
        final data = await rootBundle.load(asset);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        return (await codec.getNextFrame()).image;
      });
}

/// فكّ بايتات صورة شبكية إلى ui.Image مع كاش.
class BytesUiImages {
  BytesUiImages._();
  static final Map<String, ui.Image> _cache = {};

  static Future<ui.Image?> fromUrl(String url) async {
    final hit = _cache[url];
    if (hit != null) return hit;
    final bytes = await ImageStore.get(url);
    if (bytes == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final img = (await codec.getNextFrame()).image;
      _cache[url] = img;
      return img;
    } catch (_) {
      return null;
    }
  }
}

/// صورة شبكية تظهر بتلاشٍ ناعم عند اكتمال التحميل (يقابل tween الشفافية في جودوت).
class NetImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Duration fade;
  final Widget? placeholder;
  final ValueChanged<Uint8List>? onLoaded;

  const NetImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fade = const Duration(milliseconds: 800),
    this.placeholder,
    this.onLoaded,
  });

  @override
  State<NetImage> createState() => _NetImageState();
}

class _NetImageState extends State<NetImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NetImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final cached = ImageStore.peek(widget.url);
    if (cached != null) {
      _bytes = cached;
      widget.onLoaded?.call(cached);
      return;
    }
    final b = await ImageStore.get(widget.url);
    if (!mounted) return;
    setState(() {
      _bytes = b;
      _failed = b == null;
    });
    if (b != null) widget.onLoaded?.call(b);
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: b == null
          ? (_failed ? const SizedBox.shrink() : (widget.placeholder ?? const SizedBox.shrink()))
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: widget.fade,
              curve: Curves.easeInOutSine,
              builder: (_, v, child) => Opacity(opacity: v, child: child),
              child: Image.memory(b,
                  fit: widget.fit, width: widget.width, height: widget.height, gaplessPlayback: true),
            ),
    );
  }
}
