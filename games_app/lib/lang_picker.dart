import 'package:flutter/material.dart' hide Text;

import 'colors.dart';
import 'glow_button.dart';
import 'lang_prefs.dart';
import 'l10n.dart';

/// صف «لغة نصوص الألعاب» في الإعدادات: يتوسّع ليعرض الخيارات (تلقائي، بلا ترجمة، ثم اللغات).
/// بنفس مقاسات صفوف الإعدادات الأخرى (تصميم عرض 1080).
class LangPicker extends StatefulWidget {
  const LangPicker({super.key});
  @override
  State<LangPicker> createState() => _LangPickerState();
}

class _LangPickerState extends State<LangPicker> {
  static const _lav = Color(0xFFE3B8FF);
  bool _open = false;

  Widget _icon(IconData icon) => Container(
        width: 84,
        height: 84,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [Color(0xFFC21AE0), Color(0xFF6A0DAD)], begin: Alignment.topRight, end: Alignment.bottomLeft),
        ),
        child: Icon(icon, color: Colors.white, size: 46),
      );

  Widget _option(String code, String text, String cur) {
    final sel = code == cur;
    return GlowButton(
      onTap: () {
        LangPrefs.instance.set(code);
        setState(() => _open = false);
      },
      child: Container(
        height: 104,
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Row(children: [
          const SizedBox(width: 110),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 42, fontWeight: sel ? FontWeight.w800 : FontWeight.w500, color: sel ? AppColors.yellowLabel : Colors.white)),
          ),
          if (sel) const Icon(Icons.check, color: AppColors.yellowLabel, size: 52),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LangPrefs.instance.gameLang,
      builder: (_, cur, __) => Column(children: [
        GlowButton(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            height: 124,
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Row(children: [
              _icon(Icons.translate),
              const SizedBox(width: 26),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('لغة نصوص الألعاب', style: TextStyle(fontSize: 46, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text(LangPrefs.instance.label(cur), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w500, color: _lav)),
                ]),
              ),
              Icon(_open ? Icons.expand_less : Icons.expand_more, color: _lav, size: 56),
            ]),
          ),
        ),
        if (_open) ...[
          _option(LangPrefs.auto, 'تلقائي (لغة الجهاز)', cur),
          _option(LangPrefs.off, 'الأصلية بلا ترجمة', cur),
          for (final e in LangPrefs.names.entries) _option(e.key, e.value, cur),
        ],
      ]),
    );
  }
}


/// صف «لغة التطبيق» (واجهة خيال نفسها): تلقائي أو العربية أو English.
class UiLangPicker extends StatefulWidget {
  const UiLangPicker({super.key});
  @override
  State<UiLangPicker> createState() => _UiLangPickerState();
}

class _UiLangPickerState extends State<UiLangPicker> {
  static const _lav = Color(0xFFE3B8FF);
  bool _open = false;

  String _label(String v) => v == L10n.auto ? L10n.tr('تلقائي (لغة الجهاز)') : (L10n.options[v] ?? v);

  Widget _option(String code, String text, String cur) {
    final sel = code == cur;
    return GlowButton(
      onTap: () {
        L10n.set(code);
        setState(() => _open = false);
      },
      child: Container(
        height: 104,
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Row(children: [
          const SizedBox(width: 110),
          Expanded(
            child: _txt(text, sel),
          ),
          if (sel) const Icon(Icons.check, color: AppColors.yellowLabel, size: 52),
        ]),
      ),
    );
  }

  Widget _txt(String text, bool sel) => Text(text,
      style: TextStyle(fontSize: 42, fontWeight: sel ? FontWeight.w800 : FontWeight.w500, color: sel ? AppColors.yellowLabel : Colors.white));

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: L10n.lang,
      builder: (_, cur, __) => Column(children: [
        GlowButton(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            height: 124,
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Row(children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [Color(0xFFC21AE0), Color(0xFF6A0DAD)], begin: Alignment.topRight, end: Alignment.bottomLeft),
                ),
                child: const Icon(Icons.language, color: Colors.white, size: 46),
              ),
              const SizedBox(width: 26),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('لغة التطبيق', style: TextStyle(fontSize: 46, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text(_label(cur), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w500, color: _lav)),
                ]),
              ),
              Icon(_open ? Icons.expand_less : Icons.expand_more, color: _lav, size: 56),
            ]),
          ),
        ),
        if (_open) ...[
          _option(L10n.auto, 'تلقائي (لغة الجهاز)', cur),
          for (final e in L10n.options.entries) _option(e.key, e.value, cur),
        ],
      ]),
    );
  }
}
