import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/theme_provider.dart';

/// Test ekranlarında sorunun hemen altında açılan KARALAMA (scratchpad) katmanı
/// (kullanıcı isteği). İçinde hem PARMAKLA ÇİZİM hem de YAZI yazılabilir; alan
/// cevapların üzerinde durur, aşağı kaymaz — çağıran ekranda "sonraki soru"
/// butonlarının ÜZERİNDE, sabit bir konumda gösterilir. Sağ üstteki ✕ ile
/// kapatılır.
///
/// Durum (çizgiler + yazı) çağıran ekranda TUTULMAZ; bu widget kendi içinde
/// saklar. Aynı test oturumunda açılıp kapandığında notlar korunur diye
/// state'i çağıran, bu widget'ı ağaçta tutup yalnızca görünürlüğünü değiştirerek
/// (Offstage/Visibility yerine koşullu ekleme + AnimatedSlide) yönetebilir; en
/// basit kullanım için burada kendi state'ini korur.
class KaralamaKatmani extends StatefulWidget {
  final VoidCallback onKapat;
  const KaralamaKatmani({super.key, required this.onKapat});

  @override
  State<KaralamaKatmani> createState() => _KaralamaKatmaniState();
}

class _Cizgi {
  final List<Offset> noktalar;
  final Color renk;
  final double kalinlik;
  _Cizgi(this.renk, this.kalinlik) : noktalar = [];
}

class _KaralamaKatmaniState extends State<KaralamaKatmani> {
  final List<_Cizgi> _cizgiler = [];
  _Cizgi? _aktif;
  final TextEditingController _yaziCtrl = TextEditingController();

  // Mod: true => çizim (parmakla çiz), false => yazı (klavye).
  bool _cizimModu = true;

  // Kalem renkleri.
  static const List<Color> _renkler = [
    Color(0xFF111111),
    Color(0xFF2563EB),
    Color(0xFFEF4444),
    Color(0xFF16A34A),
    Color(0xFFF59E0B),
  ];
  Color _renk = _renkler[1];
  double _kalinlik = 3;

  @override
  void dispose() {
    _yaziCtrl.dispose();
    super.dispose();
  }

  void _temizle() {
    setState(() {
      _cizgiler.clear();
      _aktif = null;
      _yaziCtrl.clear();
    });
  }

  void _geriAl() {
    if (_cizgiler.isEmpty) return;
    setState(() => _cizgiler.removeLast());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: Color.alphaBlend(c.violet.withValues(alpha: 0.06), c.bg2),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.violet.withValues(alpha: 0.40), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Araç çubuğu ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              decoration: BoxDecoration(
                color: c.glass2,
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  const Text('✏️', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: 6),
                  Text('Karalama',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: c.text)),
                  const SizedBox(width: 10),
                  // Mod geçişi: Çiz / Yaz.
                  _ModCip(
                    label: 'Çiz',
                    aktif: _cizimModu,
                    renk: c.violet,
                    onTap: () => setState(() => _cizimModu = true),
                  ),
                  const SizedBox(width: 6),
                  _ModCip(
                    label: 'Yaz',
                    aktif: !_cizimModu,
                    renk: c.violet,
                    onTap: () => setState(() => _cizimModu = false),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Geri al',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.undo_rounded, size: 19, color: c.textDim),
                    onPressed: _geriAl,
                  ),
                  IconButton(
                    tooltip: 'Temizle',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 19, color: c.textDim),
                    onPressed: _temizle,
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, size: 20, color: c.text),
                    onPressed: widget.onKapat,
                  ),
                ],
              ),
            ),
            // ── Renk / kalınlık şeridi (yalnızca çizim modunda) ─────────
            if (_cizimModu)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: c.glass,
                child: Row(
                  children: [
                    for (final r in _renkler) ...[
                      _RenkNoktasi(
                        renk: r,
                        secili: _renk == r,
                        onTap: () => setState(() => _renk = r),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Spacer(),
                    Icon(Icons.line_weight_rounded, size: 16, color: c.textFaint),
                    SizedBox(
                      width: 110,
                      child: Slider(
                        value: _kalinlik,
                        min: 1,
                        max: 10,
                        onChanged: (v) => setState(() => _kalinlik = v),
                      ),
                    ),
                  ],
                ),
              ),
            // ── Çizim + yazı alanı ──────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  // Çizim yüzeyi.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _cizimModu
                          ? (d) {
                              setState(() {
                                _aktif = _Cizgi(_renk, _kalinlik)
                                  ..noktalar.add(d.localPosition);
                                _cizgiler.add(_aktif!);
                              });
                            }
                          : null,
                      onPanUpdate: _cizimModu
                          ? (d) => setState(
                              () => _aktif?.noktalar.add(d.localPosition))
                          : null,
                      onPanEnd: _cizimModu ? (_) => _aktif = null : null,
                      child: CustomPaint(
                        painter: _CizimPainter(_cizgiler),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                  // Yazı alanı (yalnızca yazı modunda dokunuşları alır).
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: _cizimModu,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: TextField(
                          controller: _yaziCtrl,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          style: TextStyle(
                              fontSize: 14, height: 1.4, color: c.text),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: _cizimModu
                                ? null
                                : 'Buraya not yazabilirsin…',
                            hintStyle: TextStyle(color: c.textFaint),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModCip extends StatelessWidget {
  final String label;
  final bool aktif;
  final Color renk;
  final VoidCallback onTap;
  const _ModCip(
      {required this.label,
      required this.aktif,
      required this.renk,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: aktif ? renk : c.glass2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: aktif ? renk : c.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: aktif ? Colors.white : c.textDim)),
      ),
    );
  }
}

class _RenkNoktasi extends StatelessWidget {
  final Color renk;
  final bool secili;
  final VoidCallback onTap;
  const _RenkNoktasi(
      {required this.renk, required this.secili, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: renk,
          shape: BoxShape.circle,
          border: Border.all(
            color: secili ? Colors.white : Colors.white24,
            width: secili ? 3 : 1,
          ),
          boxShadow: secili
              ? [BoxShadow(color: renk.withValues(alpha: 0.6), blurRadius: 6)]
              : null,
        ),
      ),
    );
  }
}

class _CizimPainter extends CustomPainter {
  final List<_Cizgi> cizgiler;
  _CizimPainter(this.cizgiler);

  @override
  void paint(Canvas canvas, Size size) {
    for (final cizgi in cizgiler) {
      if (cizgi.noktalar.isEmpty) continue;
      final p = Paint()
        ..color = cizgi.renk
        ..strokeWidth = cizgi.kalinlik
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (cizgi.noktalar.length == 1) {
        canvas.drawPoints(PointMode.points, cizgi.noktalar, p);
        continue;
      }
      final path = Path()..moveTo(cizgi.noktalar.first.dx, cizgi.noktalar.first.dy);
      for (var i = 1; i < cizgi.noktalar.length; i++) {
        path.lineTo(cizgi.noktalar[i].dx, cizgi.noktalar[i].dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _CizimPainter old) => true;
}
