import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/attempt.dart';
import '../models/subject.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';
import 'tools_hub_screen.dart';

/// "Bugün Sınava Girsen Kaç Alırsın?" — JS: renderPredictor.
/// Geçmiş ders/konu testlerindeki başarı oranı, 120 soruluk tam deneme
/// dağılımına (kFullTestDist) uygulanarak tahmini bir KPSS puanı hesaplanır.
///
/// Tasarım (kullanıcı isteği): Lig ekranındaki premium vitrin diliyle — koyu
/// degrade zemin, altın aksan, büyük tahmini puan ve rozetler.
class PredictorScreen extends StatelessWidget {
  const PredictorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    if (!storage.isPremiumUser()) {
      return const LockedFeatureCard(
        title: 'Bugün Sınava Girsen Kaç Alırsın?',
        desc:
            "Geçmiş performansına göre tahmini KPSS puanını görmek için Premium'a geç.",
      );
    }

    final c = context.watch<ThemeProvider>().colors;
    final overall = storage.computeOverall();

    if (overall.tests < 1) {
      return Scaffold(
        appBar: AppBar(title: const Text('🎯 Bugün Girsen Kaç Alırsın?')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🎯', style: TextStyle(fontSize: 52)),
                const SizedBox(height: 14),
                Text(
                  'Tahmin üretmek için önce birkaç test çöz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: c.text),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ne kadar çok test çözersen tahmin o kadar isabetli olur.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.textFaint),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final overallRate = overall.rate / 100;
    var dogru = 0, yanlis = 0;
    kFullTestDist.forEach((sid, n) {
      final avg = storage.computeSubjectAvg(sid);
      final rate = avg != null ? avg / 100 : overallRate;
      final d = (n * rate).round();
      dogru += d;
      yanlis += (n - d);
    });
    final k = KpssPoints.compute(dogru: dogru, yanlis: yanlis, toplam: dogru + yanlis);

    return Scaffold(
      appBar: AppBar(title: const Text('🎯 Bugün Girsen Kaç Alırsın?')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _girisAnim(
            sira: 0,
            child: _TahminVitrini(
              net: k.net,
              dogru: dogru,
              yanlis: yanlis,
              p3: k.p3,
              p93: k.p93,
              p94: k.p94,
              testSayisi: overall.tests,
            ),
          ),
          const SizedBox(height: 22),
          _girisAnim(
            sira: 1,
            child: Row(
              children: [
                Icon(Icons.insights_rounded, size: 18, color: c.gold),
                const SizedBox(width: 8),
                Text('Puan Türleri',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: c.text,
                        letterSpacing: 0.2)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _girisAnim(
            sira: 2,
            child: Row(
              children: [
                Expanded(
                    child: _PuanKutusu(
                        etiket: 'KPSSP3', deger: k.p3, aciklama: 'Lisans', renk: c.violet)),
                const SizedBox(width: 10),
                Expanded(
                    child: _PuanKutusu(
                        etiket: 'KPSSP93', deger: k.p93, aciklama: 'Önlisans', renk: c.rose)),
                const SizedBox(width: 10),
                Expanded(
                    child: _PuanKutusu(
                        etiket: 'KPSSP94', deger: k.p94, aciklama: 'Ortaöğretim', renk: c.mint)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _girisAnim(
            sira: 3,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.glass,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: c.textFaint),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bu tahmin, çözdüğün konu/ders testlerindeki ders bazlı başarı '
                      'oranların 120 soruluk tam deneme dağılımına uygulanarak '
                      'hesaplanır. Gerçek sınav sonucu farklı olabilir — daha çok '
                      'test çöz, tahmin daha isabetli olsun.',
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.5,
                          color: c.textFaint,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _girisAnim({required int sira, required Widget child}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + sira * 60),
      curve: Curves.easeOutCubic,
      builder: (context, t, ch) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: ch),
      ),
      child: child,
    );
  }
}

/// Üstteki premium vitrin — Lig ekranıyla aynı dil: koyu degrade zemin, altın
/// aksan, büyük tahmini net + doğru/yanlış/test rozetleri.
class _TahminVitrini extends StatelessWidget {
  final double net;
  final int dogru, yanlis, p3, p93, p94, testSayisi;
  const _TahminVitrini({
    required this.net,
    required this.dogru,
    required this.yanlis,
    required this.p3,
    required this.p93,
    required this.p94,
    required this.testSayisi,
  });

  static Color _koyult(Color renk, double oran) =>
      Color.lerp(Colors.black, renk, oran)!;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final vurgu = c.gold;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _koyult(c.violet, 0.20),
            _koyult(c.violet, 0.34),
            _koyult(vurgu, 0.26),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: vurgu.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: vurgu.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: vurgu.withValues(alpha: 0.45)),
              ),
              child: Text(
                'TAHMİNİ SONUÇ',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                    color: vurgu),
              ),
            ),
            const SizedBox(height: 16),
            Text('🎯', style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 10),
            Text(
              'Bugün girsen tahmini',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.65)),
            ),
            const SizedBox(height: 2),
            // Büyük tahmini NET.
            Text(
              net.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 52,
                height: 1.0,
                fontWeight: FontWeight.w900,
                color: Color.lerp(Colors.white, vurgu, 0.20),
                letterSpacing: 0.5,
              ),
            ),
            Text(
              'NET  •  120 soru üzerinden',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Colors.white.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                    child: _rozet('Doğru', '$dogru', Icons.check_rounded, vurgu)),
                const SizedBox(width: 10),
                Expanded(
                    child: _rozet('Yanlış', '$yanlis', Icons.close_rounded, vurgu)),
                const SizedBox(width: 10),
                Expanded(
                    child: _rozet('Test', '$testSayisi', Icons.history_edu_rounded,
                        vurgu)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _rozet(String etiket, String deger, IconData ikon, Color vurgu) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Icon(ikon, size: 15, color: vurgu.withValues(alpha: 0.9)),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(deger,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
          ),
          const SizedBox(height: 2),
          Text(etiket,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.55))),
        ],
      ),
    );
  }
}

/// Puan türü kutusu (KPSSP3/93/94) — temaya uygun renkli kart.
class _PuanKutusu extends StatelessWidget {
  final String etiket;
  final int deger;
  final String aciklama;
  final Color renk;
  const _PuanKutusu({
    required this.etiket,
    required this.deger,
    required this.aciklama,
    required this.renk,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            renk.withValues(alpha: c.isLight ? 0.16 : 0.26),
            renk.withValues(alpha: c.isLight ? 0.08 : 0.14),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: renk.withValues(alpha: 0.40)),
      ),
      child: Column(
        children: [
          Text(etiket,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                  color: renk)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('$deger',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, color: c.text)),
          ),
          const SizedBox(height: 2),
          Text(aciklama,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: c.textFaint)),
        ],
      ),
    );
  }
}
