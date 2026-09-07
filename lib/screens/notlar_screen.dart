import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/karalama_not_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import '../widgets/kodlama_notu.dart'
    show kodlamaKagitRengi, kodlamaMurekkep;

/// "Notlar" ekranı (kullanıcı isteği): testlerdeki KARALAMA katmanında
/// kaydedilen yazı/çizim notları, Akılda Kalıcı Kodlama ekranındaki yapışkan
/// not kâğıdı boyut/diliyle 2 sütunlu masonry olarak listelenir. Her kartın
/// ÖNİZLEMESİ kullanıcının yazdığı/karaladığı içeriktir.
class NotlarScreen extends StatefulWidget {
  const NotlarScreen({super.key});

  @override
  State<NotlarScreen> createState() => _NotlarScreenState();
}

class _NotlarScreenState extends State<NotlarScreen> {
  final KaralamaNotService _svc = KaralamaNotService();
  List<KaralamaNot> _notlar = [];

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  void _yukle() {
    _notlar = _svc.getir(context.read<StorageService>());
  }

  Future<void> _sil(KaralamaNot n) async {
    context.read<SoundService>().click();
    await _svc.sil(context.read<StorageService>(), n.id);
    setState(_yukle);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(title: const Text('📝 Notlar')),
      body: SafeArea(
        child: _notlar.isEmpty
            ? _bosDurum(c)
            : ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Text(
                    'Testlerdeki karalama alanında "Kaydet" dediğin yazı ve '
                    'çizimler burada durur.',
                    style: TextStyle(fontSize: 12.5, color: c.textFaint),
                  ),
                  const SizedBox(height: 14),
                  _masonry(c),
                ],
              ),
      ),
    );
  }

  Widget _bosDurum(KpssColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🗒️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 10),
            Text('Henüz not yok',
                style: TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 15, color: c.text)),
            const SizedBox(height: 6),
            Text(
              'Bir test çözerken alttaki ✏️ karalama alanını aç, yaz ya da çiz '
              've "Kaydet" de — notların burada birikir.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: c.textFaint),
            ),
          ],
        ),
      ),
    );
  }

  /// Akılda Kalıcı Kodlama ile aynı 2 sütunlu yapışkan not masonry'si.
  Widget _masonry(KpssColors c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _notlar.length; i += 2) ...[
                _NotKarti(
                    not: _notlar[i], index: i, colors: c, onSil: () => _sil(_notlar[i])),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 1; i < _notlar.length; i += 2) ...[
                _NotKarti(
                    not: _notlar[i], index: i, colors: c, onSil: () => _sil(_notlar[i])),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Tek not kartı — yapışkan not kâğıdı görünümü (Akılda Kalıcı Kodlama dili):
/// renkli kâğıt + üst bant + kıvrık köşe; içinde ÇİZİM ÖNİZLEMESİ ve/veya yazı.
class _NotKarti extends StatelessWidget {
  final KaralamaNot not;
  final int index;
  final KpssColors colors;
  final VoidCallback onSil;
  const _NotKarti(
      {required this.not,
      required this.index,
      required this.colors,
      required this.onSil});

  @override
  Widget build(BuildContext context) {
    final acikTema = colors.isLight;
    final kagit = kodlamaKagitRengi(index, acikTema);
    final ink = kodlamaMurekkep(acikTema);
    final egim = ((index % 5) - 2) * 0.008;

    return Transform.rotate(
      angle: egim,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: acikTema ? 0.16 : 0.42),
              blurRadius: 12,
              offset: const Offset(2, 6),
            ),
          ],
        ),
        child: Material(
          color: kagit,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ink.withValues(alpha: 0.10)),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Kaynak rozeti (hangi ders/konu ya da KPSS Düello) ──
                      if (not.kaynak.trim().isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: ink.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: ink.withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.label_important_outline_rounded,
                                  size: 12, color: ink.withValues(alpha: 0.6)),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  not.kaynak.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: ink.withValues(alpha: 0.7)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // ── Çizim önizlemesi ──
                      if (not.cizimVar) ...[
                        AspectRatio(
                          aspectRatio: not.w <= 0 || not.h <= 0
                              ? 3 / 2
                              : (not.w / not.h).clamp(0.6, 2.4),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: ink.withValues(alpha: 0.12)),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: CustomPaint(
                              painter: KaralamaOnizlemePainter(not),
                              size: Size.infinite,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // ── Yazı ──
                      if (not.metinVar)
                        Text(
                          not.metin.trim(),
                          maxLines: not.cizimVar ? 4 : 8,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: Color(not.metinRenk),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.push_pin_rounded,
                              size: 11, color: ink.withValues(alpha: 0.35)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _tarih(not.createdAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: ink.withValues(alpha: 0.45)),
                            ),
                          ),
                          InkWell(
                            onTap: onSil,
                            borderRadius: BorderRadius.circular(999),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Icon(Icons.delete_outline_rounded,
                                  size: 16,
                                  color: ink.withValues(alpha: 0.55)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Üstteki yapışkan bant
                Positioned(
                  top: 4,
                  left: 16,
                  child: Transform.rotate(
                    angle: -0.10,
                    child: Container(
                      width: 46,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.white
                            .withValues(alpha: acikTema ? 0.65 : 0.16),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                // Sağ alt kıvrık köşe
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                        bottomRight: Radius.circular(10)),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: Transform.rotate(
                        angle: 0.785,
                        origin: const Offset(6, 6),
                        child: Container(
                            color:
                                ink.withValues(alpha: acikTema ? 0.10 : 0.18)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _tarih(int ms) {
    if (ms <= 0) return 'Not';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    const aylar = [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
    ];
    return '${d.day} ${aylar[d.month - 1]} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

/// Küçük alanlar için (ör. anasayfadaki "Notlar" kartı) tek notun kompakt
/// önizlemesi: çizim varsa orantılı çizim, yoksa yazının ilk satırları.
class KaralamaMiniOnizleme extends StatelessWidget {
  final KaralamaNot not;
  const KaralamaMiniOnizleme({super.key, required this.not});

  @override
  Widget build(BuildContext context) {
    if (not.cizimVar) {
      return CustomPaint(
        painter: KaralamaOnizlemePainter(not),
        size: Size.infinite,
      );
    }
    return Align(
      alignment: Alignment.topLeft,
      child: Text(
        not.metin.trim(),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 11.5,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: Color(not.metinRenk).withValues(alpha: 1)),
      ),
    );
  }
}

/// Kaydedilmiş çizgileri kartın önizleme alanına ORANTILI ölçekleyerek çizer.
class KaralamaOnizlemePainter extends CustomPainter {
  final KaralamaNot not;
  KaralamaOnizlemePainter(this.not);

  @override
  void paint(Canvas canvas, Size size) {
    final srcW = not.w <= 0 ? size.width : not.w;
    final srcH = not.h <= 0 ? size.height : not.h;
    final sx = size.width / srcW;
    final sy = size.height / srcH;
    for (final ciz in not.cizgiler) {
      final pts = ciz.noktalar;
      if (pts.length < 2) continue;
      final p = Paint()
        ..color = Color(ciz.renk)
        ..strokeWidth = (ciz.kalinlik * sx).clamp(0.6, 8.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final noktalar = <Offset>[
        for (var i = 0; i + 1 < pts.length; i += 2)
          Offset(pts[i] * sx, pts[i + 1] * sy)
      ];
      if (noktalar.length == 1) {
        canvas.drawPoints(PointMode.points, noktalar, p);
        continue;
      }
      final path = Path()..moveTo(noktalar.first.dx, noktalar.first.dy);
      for (var i = 1; i < noktalar.length; i++) {
        path.lineTo(noktalar[i].dx, noktalar[i].dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant KaralamaOnizlemePainter old) => old.not.id != not.id;
}
