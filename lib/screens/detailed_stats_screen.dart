import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/attempt.dart';
import '../models/badge.dart';
import '../models/subject.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';

/// Anasayfa'da sadece kısa bir stat özeti (genel başarı / çözülen soru / konu
/// sayısı — bkz. home_screen.dart _StatCard satırı) gösterilir; TÜM diğer
/// istatistikler (ders/konu bazlı başarı, seri, çalışma süresi, yanlış
/// bankası, rozet ilerlemesi, deneme geçmişi) buraya taşındı. Profil
/// ekranındaki "Detaylı İstatistikler →" kartından açılır.
///
/// Tamamen StorageService'teki GERÇEK veriden üretilir, hiçbir yer tutucu
/// (placeholder) sayı içermez.
class DetailedStatsScreen extends StatelessWidget {
  const DetailedStatsScreen({super.key});

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

    // Ders bazlı ortalama başarı (sadece en az bir denemesi olan dersler).
    final subjectAverages = <({String id, String label, String icon, int avg})>[];
    for (final meta in kSubjects) {
      final avg = storage.computeSubjectAvg(meta.id);
      if (avg != null) subjectAverages.add((id: meta.id, label: meta.ad, icon: meta.icon, avg: avg));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('📊 Detaylı İstatistikler')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.7,
              children: [
                _MiniStat(label: 'Toplam Test', value: '${overall.tests}', icon: '📝', colors: c),
                _MiniStat(label: 'Çözülen Soru', value: '${overall.solved}', icon: '🎯', colors: c),
                _MiniStat(label: 'Şu Anki Seri', value: '$streakCount gün', icon: '🔥', colors: c),
                _MiniStat(label: 'En Uzun Maraton', value: '$bestMarathon soru', icon: '🏃', colors: c),
                _MiniStat(label: 'Toplam Çalışma', value: _fmtStudy(totalStudySeconds), icon: '⏱️', colors: c),
                _MiniStat(label: 'Yanlışlar Bankası', value: '$wrongCount soru', icon: '❌', colors: c),
              ],
            ),
            const SizedBox(height: 18),
            _SectionCard(
              colors: c,
              title: '📈 Ders Bazlı Başarı Oranı',
              child: subjectAverages.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Henüz yeterli veri yok. Birkaç test çöz, grafik burada oluşsun.',
                        style: TextStyle(fontSize: 12.5, color: c.textFaint),
                      ),
                    )
                  : SizedBox(
                      height: 220,
                      child: BarChart(
                        BarChartData(
                          maxY: 100,
                          alignment: BarChartAlignment.spaceAround,
                          barTouchData: BarTouchData(enabled: false),
                          gridData: const FlGridData(show: true, drawVerticalLine: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: true, reservedSize: 32, interval: 25),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 42,
                                getTitlesWidget: (value, meta) {
                                  final i = value.toInt();
                                  if (i < 0 || i >= subjectAverages.length) return const SizedBox.shrink();
                                  final label = subjectAverages[i].label;
                                  final short = label.length > 6 ? label.substring(0, 6) : label;
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(short, style: const TextStyle(fontSize: 9)),
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
                                  color: c.violet,
                                  width: 20,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ]),
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              colors: c,
              title: '📚 Ders Bazlı Ayrıntı',
              child: subjectAverages.isEmpty
                  ? Text('Henüz veri yok.', style: TextStyle(fontSize: 12.5, color: c.textFaint))
                  : Column(
                      children: [
                        for (var i = 0; i < subjectAverages.length; i++) ...[
                          _SubjectDetailRow(
                            icon: subjectAverages[i].icon,
                            label: subjectAverages[i].label,
                            avg: subjectAverages[i].avg,
                            studySeconds: studyTimeBySubject[subjectAverages[i].id] ?? 0,
                            testCount: attempts.where((a) => a.subjectId == subjectAverages[i].id).length,
                            colors: c,
                          ),
                          if (i < subjectAverages.length - 1) const Divider(height: 18),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              colors: c,
              title: '🏅 Rozet İlerlemesi',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${unlockedBadges.length} / ${kBadgeDefs.length} rozet açıldı',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      Text(
                        '%${kBadgeDefs.isEmpty ? 0 : ((unlockedBadges.length / kBadgeDefs.length) * 100).round()}',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: c.gold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: kBadgeDefs.isEmpty ? 0 : unlockedBadges.length / kBadgeDefs.length,
                      minHeight: 8,
                      color: c.gold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              colors: c,
              title: '🕓 Son Denemeler',
              child: attempts.isEmpty
                  ? Text('Henüz test çözmedin.', style: TextStyle(fontSize: 12.5, color: c.textFaint))
                  : Column(
                      children: [
                        for (var i = 0; i < attempts.length && i < 10; i++) ...[
                          _AttemptRow(attempt: attempts[i], colors: c),
                          if (i < attempts.length - 1 && i < 9) const Divider(height: 16),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Saniyeyi "1sa 20dk" / "45dk" gibi kısa okunur bir süreye çevirir.
/// (home_screen.dart'taki _fmtStudyShort ile aynı mantık.)
String _fmtStudy(int seconds) {
  final minutes = seconds ~/ 60;
  if (minutes < 1) return '0dk';
  final h = minutes ~/ 60, m = minutes % 60;
  return h > 0 ? '${h}sa ${m}dk' : '${m}dk';
}

class _MiniStat extends StatelessWidget {
  final String label, value, icon;
  final KpssColors colors;
  const _MiniStat({required this.label, required this.value, required this.icon, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            Text(label, style: TextStyle(fontSize: 10.5, color: colors.textFaint)),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final KpssColors colors;
  const _SectionCard({required this.title, required this.child, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SubjectDetailRow extends StatelessWidget {
  final String icon, label;
  final int avg;
  final int studySeconds;
  final int testCount;
  final KpssColors colors;
  const _SubjectDetailRow({
    required this.icon,
    required this.label,
    required this.avg,
    required this.studySeconds,
    required this.testCount,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: avg / 100, minHeight: 6),
              ),
              const SizedBox(height: 4),
              Text(
                '$testCount test · ${_fmtStudy(studySeconds)} çalışma',
                style: TextStyle(fontSize: 10.5, color: colors.textFaint),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text('%$avg', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
      ],
    );
  }
}

class _AttemptRow extends StatelessWidget {
  final Attempt attempt;
  final KpssColors colors;
  const _AttemptRow({required this.attempt, required this.colors});

  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(attempt.topicBaslik,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                '${attempt.subjectAd} · ${_fmtDate(attempt.tarih)} · ${attempt.dogru}/${attempt.toplam} doğru',
                style: TextStyle(fontSize: 10.5, color: colors.textFaint),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (attempt.skor >= 70 ? colors.success : colors.warn).withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '%${attempt.skor}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: attempt.skor >= 70 ? colors.success : colors.warn,
            ),
          ),
        ),
      ],
    );
  }
}
