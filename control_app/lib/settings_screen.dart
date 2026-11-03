import 'package:flutter/material.dart';
import 'actions_api.dart';
import 'ai_api.dart';
import 'secrets_api.dart';
import 'cloudinary.dart';
import 'github.dart';
import 'store.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات'), actions: [
        IconButton(
            icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _show = !_show)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('🔒 تُحفظ على هذا الهاتف فقط ولا تُرفع إلى المستودع.', style: TextStyle(color: Colors.greenAccent)),
        const SizedBox(height: 14),
        const Text('GitHub', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        field(token, 'Token (ghp_... أو github_pat_...)', obscure: !_show),
        field(owner, 'Owner'),
        field(repo, 'Repo'),
        field(branch, 'Branch'),
        OutlinedButton(onPressed: () => _test(Github.testConnection), child: const Text('اختبار GitHub')),
        const Divider(height: 36),
        const Text('مستودع الاستيراد (GitHub Actions)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('المستودع الذي فيه ملف import-game.yml. التوكن نفسه يجب أن يشمله بصلاحية Actions (Read and write).',
            style: TextStyle(fontSize: 12, color: Colors.white60)),
        const SizedBox(height: 8),
        field(acOwner, 'Owner'),
        field(acRepo, 'Repo'),
        field(acBranch, 'Branch'),
        OutlinedButton(onPressed: () => _test(ActionsApi.test), child: const Text('اختبار Actions')),
        const Divider(height: 36),
        const Text('إحصاءات اللعب (اختياري)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('رابط واجهة الإحصاء في Worker (مثل https://api.games.example.com) ورمز STATS_TOKEN الذي وضعته في Cloudflare.',
            style: TextStyle(fontSize: 12, color: Colors.white60)),
        const SizedBox(height: 8),
        field(statsUrl, 'رابط الإحصاء'),
        field(statsToken, 'STATS_TOKEN', obscure: !_show),
        const Divider(height: 36),
        const Text('الذكاء الاصطناعي (اختياري)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
            'نموذج يرى لقطات اللعبة ويجرّبها ويكتب تقريراً. الرابط يختلف من مزوّد لآخر: انسخه من توثيق المزوّد (الرابط الكامل لـ chat/completions أو messages) واختر نموذجاً يدعم الصور (Vision). مثال Gemini: https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
            style: TextStyle(fontSize: 12, color: Colors.white60)),
        const SizedBox(height: 8),
        field(aiUrl, 'رابط النموذج (Endpoint كامل)'),
        field(aiModel, 'اسم النموذج'),
        field(aiKey, 'المفتاح (API Key)', obscure: !_show),
        OutlinedButton(onPressed: () => _test(AiApi.test), child: const Text('اختبار النموذج')),
        const SizedBox(height: 6),
        OutlinedButton(onPressed: () => _test(SecretsApi.sendAi), child: const Text('إرسال إلى GitHub (أسرار) ليستعمله الاستيراد')),
        const Text('يحتاج التوكن صلاحية Secrets: Read and write على مستودع المشاريع.',
            style: TextStyle(fontSize: 12, color: Colors.white60)),
        const Divider(height: 36),
        const Text('Cloudinary (لرفع وتحرير الصور)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        field(cloud, 'Cloud name'),
        field(key, 'API Key'),
        field(secret, 'API Secret', obscure: !_show),
        OutlinedButton(onPressed: () => _test(Cloudinary.ping), child: const Text('اختبار Cloudinary')),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () async {
            await _save();
            if (mounted) {
              toast(context, 'تم الحفظ ✓');
              Navigator.pop(context);
            }
          },
          child: const Padding(padding: EdgeInsets.all(10), child: Text('حفظ')),
        ),
      ]),
    );
  }
}
