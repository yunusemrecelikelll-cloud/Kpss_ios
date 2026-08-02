import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/attempt.dart';
import '../models/badge.dart';
import '../models/subject.dart';
import '../services/sound_service.dart';
import 'game_stats_screen.dart';
import '../services/storage_service.dart';
import '../theme/design_system.dart';
import '../theme/subject_colors.dart';
import '../theme/theme_provider.dart';

/// Anasayfa'da yalnızca kısa bir stat özeti + "İstatistik" kısayolu gösterilir;
/// TÜM ayrıntılı istatistikler (ders/konu bazlı başarı, seri, çalışma süresi,
/// yanlış bankası, rozet ilerlemesi, deneme geçmişi) buradadır. Profil ya da
/// anasayfadaki "İstatistik" kartından açılır.
///
/// Tamamen StorageService'teki GERÇEK veriden üretilir, hiçbir yer tutucu sayı
/// içermez. Tasarım: tasarım sistemine (DsCard) taşındı; grafikler renkli
/// gradyan çubuklarla ve performansa göre renklenen barlarla canlandırıldı
/// (kullanıcı isteği: "premium tema + daha canlı grafikler + redesign").
class DetailedStatsScreen extends StatelessWidget {
  const DetailedStatsScreen({super.key});

  /// Başarı yüzdesine göre canlı renk (yeşil/sarı/kırmızı).
  static Color _perfColor(int avg, dynamic c) =>
      avg >= 70 ? c.success : (avg >= 45 ? c.warn : c.danger);

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final c = context.watch<ThemeProvider>().colors;

    final overall = storage.computeOverall();
    final streak = storage.getStreak();
    final streakCount = (streak['count'] as num?)?.toInt() ?? 0;
    final bestMarathon = storage.getBestMarathonStreak();
    final wrongCount = storage.getWrongBank().length;
    final unlockedBadges = storage.getUnlockedBadges();
    final totalStudySeconds = storage.getTotalStudyTime();
    final studyTimeBySubject = storage.getStudyTime();
    final attempts = storage.getAttempts()..sort((a, b) => b.tarih.compareTo(a.tarih));

    // Ders bazlı ortalama başarı (sadece en az bir denemesi olan dersler),
    // en yüksekten düşüğe sıralı (grafik ve liste okunur olsun).
    final subjectAverages = <({String id, String label, String icon, int avg})>[];
    for (final meta in kSubjects) {
      final avg = storage.computeSubjectAvg(meta.id);
      if (avg != null) {
        subjectAverages.add((id: meta.id, label: meta.ad, icon: meta.icon, avg: avg));
      }
    }
    subjectAverages.sort((a, b) => b.avg.compareTo(a.avg));

