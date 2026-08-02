import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/subject.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';

/// Oyun İstatistikleri (kullanıcı isteği): oyunlarda verilen doğru/yanlış
/// cevaplar ders bazında toplanır; hangi dersin zayıf hangisinin iyi olduğu
/// hem GENEL hem de OYUN BAZINDA yorumlanır (bkz. StorageService.addGameAnswer /
/// getGameStatsBySubject / getGameStatsByGame).
class GameStatsScreen extends StatelessWidget {
  const GameStatsScreen({super.key});

  static String _dersAd(String id) {
    for (final s in kSubjects) {
      if (s.id == id) return '${s.icon} ${s.ad}';
    }
    if (id == 'genel') return '🎮 Genel';
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final storage = context.watch<StorageService>();
    final bySubject = storage.getGameStatsBySubject();
    final byGame = storage.getGameStatsByGame();

    // Ders bazlı başarı yüzdeleri (en az 1 cevap olan dersler).
    final dersOran = <String, double>{};
    final dersToplam = <String, int>{};
    bySubject.forEach((sid, m) {
      final d = m['d'] ?? 0, y = m['y'] ?? 0, t = d + y;
      if (t > 0) {
        dersOran[sid] = d * 100 / t;
        dersToplam[sid] = t;
      }
    });
    final sirali = dersOran.keys.toList()
      ..sort((a, b) => dersOran[b]!.compareTo(dersOran[a]!));

    return Scaffold(
      appBar: AppBar(
        title: const Text('🎮 Oyun İstatistikleri'),
        actions: [
          if (dersOran.isNotEmpty)
            IconButton(
              tooltip: 'Sıfırla',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    content: const Text('Oyun istatistikleri sıfırlansın mı?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Vazgeç')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Sıfırla')),
                    ],
                  ),
                );
                if (ok == true) await storage.clearGameStats();
              },
            ),
        ],
      ),
      body: dersOran.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🎮', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text('Henüz oyun verisi yok',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: c.text)),
                    const SizedBox(height: 6),
                    Text(
                      'Oyunları oynadıkça verdiğin doğru/yanlış cevaplar burada '
                      'ders bazında toplanır ve hangi derste iyi/zayıf olduğun '
                      'yorumlanır.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: c.textFaint),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── GENEL YORUM ──
                _yorumKarti(context, sirali, dersOran, dersToplam),
                const SizedBox(height: 18),
                Text('Ders Bazında Başarı (Tüm Oyunlar)',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: c.text)),
                const SizedBox(height: 10),
                for (final sid in sirali)
                  _dersSatiri(context, sid, dersOran[sid]!, bySubject[sid]!),
                const SizedBox(height: 18),
                Text('Oyun Bazında',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: c.text)),
                const SizedBox(height: 10),
                for (final entry in byGame.entries)
                  _oyunKarti(context, entry.key, entry.value),
              ],
            ),
    );
  }

  Widget _yorumKarti(BuildContext context, List<String> sirali,
      Map<String, double> oran, Map<String, int> toplam) {
    final c = context.watch<ThemeProvider>().colors;
    final iyi = sirali.first;
    final zayif = sirali.last;
    final toplamCevap = toplam.values.fold(0, (a, b) => a + b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.violet.withValues(alpha: 0.20),
            c.mint.withValues(alpha: 0.14),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.violet.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🧭', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text('Genel Değerlendirme',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: c.text)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Oyunlarda toplam $toplamCevap cevap verdin. '
            'En iyi olduğun ders ${_dersAd(iyi)} (%${oran[iyi]!.round()} başarı). '
            '${sirali.length > 1 ? "En çok gelişmen gereken ders ise ${_dersAd(zayif)} (%${oran[zayif]!.round()})." : ""}',
            style: TextStyle(fontSize: 13, height: 1.5, color: c.text),
          ),
        ],
      ),
    );
  }

  Widget _dersSatiri(
      BuildContext context, String sid, double oran, Map<String, int> m) {
    final c = context.watch<ThemeProvider>().colors;
    final d = m['d'] ?? 0, y = m['y'] ?? 0;
    final renk = oran >= 70
        ? c.success
        : (oran >= 45 ? c.warn : c.danger);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_dersAd(sid),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: c.text)),
              ),
              Text('%${oran.round()}',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15, color: renk)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (oran / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: c.glass2,
              valueColor: AlwaysStoppedAnimation<Color>(renk),
            ),
          ),
          const SizedBox(height: 6),
          Text('✔ $d doğru • ✘ $y yanlış',
              style: TextStyle(fontSize: 11.5, color: c.textFaint)),
        ],
      ),
    );
  }

  Widget _oyunKarti(BuildContext context, String gameId,
      Map<String, Map<String, int>> dersler) {
    final c = context.watch<ThemeProvider>().colors;
    // Oyunun genel doğrusu/yanlışı.
    var d = 0, y = 0;
    dersler.forEach((_, m) {
      d += m['d'] ?? 0;
      y += m['y'] ?? 0;
    });
    final t = d + y;
    if (t == 0) return const SizedBox.shrink();
    // Bu oyundaki en iyi/zayıf ders.
    String? iyi, zayif;
    double iyiO = -1, zayifO = 101;
    dersler.forEach((sid, m) {
      final tt = (m['d'] ?? 0) + (m['y'] ?? 0);
      if (tt == 0) return;
      final o = (m['d'] ?? 0) * 100 / tt;
      if (o > iyiO) {
        iyiO = o;
        iyi = sid;
      }
      if (o < zayifO) {
        zayifO = o;
        zayif = sid;
      }
    });
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.glass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_oyunAd(gameId),
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 13, color: c.text)),
          const SizedBox(height: 4),
          Text('%${(d * 100 / t).round()} başarı • $t cevap',
              style: TextStyle(fontSize: 11.5, color: c.textFaint)),
          if (iyi != null && dersler.length > 1) ...[
            const SizedBox(height: 6),
            Text(
              'Bu oyunda en iyi: ${_dersAd(iyi!)} (%${iyiO.round()})'
              '${zayif != null && zayif != iyi ? " • zayıf: ${_dersAd(zayif!)} (%${zayifO.round()})" : ""}',
              style: TextStyle(fontSize: 11.5, height: 1.4, color: c.textDim),
            ),
          ],
        ],
      ),
    );
  }

  static String _oyunAd(String gameId) {
    const adlar = {
      'map_ili_bul': '🔎 İli Bul',
      'map_bolge_bul': '🧭 Bölgeyi Bul',
      'map_komsu_il': '🤝 Komşu İl',
      'map_tarih_haritasi': '🕰️ Tarih Haritası',
      'map_iklim_avi': '☀️ İklim Avı',
      'map_urun_haritasi': '🗺️ Konu Haritası',
      'duello': '⚔️ Düello',
    };
    return adlar[gameId] ?? gameId;
  }
}
