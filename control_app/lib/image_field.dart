import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'cloudinary.dart';
import 'theme.dart';
import 'image_editor_screen.dart';
import 'ui.dart';

/// حقل رابط صورة + معاينة + رفع من المعرض + تحرير + لصق/نسخ.
class ImageField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final double previewHeight;
  /// نسبة (عرض/ارتفاع) لمعاينة كاملة بلا قص وبشكل مدمج (أزرار أيقونات)؛ عند null يبقى الشكل القديم.
  final double? aspect;
  final Color accent;
  const ImageField({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
    this.previewHeight = 160,
    this.aspect,
    this.accent = Pal.purple,
  });

  @override
  State<ImageField> createState() => _ImageFieldState();
}

class _ImageFieldState extends State<ImageField> {
  bool _busy = false;

  Future<void> _pick() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 92);
      if (f == null) return;
      setState(() => _busy = true);
      final bytes = await f.readAsBytes();
      final img = await Cloudinary.uploadBytes(bytes, f.name);
      widget.controller.text = img.url;
      widget.onChanged();
      if (mounted) toast(context, 'تم الرفع ✓');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final url = widget.controller.text.trim();
    if (url.isEmpty) {
      toast(context, 'ارفع صورة أو الصق رابطاً أولاً', error: true);
      return;
    }
    final res = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => ImageEditorScreen(url: url)));
    if (res != null && res.isNotEmpty) {
      widget.controller.text = res;
      widget.onChanged();
      setState(() {});
    }
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData('text/plain');
    final t = d?.text?.trim() ?? '';
    if (t.isEmpty) return;
    widget.controller.text = t;
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.controller.text.trim();
    if (widget.aspect != null) return _compact(url);
    return Card(
      color: Pal.surface,
      shape: Pal.cardShape(),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (url.startsWith('http'))
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(url,
                  height: widget.previewHeight,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(height: 60, child: Center(child: Text('تعذّر عرض الصورة')))),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: widget.controller,
            onChanged: (_) {
              widget.onChanged();
              setState(() {});
            },
            decoration: const InputDecoration(hintText: 'رابط الصورة https://...'),
          ),
          const SizedBox(height: 8),
          if (_busy) const LinearProgressIndicator(),
          Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.upload), label: const Text('رفع')),
            OutlinedButton.icon(onPressed: _busy ? null : _edit, icon: const Icon(Icons.tune), label: const Text('تحرير')),
            OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.paste), label: const Text('لصق')),
            OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.controller.text));
                  toast(context, 'تم النسخ');
                },
                icon: const Icon(Icons.copy),
                label: const Text('نسخ')),
          ]),
        ]),
      ),
    );
  }

  Widget _compact(String url) {
    final a = widget.accent;
    Widget ic(IconData i, String tip, VoidCallback? f) => IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        color: a,
        tooltip: tip,
        onPressed: f,
        icon: Icon(i));
    return Card(
      color: Pal.surface,
      shape: Pal.cardShape(a),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.label, style: TextStyle(fontWeight: FontWeight.bold, color: a, fontSize: 13)),
          const SizedBox(height: 6),
          // معاينة كاملة بلا قص (contain) داخل إطار بنسبة الصورة الفعلية
          AspectRatio(
            aspectRatio: widget.aspect!,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ColoredBox(
                color: Pal.surface2,
                child: url.startsWith('http')
                    ? Image.network(url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(child: Text('تعذّر العرض', style: TextStyle(fontSize: 11))))
                    : Center(child: Icon(Icons.image_outlined, color: a.withOpacity(0.4), size: 32)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: widget.controller,
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            onChanged: (_) {
              widget.onChanged();
              setState(() {});
            },
            decoration: const InputDecoration(hintText: 'https://...', contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 4), child: LinearProgressIndicator()),
          Wrap(alignment: WrapAlignment.center, children: [
            ic(Icons.upload, 'رفع', _busy ? null : _pick),
            ic(Icons.tune, 'تحرير', _busy ? null : _edit),
            ic(Icons.paste, 'لصق', _paste),
            ic(Icons.copy, 'نسخ', () {
              Clipboard.setData(ClipboardData(text: widget.controller.text));
              toast(context, 'تم النسخ');
            }),
          ]),
        ]),
      ),
    );
  }
}
