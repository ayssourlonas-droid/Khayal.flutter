import 'package:flutter/material.dart';

import '../core/colors.dart';
import 'design.dart';

/// يقابل AlertPopup.gd — نافذة تنبيه 800x500 بحدود بنفسجية وتوهج،
/// 1–3 أزرار 220x100 بلوحة ألوان، دخول بتكبير/تلاشٍ 0.25 ث وخروج 0.2 ث.
class PopupBtn {
  final String text;

  /// 1 أحمر، 2 أخضر، 3 أزرق، 4 أصفر، 5 بنفسجي
  final int color;
  const PopupBtn(this.text, [this.color = 5]);
}

const _palette = <int, Color>{
  1: Color.fromRGBO(230, 51, 51, 1), // (0.9,0.2,0.2)
  2: Color.fromRGBO(51, 204, 51, 1), // (0.2,0.8,0.2)
  3: Color.fromRGBO(51, 128, 242, 1), // (0.2,0.5,0.95)
  4: Color.fromRGBO(242, 204, 26, 1), // (0.95,0.8,0.1)
  5: Color.fromRGBO(179, 77, 230, 1), // (0.7,0.3,0.9)
};

/// يرجع فهرس الزر المضغوط (0-based).
Future<int> showAlertPopup(
  BuildContext context, {
  required String title,
  required String message,
  List<PopupBtn> buttons = const [PopupBtn('حسناً', 5)],
}) async {
  final r = await showGeneralDialog<int>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (ctx, a, b) => PopScope(
      canPop: false,
      child: Design(builder: (c, h) => Center(child: _Popup(title: title, message: message, buttons: buttons))),
    ),
    transitionBuilder: (ctx, anim, sec, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween<double>(begin: 0.7, end: 1).animate(curved), child: child),
      );
    },
  );
  return r ?? 0;
}

class _Popup extends StatelessWidget {
  final String title, message;
  final List<PopupBtn> buttons;
  const _Popup({required this.title, required this.message, required this.buttons});

  @override
  Widget build(BuildContext context) {
    final btns = buttons.take(3).toList();
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 800,
        height: 500,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.98),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: AppColors.popupBorder, width: 5),
                boxShadow: [BoxShadow(color: AppColors.popupBorder.withOpacity(0.6), blurRadius: 30)],
              ),
              padding: const EdgeInsets.fromLTRB(40, 90, 40, 30),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(fontSize: 34, color: Colors.white, height: 1.35),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < btns.length; i++) ...[
                        if (i > 0) const SizedBox(width: 20),
                        _PopupButton(
                          btn: btns[i],
                          onTap: () => Navigator.of(context).pop(i),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 18,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.popupBorder,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(title,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontSize: 38, color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopupButton extends StatelessWidget {
  final PopupBtn btn;
  final VoidCallback onTap;
  const _PopupButton({required this.btn, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final base = _palette[btn.color] ?? _palette[5]!;
    final bg = Color.lerp(base, Colors.white, 0.85)!;
    final fg = Color.lerp(base, Colors.black, 0.5)!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        height: 100,
        padding: const EdgeInsets.only(bottom: 5),
        decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(15)),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15), bottom: Radius.circular(10)),
          ),
          child: Text(btn.text,
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 34, color: fg, decoration: TextDecoration.none)),
        ),
      ),
    );
  }
}
