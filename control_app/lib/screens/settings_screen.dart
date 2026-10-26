import 'package:flutter/material.dart';
import '../core/cloudinary.dart';
import '../core/github.dart';
import '../core/store.dart';
import '../widgets/ui.dart';

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
  final cloud = TextEditingController(text: Store.clCloud);
  final key = TextEditingController(text: Store.clKey);
  final secret = TextEditingController(text: Store.clSecret);
  bool _show = false;

  Future<void> _save() async {
    await Store.setAll({
      'gh_token': token.text,
      'gh_owner': owner.text,
      'gh_repo': repo.text,
      'gh_branch': branch.text.isEmpty ? 'main' : branch.text,
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
