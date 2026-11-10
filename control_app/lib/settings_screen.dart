import 'package:flutter/material.dart';
import 'actions_api.dart';
import 'ai_api.dart';
import 'secrets_api.dart';
import 'cloudinary.dart';
import 'github.dart';
import 'store.dart';
import 'theme.dart';
import 'ui.dart';

/// كل المفاتيح تُحفظ على هذا الجهاز فقط ولا تُرفع إلى أي مكان.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final token = TextEditingController(text: Store.ghToken);
  final owner = TextEditingController(text: Store.ghOwner);
  final repo = TextEditingController(text: Store.ghRepo);
  final branch = TextEditingController(text: Store.ghBranch);
  final acOwner = TextEditingController(text: Store.acOwner);
  final acRepo = TextEditingController(text: Store.acRepo);
  final acBranch = TextEditingController(text: Store.acBranch);
  final cloud = TextEditingController(text: Store.clCloud);
  final key = TextEditingController(text: Store.clKey);
  final secret = TextEditingController(text: Store.clSecret);
  final aiKey = TextEditingController(text: Store.aiKey);
  final aiUrl = TextEditingController(text: Store.aiEndpoint);
  final aiModel = TextEditingController(text: Store.aiModel);
  final statsUrl = TextEditingController(text: Store.statsUrl);
  final statsToken = TextEditingController(text: Store.statsToken);
  bool _show = false;

  static const _cGithub = Color(0xFFB34DE6);
  static const _cActions = Color(0xFF42A5F5);
  static const _cStats = Color(0xFFFF9800);
  static const _cAi = Color(0xFFE7FF14);
  static const _cCloud = Color(0xFF26A69A);

  bool _has(List<TextEditingController> l) => l.every((c) => c.text.trim().isNotEmpty);

  Future<void> _save() async {
    await Store.setAll({
      'gh_token': token.text,
      'gh_owner': owner.text,
      'gh_repo': repo.text,
      'gh_branch': branch.text.isEmpty ? 'main' : branch.text,
      'ac_owner': acOwner.text,
      'ac_repo': acRepo.text,
      'ac_branch': acBranch.text.isEmpty ? 'main' : acBranch.text,
      'stats_url': statsUrl.text,
      'stats_token': statsToken.text,
      'ai_key': aiKey.text,
      'ai_endpoint': aiUrl.text,
      'ai_model': aiModel.text,
      'cl_cloud': cloud.text,
      'cl_key': key.text,
      'cl_secret': secret.text,
    });
  }

  Future<void> _test(Future<String> Function() f) async {
    await _save();
    try {
      final m = await f();
      if (mounted) toast(context, m);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  /// حقل يحدّث شارة الحالة فور الكتابة.
  Widget _f(TextEditingController c, String label, {bool obscure = false, String? hint}) =>
      field(c, label, obscure: obscure, hint: hint, onChanged: () => setState(() {}));

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.info_outline, size: 15, color: Colors.white38),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, height: 1.5, color: Colors.white60))),
        ]),
      );

  Widget _pill(String text, Color c, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: c.withOpacity(0.16),
          border: Border.all(color: c.withOpacity(0.55)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _status(bool ready, {bool optional = false}) {
    if (ready) return _pill('جاهز', Pal.ok, icon: Icons.check_circle);
    return optional
        ? _pill('اختياري · غير مضبوط', Colors.white54)
        : _pill('يحتاج ضبطاً', Pal.warn, icon: Icons.warning_amber_rounded);
  }

  Widget _section({
    required IconData icon,
    required String title,
    required Color color,
    required bool ready,
    bool optional = false,
    bool open = false,
    required List<Widget> children,
  }) {
    return Card(
      color: Pal.surface,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: Pal.cardShape(color),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: open,
          iconColor: color,
          collapsedIconColor: Colors.white54,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color.withOpacity(0.18), shape: BoxShape.circle),
            child: Icon(icon, size: 22, color: color),
          ),
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Align(alignment: AlignmentDirectional.centerStart, child: _status(ready, optional: optional)),
          ),
          children: children,
        ),
      ),
    );
  }

  Widget _testBtn(String label, IconData icon, Future<String> Function() f) => OutlinedButton.icon(
        onPressed: () => _test(f),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        actions: [
          IconButton(
            tooltip: _show ? 'إخفاء المفاتيح' : 'إظهار المفاتيح',
            icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _show = !_show),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 24), children: [
        // شريط الخصوصية
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Pal.ok.withOpacity(0.10),
            border: Border.all(color: Pal.ok.withOpacity(0.4)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(children: [
            Icon(Icons.lock, size: 18, color: Pal.ok),
            SizedBox(width: 10),
            Expanded(
              child: Text('كل المفاتيح تُحفظ على هذا الهاتف فقط ولا تُرفع إلى المستودع.',
                  style: TextStyle(fontSize: 13, color: Pal.ok)),
            ),
          ]),
        ),

        _section(
          icon: Icons.hub,
          title: 'GitHub',
          color: _cGithub,
          ready: _has([token, owner, repo]),
          open: true,
          children: [
            _f(token, 'Token (ghp_... أو github_pat_...)', obscure: !_show),
            _f(owner, 'Owner'),
            _f(repo, 'Repo'),
            _f(branch, 'Branch'),
            _testBtn('اختبار GitHub', Icons.network_check, Github.testConnection),
          ],
        ),

        _section(
          icon: Icons.play_circle_outline,
          title: 'مستودع الاستيراد (Actions)',
          color: _cActions,
          ready: _has([acOwner, acRepo]),
          children: [
            _note('المستودع الذي فيه ملف import-game.yml. التوكن نفسه يجب أن يشمله بصلاحية Actions (Read and write).'),
            _f(acOwner, 'Owner'),
            _f(acRepo, 'Repo'),
            _f(acBranch, 'Branch'),
            TextButton.icon(
              onPressed: () => setState(() {
                acOwner.text = owner.text;
                acRepo.text = repo.text;
                acBranch.text = branch.text;
              }),
              icon: const Icon(Icons.content_copy, size: 16),
              label: const Text('نفس مستودع GitHub أعلاه'),
            ),
            _testBtn('اختبار Actions', Icons.network_check, ActionsApi.test),
          ],
        ),

        _section(
          icon: Icons.bar_chart,
          title: 'إحصاءات اللعب',
          color: _cStats,
          optional: true,
          ready: _has([statsUrl, statsToken]),
          children: [
            _note('رابط واجهة الإحصاء في Worker (مثل https://api.games.example.com) ورمز STATS_TOKEN الذي وضعته في Cloudflare.'),
            _f(statsUrl, 'رابط الإحصاء'),
            _f(statsToken, 'STATS_TOKEN', obscure: !_show),
          ],
        ),

        _section(
          icon: Icons.auto_awesome,
          title: 'الذكاء الاصطناعي',
          color: _cAi,
          optional: true,
          ready: _has([aiKey, aiUrl, aiModel]),
          children: [
            _note('نموذج يرى لقطات اللعبة ويجرّبها ويكتب تقريراً. الرابط يختلف من مزوّد لآخر: انسخه من توثيق المزوّد '
                '(الرابط الكامل لـ chat/completions أو messages) واختر نموذجاً يدعم الصور (Vision).'),
            _f(aiUrl, 'رابط النموذج (Endpoint كامل)',
                hint: 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions'),
            _f(aiModel, 'اسم النموذج'),
            _f(aiKey, 'المفتاح (API Key)', obscure: !_show),
            _testBtn('اختبار النموذج', Icons.network_check, AiApi.test),
            const SizedBox(height: 8),
            _testBtn('إرسال إلى GitHub (أسرار) ليستعمله الاستيراد', Icons.cloud_upload_outlined, SecretsApi.sendAi),
            const SizedBox(height: 6),
            const Text('يحتاج التوكن صلاحية Secrets: Read and write على مستودع المشاريع.',
                style: TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ),

        _section(
          icon: Icons.image_outlined,
          title: 'Cloudinary (رفع وتحرير الصور)',
          color: _cCloud,
          ready: _has([cloud, key, secret]),
          children: [
            _f(cloud, 'Cloud name'),
            _f(key, 'API Key'),
            _f(secret, 'API Secret', obscure: !_show),
            _testBtn('اختبار Cloudinary', Icons.network_check, Cloudinary.ping),
          ],
        ),
      ]),
      // زر الحفظ ثابت أسفل الشاشة، فلا حاجة للتمرير إلى آخرها
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Pal.surface,
          border: Border(top: BorderSide(color: Color(0x33B34DE6))),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await _save();
                  if (mounted) {
                    toast(context, 'تم الحفظ ✓');
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.save),
                label: const Padding(padding: EdgeInsets.all(10), child: Text('حفظ')),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
