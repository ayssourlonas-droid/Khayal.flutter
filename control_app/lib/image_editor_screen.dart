import 'package:flutter/material.dart';
import 'cloudinary.dart';
import 'store.dart';
import 'text_remove_screen.dart';
import 'ui.dart';

/// محرر صور بتحويلات Cloudinary (قص/ضباب/تحسين/إزالة خلفية) مع تراجع.
/// عند "اعتماد" يُرفع الناتج كصورة جديدة ويُرجع رابطها.
class ImageEditorScreen extends StatefulWidget {
  final String url;
  final bool startDrawing; // يفتح شاشة رسم إزالة النصوص مباشرة بعد التجهيز
  const ImageEditorScreen({super.key, required this.url, this.startDrawing = false});
  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  String? _cloud;
  String? _pid;
  final List<String> _chain = [];
  bool _busy = true;
  String? _err;
  int _nonce = 0; // لإعادة تحميل المعاينة (Cloudinary قد يردّ 420/423 حتى تجهز النسخة المعالجة)

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      if (!Store.hasCloudinary) throw CloudinaryException('أدخل إعدادات Cloudinary أولاً.');
      final p = Cloudinary.parseUrl(widget.url);
      if (p != null && p.cloud == Store.clCloud) {
        _cloud = p.cloud;
        _pid = p.publicId;
      } else {
        final up = await Cloudinary.uploadRemote(widget.url);
        _cloud = Store.clCloud;
        _pid = up.publicId;
      }
    } catch (e) {
      _err = '$e';
    }
    if (mounted) setState(() => _busy = false);
    if (_err == null && widget.startDrawing && mounted) _draw();
  }

  String get _preview => Cloudinary.buildUrl(_cloud!, _pid!, _chain.join('/'));
  String get _shown => _nonce == 0 ? _preview : '${_preview}?_r=$_nonce';

  Future<void> _draw() async {
    final t = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => TextRemoveScreen(imageUrl: _shown)));
    if (t != null && mounted) {
      setState(() {
        _chain.add(t);
        _nonce = 0;
      });
    }
  }

  void _add(String t) => setState(() => _chain.add(t));

  Future<void> _apply() async {
    if (_chain.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _busy = true);
    try {
      final out = await Cloudinary.uploadRemote(_preview);
      if (mounted) Navigator.pop(context, out.url);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, '$e', error: true);
      }
    }
  }

  Widget _b(String t, IconData i, String chain) =>
      OutlinedButton.icon(onPressed: _busy ? null : () => _add(chain), icon: Icon(i), label: Text(t));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تحرير الصورة')),
      body: _err != null
          ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_err!)))
          : (_busy && _pid == null)
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  if (_busy) const LinearProgressIndicator(),
                  Expanded(
                    child: InteractiveViewer(
                      child: Center(
                        child: Image.network(_shown,
                            loadingBuilder: (c, w, p) => p == null ? w : const Center(child: CircularProgressIndicator()),
                            errorBuilder: (_, __, ___) => Column(mainAxisSize: MainAxisSize.min, children: [
                              const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text('تعذّر تحميل المعاينة: قد تكون النسخة المعالجة لم تجهز بعد، أو الإضافة غير مفعّلة.', textAlign: TextAlign.center)),
                              OutlinedButton.icon(onPressed: () => setState(() => _nonce++), icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
                            ])),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Wrap(spacing: 8, runSpacing: 6, children: [
                      _b('قص غلاف 3:4', Icons.crop_portrait, Cloudinary.poster),
                      _b('قص خلفية 16:9', Icons.crop_landscape, Cloudinary.wide),
                      _b('ضباب', Icons.blur_on, Cloudinary.blur),
                      _b('تحسين', Icons.auto_fix_high, Cloudinary.enhance),
                      _b('إزالة الخلفية', Icons.layers_clear, Cloudinary.removeBg),
                      OutlinedButton.icon(onPressed: _busy ? null : _draw, icon: const Icon(Icons.draw), label: const Text('إزالة نصوص (ارسم)')),
                      OutlinedButton.icon(
                          onPressed: _chain.isEmpty ? null : () => setState(_chain.removeLast),
                          icon: const Icon(Icons.undo),
                          label: const Text('تراجع')),
                      OutlinedButton.icon(
                          onPressed: _chain.isEmpty ? null : () => setState(_chain.clear),
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('الأصل')),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: _busy ? null : _apply,
                          child: Padding(
                              padding: const EdgeInsets.all(12), child: Text(_chain.isEmpty ? 'إغلاق' : 'اعتماد (${_chain.length} تعديل)'))),
                    ),
                  ),
                ]),
    );
  }
}
