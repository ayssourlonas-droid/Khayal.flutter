import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'alert_popup.dart';
import 'app_state.dart';
import 'config.dart';

/// فحص التحديث ونافذة «قيد التطوير» للشاشة الرئيسية — استُخرجا من home_screen.dart كما هما.
/// الاستعمال: `class _HomeScreenState extends State<HomeScreen> with UpdateCheckMixin`
/// ثم استدعاء showDevNotice() و checkForUpdate() بعد أول إطار.
mixin UpdateCheckMixin<T extends StatefulWidget> on State<T> {
  // ───────── نافذة "قيد التطوير" (مرة واحدة لكل تشغيل) ─────────
  Future<void> showDevNotice() async {
    if (AppState.devNoticeShown) return;
    AppState.devNoticeShown = true;
    _devOpen = true;
    await showAlertPopup(
      context,
      title: 'تنبيه !',
      message: 'يرجى العلم أن التطبيق ما زال قيد التطوير،\nوقد تواجهكم بعض المشكلات.\nنرجو منكم التفهم.❤️',
      buttons: const [PopupBtn(' موافق ', 2)],
    );
    _devOpen = false;
  }

  /// تُغلق نافذة "قيد التطوير" إن كانت ظاهرة قبل رسائل التحديث (لا تتراكم النوافذ).
  void _hideDevNotice() {
    if (_devOpen && mounted) {
      _devOpen = false;
      Navigator.of(context).pop(0);
    }
  }

  // ───────── فحص التحديث ─────────
  bool _dialogOpen = false;
  bool _devOpen = false;

  Future<void> checkForUpdate() async {
    http.Response res;
    try {
      res = await http
          .get(Uri.parse('${Config.versionCheckUrl}?t=${DateTime.now().millisecondsSinceEpoch ~/ 1000}'))
          .timeout(const Duration(seconds: 15));
    } on SocketException {
      return; // لا إنترنت: تجاهل صامت
    } on TimeoutException {
      return;
    } on HandshakeException {
      return;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (res.statusCode != 200) return _showCheckFailed();
    dynamic parsed;
    try {
      parsed = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return _showCheckFailed();
    }
    if (parsed is! Map) return _showCheckFailed();

    String s(String k) => (parsed[k] ?? '').toString().trim();
    final remote = s('latest_version');
    final url = s('download_url');
    final mode = parsed['update_mode'] == null ? 'optional' : s('update_mode');

    AppState.supportWhatsappUrl = s('whatsapp_url');
    AppState.supportEmail = s('support_email');
    AppState.appPageUrl = s('app_page_url');
    AppState.feedbackUrl = s('feedback_url');
    AppState.termsUrl = s('terms_url');
    AppState.privacyUrl = s('privacy_url');
    AppState.creditsUrl = s('credits_url');

    if (remote.isEmpty || url.isEmpty) return _showCheckFailed();

    final local = (await PackageInfo.fromPlatform()).version;
    if (_isNewer(remote, local)) _showUpdate(url, mode == 'forced');
  }

  /// مقارنة رقمية x.y.z (وليست نصية).
  bool _isNewer(String remote, String local) {
    final r = remote.split('.'), l = local.split('.');
    final n = r.length > l.length ? r.length : l.length;
    for (var i = 0; i < n; i++) {
      final a = i < r.length ? int.tryParse(r[i]) ?? 0 : 0;
      final b = i < l.length ? int.tryParse(l[i]) ?? 0 : 0;
      if (a > b) return true;
      if (a < b) return false;
    }
    return false;
  }

  Future<void> _showCheckFailed() async {
    if (_dialogOpen || !mounted) return;
    _dialogOpen = true;
    _hideDevNotice();
    await showAlertPopup(
      context,
      title: '⚠️ تعثّر فحص الإصدار',
      message: 'تعثّر فحص إصدار التطبيق.\nيرجى ترقية التطبيق إلى آخر إصدار.',
      buttons: const [PopupBtn(' موافق ', 2), PopupBtn(' تجاوز ', 3)],
    );
    _dialogOpen = false;
  }

  Future<void> _showUpdate(String url, bool forced) async {
    if (_dialogOpen || !mounted) return;
    _dialogOpen = true;
    _hideDevNotice();
    final msg = forced
        ? 'يوجد إصدار جديد إلزامي من التطبيق.\nيجب التحديث للمتابعة.'
        : 'يتوفر إصدار جديد من التطبيق.\nيُنصح بالتحديث للحصول على أحدث الميزات والإصلاحات.';
    while (mounted) {
      final r = await showAlertPopup(
        context,
        title: '🔄 يتوفر تحديث',
        message: msg,
        buttons: [const PopupBtn(' تحديث ⬆️ ', 2), if (!forced) const PopupBtn(' تجاوز ', 1)],
      );
      if (r == 0) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        if (!forced) break;
        await Future.delayed(const Duration(milliseconds: 250)); // الإجباري: تعاد النافذة
      } else {
        break;
      }
    }
    _dialogOpen = false;
  }
}
