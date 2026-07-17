import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';

class _DistRow {
  final String icon;
  final String ad;
  final int soru;
  final Color renk;
  const _DistRow(this.icon, this.ad, this.soru, this.renk);
}

/// Gerçek KPSS Genel Yetenek / Genel Kültür soru dağılımı — Lisans, Önlisans
/// ve Ortaöğretim sınavlarında bu dağılım pratikte birebir aynıdır (kaynak:
/// kitapsec.com KPSS konu/soru dağılımı sayfaları, 2026).
const List<_DistRow> _kGenelYetenek = [
  _DistRow('📖', 'Türkçe', 30, Color(0xFF6366F1)),
  _DistRow('🔢', 'Matematik ve Geometri', 30, Color(0xFF0EA5E9)),
];

const List<_DistRow> _kGenelKultur = [
  _DistRow('🏛️', 'Tarih', 27, Color(0xFF92400E)),
  _DistRow('🗺️', 'Coğrafya', 18, Color(0xFF059669)),
  _DistRow('⚖️', 'Vatandaşlık', 9, Color(0xFF475569)),
  _DistRow('📰', 'Güncel Bilgiler', 6, Color(0xFFE11D48)),
];

class ScoreDistributionScreen extends StatelessWidget {
  const ScoreDistributionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final all = [..._kGenelYetenek, ..._kGenelKultur];
    final total = all.fold<int>(0, (s, r) => s + r.soru);

    return Scaffold(
      appBar: AppBar(title: const Text('📊 Soru Dağılımı')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'KPSS $total soruluk Genel Yetenek – Genel Kültür testinden oluşur. '
              'Bu dağılım Lisans, Önlisans ve Ortaöğretim sınavlarında pratikte aynıdır.',
              style: TextStyle(fontSize: 13, color: c.textFaint, height: 1.5),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 22,
                child: Row(
                  children: [
                    for (final r in all)
                      Expanded(
                        flex: r.soru,
                        child: Container(color: r.renk),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _SectionTitle(title: 'Genel Yetenek (60 soru)', c: c),
            for (final r in _kGenelYetenek) _DistCard(row: r, total: total, c: c),
            const SizedBox(height: 16),
            _SectionTitle(title: 'Genel Kültür (60 soru)', c: c),
            for (final r in _kGenelKultur) _DistCard(row: r, total: total, c: c),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final KpssColors c;
  const _SectionTitle({required this.title, required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: c.violet)),
    );
  }
}

class _DistCard extends StatelessWidget {
  final _DistRow row;
  final int total;
  final KpssColors c;
  const _DistCard({required this.row, required this.total, required this.c});

  @override
  Widget build(BuildContext context) {
    final pct = row.soru / total;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: row.renk.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: row.renk.withValues(alpha: 0.16),
                  ),
                  child: Center(child: Text(row.icon, style: const TextStyle(fontSize: 18))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(row.ad, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ),
                Text('${row.soru} soru',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: row.renk)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: row.renk.withValues(alpha: 0.12),
                color: row.renk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
