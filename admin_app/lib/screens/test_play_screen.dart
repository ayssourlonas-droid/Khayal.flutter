import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class TestPlayScreen extends StatefulWidget {
  final String url;
  const TestPlayScreen({super.key, required this.url});
  @override
  State<TestPlayScreen> createState() => _TestPlayScreenState();
}

class _TestPlayScreenState extends State<TestPlayScreen> {
  late final WebViewController _c = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(Uri.parse(widget.url));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تجربة اللعبة'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: () => _c.reload()),
      ]),
      body: WebViewWidget(controller: _c),
    );
  }
}