    return Scaffold(
      appBar: AppBar(title: const Text('📊 Detaylı İstatistikler')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Üst özet (premium hero): genel başarı göstergesi ─────────────
            _HeroOzet(
              rate: overall.rate,
              solved: overall.solved,
              tests: overall.tests,
              correct: overall.correct,
            ),
            const SizedBox(height: kDsGap),
            // ── Oyun İstatistikleri kısayolu (kullanıcı isteği) ──────────────
            DsCard(
              accent: c.gold,
              onTap: () {
                context.read<SoundService>().click();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const GameStatsScreen()));
              },
              child: Row(
                children: [
                  DsIconBadge(emoji: '🎮', color: c.gold, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Oyun İstatistikleri',
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w900,
                                color: c.text)),
                        const SizedBox(height: 2),
                        Text(
                            'Oyunlardaki doğru/yanlışlara göre hangi ders iyi, hangisi zayıf',
                            style: TextStyle(fontSize: 12, color: c.textDim)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: c.textDim),
                ],
              ),
            ),
            const SizedBox(height: kDsGap),
            // ── Mini stat ızgarası ───────────────────────────────────────────
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: kDsGap,
              crossAxisSpacing: kDsGap,
              childAspectRatio: 2.1,
              children: [
                _MiniStat(label: 'Toplam Test', value: '${overall.tests}', emoji: '📝', renk: c.violet),
                _MiniStat(label: 'Çözülen Soru', value: '${overall.solved}', emoji: '🎯', renk: c.mint),
                _MiniStat(label: 'Şu Anki Seri', value: '$streakCount gün', emoji: '🔥', renk: c.rose),
                _MiniStat(label: 'En Uzun Maraton', value: '$bestMarathon soru', emoji: '🏃', renk: c.gold),
                _MiniStat(label: 'Toplam Çalışma', value: _fmtStudy(totalStudySeconds), emoji: '⏱️', renk: c.violetL),
                _MiniStat(label: 'Yanlışlar', value: '$wrongCount soru', emoji: '❌', renk: c.danger),
              ],
            ),
            const SizedBox(height: kDsGap),
            // ── Ders bazlı başarı grafiği (renkli gradyan çubuklar) ──────────
            _SectionCard(
              title: '📈 Ders Bazlı Başarı Oranı',
              accent: c.violet,
              child: subjectAverages.isEmpty
                  ? _bosVeri(c, 'Henüz yeterli veri yok. Birkaç test çöz, grafik burada oluşsun.')
                  : SizedBox(
                      height: 220,
                      child: BarChart(
                        BarChartData(
                          maxY: 100,
                          alignment: BarChartAlignment.spaceAround,
                          barTouchData: BarTouchData(
                            enabled: true,
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipColor: (_) => c.bg3,
                              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                                '%${rod.toY.round()}',
                                TextStyle(
                                    color: c.text,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12),
                              ),
                            ),
                          ),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (v) =>
                                FlLine(color: c.border, strokeWidth: 1),
                          ),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                interval: 25,
                                getTitlesWidget: (v, m) => Text('${v.toInt()}',
                                    style: TextStyle(fontSize: 9, color: c.textFaint)),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 42,
                                getTitlesWidget: (value, meta) {
                                  final i = value.toInt();
                                  if (i < 0 || i >= subjectAverages.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final label = subjectAverages[i].label;
                                  final short = label.length > 6 ? label.substring(0, 6) : label;
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(short,
                                        style: TextStyle(fontSize: 9, color: c.textDim)),
                                  );
                                },
                              ),
                            ),
                          ),
                          barGroups: [
                            for (var i = 0; i < subjectAverages.length; i++)
                              BarChartGroupData(x: i, barRods: [
                                BarChartRodData(
                                  toY: subjectAverages[i].avg.toDouble(),
                                  width: 20,
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(6)),
                                  // Her ders kendi renk paletinden gradyanla —
                                  // tek renk yerine canlı, ayırt edilebilir.
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      subjectPaletteFor(subjectAverages[i].id)
                                          .a
                                          .withValues(alpha: 0.55),
                                      subjectPaletteFor(subjectAverages[i].id).b,
                                    ],
                                  ),
                                  backDrawRodData: BackgroundBarChartRodData(
                                    show: true,
                                    toY: 100,
                                    color: c.glass2,
                                  ),
                                ),
                              ]),
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: kDsGap),
            // ── Ders bazlı ayrıntı (performansa göre renkli barlar) ──────────
            _SectionCard(
              title: '📚 Ders Bazlı Ayrıntı',
              accent: c.mint,
              child: subjectAverages.isEmpty
                  ? _bosVeri(c, 'Henüz veri yok.')
                  : Column(
                      children: [
                        for (var i = 0; i < subjectAverages.length; i++) ...[
                          _SubjectDetailRow(
                            icon: subjectAverages[i].icon,
                            label: subjectAverages[i].label,
                            avg: subjectAverages[i].avg,
                            studySeconds: studyTimeBySubject[subjectAverages[i].id] ?? 0,
                            testCount: attempts
                                .where((a) => a.subjectId == subjectAverages[i].id)
                                .length,
                            renk: _perfColor(subjectAverages[i].avg, c),
                          ),
                          if (i < subjectAverages.length - 1)
                            Divider(height: 18, color: c.border),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: kDsGap),
            // ── Rozet ilerlemesi (altın gradyan) ─────────────────────────────
            _SectionCard(
              title: '🏅 Rozet İlerlemesi',
              accent: c.gold,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${unlockedBadges.length} / ${kBadgeDefs.length} rozet açıldı',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13, color: c.text)),
                      Text(
                        '%${kBadgeDefs.isEmpty ? 0 : ((unlockedBadges.length / kBadgeDefs.length) * 100).round()}',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 14, color: c.gold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DsProgressBar(
                    value: kBadgeDefs.isEmpty
                        ? 0
                        : unlockedBadges.length / kBadgeDefs.length,
                    color: c.gold,
                    height: 9,
                  ),
                ],
              ),
            ),
            const SizedBox(height: kDsGap),
            // ── Son denemeler ────────────────────────────────────────────────
            _SectionCard(
              title: '🕓 Son Denemeler',
              accent: c.rose,
              child: attempts.isEmpty
                  ? _bosVeri(c, 'Henüz test çözmedin.')
                  : Column(
                      children: [
                        for (var i = 0; i < attempts.length && i < 10; i++) ...[
                          _AttemptRow(attempt: attempts[i]),
                          if (i < attempts.length - 1 && i < 9)
                            Divider(height: 16, color: c.border),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bosVeri(dynamic c, String metin) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(metin, style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textFaint)),
      );
}

/// Saniyeyi "1sa 20dk" / "45dk" gibi kısa okunur bir süreye çevirir.
String _fmtStudy(int seconds) {
  final minutes = seconds ~/ 60;
  if (minutes < 1) return '0dk';
  final h = minutes ~/ 60, m = minutes % 60;
  return h > 0 ? '${h}sa ${m}dk' : '${m}dk';
}

/// Üstteki premium özet: gradyan zemin + genel başarı halkası ve üç anahtar
/// sayı. Ekrana "detaylı analiz" hissi veren giriş kartı.
class _HeroOzet extends StatelessWidget {
  final int rate, solved, tests, correct;
  const _HeroOzet({
    required this.rate,
    required this.solved,
    required this.tests,
    required this.correct,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kDsRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.violet.withValues(alpha: c.isLight ? 0.16 : 0.28),
            c.rose.withValues(alpha: c.isLight ? 0.10 : 0.18),
          ],
        ),
        border: Border.all(color: c.violet.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          // Başarı halkası
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: (rate / 100).clamp(0.0, 1.0),
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    backgroundColor: c.glass2,
                    valueColor: AlwaysStoppedAnimation<Color>(c.violetL),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('%$rate',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900, color: c.text)),
                    Text('başarı',
                        style: TextStyle(fontSize: 9.5, color: c.textFaint)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Genel Başarın',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w900, color: c.text)),
                const SizedBox(height: 8),
                _satir(c, '🎯', '$correct / $solved doğru'),
                const SizedBox(height: 4),
                _satir(c, '📝', '$tests test çözüldü'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _satir(dynamic c, String emoji, String metin) => Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text(metin, style: TextStyle(fontSize: 12.5, color: c.textDim)),
        ],
      );
}

class _MiniStat extends StatelessWidget {
  final String label, value, emoji;
  final Color renk;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.emoji,
    required this.renk,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return DsCard(
      accent: renk,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Row(
        children: [
          DsIconBadge(emoji: emoji, color: renk, size: 34, glow: false),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w900, color: c.text)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: c.textFaint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Color accent;
  const _SectionCard({required this.title, required this.child, required this.accent});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return DsCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 14.5, color: c.text)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SubjectDetailRow extends StatelessWidget {
  final String icon, label;
  final int avg;
  final int studySeconds;
  final int testCount;
  final Color renk;
  const _SubjectDetailRow({
    required this.icon,
    required this.label,
    required this.avg,
    required this.studySeconds,
    required this.testCount,
    required this.renk,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13, color: c.text)),
              const SizedBox(height: 5),
              DsProgressBar(value: (avg / 100).clamp(0.0, 1.0), color: renk),
              const SizedBox(height: 4),
              Text(
                '$testCount test · ${_fmtStudy(studySeconds)} çalışma',
                style: TextStyle(fontSize: 10.5, color: c.textFaint),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: renk.withValues(alpha: 0.16),
            border: Border.all(color: renk.withValues(alpha: 0.4)),
          ),
          child: Text('%$avg',
              style: TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 13, color: c.text)),
        ),
      ],
    );
  }
}

class _AttemptRow extends StatelessWidget {
  final Attempt attempt;
  const _AttemptRow({required this.attempt});

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final iyi = attempt.skor >= 70;
    final renk = iyi ? c.success : c.warn;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(attempt.topicBaslik,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12.5, color: c.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                '${attempt.subjectAd} · ${_fmtDate(attempt.tarih)} · ${attempt.dogru}/${attempt.toplam} doğru',
                style: TextStyle(fontSize: 10.5, color: c.textFaint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: renk.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: renk.withValues(alpha: 0.4)),
          ),
          child: Text('%${attempt.skor}',
              style: TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 12, color: renk)),
        ),
      ],
    );
  }
}
