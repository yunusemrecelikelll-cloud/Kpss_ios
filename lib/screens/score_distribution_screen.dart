import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';

/// Bir dersin içindeki tek bir konunun ortalama soru adedi.
class _KonuSatiri {
  final String ad;
  final int ortalama;
  const _KonuSatiri(this.ad, this.ortalama);
}

class _DistRow {
  final String icon;
  final String ad;
  final int soru;
  final Color renk;

  /// Konu bazlı kırılım: 2002-2025 arası çıkmış KPSS sorularının konulara göre
  /// YAKLAŞIK ortalaması. ÖSYM yıldan yıla 1-2 soru oynatır; buradaki sayılar
  /// kesin bir taahhüt değil, uzun dönem ortalamasıdır ve toplamları dersin
  /// soru sayısına eşittir.
  final List<_KonuSatiri> konular;
  const _DistRow(this.icon, this.ad, this.soru, this.renk, this.konular);
}

/// Gerçek KPSS Genel Yetenek / Genel Kültür soru dağılımı — Lisans, Önlisans
/// ve Ortaöğretim sınavlarında bu dağılım pratikte birebir aynıdır (kaynak:
/// kitapsec.com KPSS konu/soru dağılımı sayfaları, 2026; konu kırılımları
/// 2002-2025 çıkmış soru analizlerinin yaklaşık ortalamasıdır).
const List<_DistRow> _kGenelYetenek = [
  _DistRow('📖', 'Türkçe', 30, Color(0xFF6366F1), [
    _KonuSatiri('Paragraf (anlam, yapı, anlatım)', 15),
    _KonuSatiri('Cümlede Anlam', 4),
    _KonuSatiri('Sözcükte Anlam', 3),
    _KonuSatiri('Sözel Mantık', 2),
    _KonuSatiri('Dil Bilgisi', 2),
    _KonuSatiri('Yazım Kuralları', 2),
    _KonuSatiri('Noktalama İşaretleri', 2),
  ]),
  _DistRow('🔢', 'Matematik ve Geometri', 30, Color(0xFF0EA5E9), [
    _KonuSatiri('Problemler (yaş, işçi, hız, yüzde...)', 9),
    _KonuSatiri('Temel Kavramlar ve Sayılar', 6),
    _KonuSatiri('Sayısal Mantık', 3),
    _KonuSatiri('Geometri', 3),
    _KonuSatiri('Rasyonel ve Ondalık Sayılar', 2),
    _KonuSatiri('Üslü ve Köklü Sayılar', 2),
    _KonuSatiri('Oran - Orantı', 2),
    _KonuSatiri('Bölme - Bölünebilme', 1),
    _KonuSatiri('Kümeler ve Fonksiyonlar', 1),
    _KonuSatiri('Olasılık - Permütasyon', 1),
  ]),
];

const List<_DistRow> _kGenelKultur = [
  _DistRow('🏛️', 'Tarih', 27, Color(0xFF92400E), [
    _KonuSatiri('Cumhuriyet Dönemi ve İnkılaplar', 4),
    _KonuSatiri('Osmanlı Kuruluş - Yükselme', 3),
    _KonuSatiri('17-19. yy Osmanlı (Duraklama-Dağılma)', 3),
    _KonuSatiri('İslamiyet Öncesi Türk Tarihi', 2),
    _KonuSatiri('İlk Türk-İslam Devletleri', 2),
    _KonuSatiri('Anadolu Selçuklu ve Beylikler', 2),
    _KonuSatiri('Osmanlı Kültür ve Uygarlığı', 2),
    _KonuSatiri('20. yy Başında Osmanlı', 2),
    _KonuSatiri('Kurtuluş Savaşı Hazırlık Dönemi', 2),
    _KonuSatiri('Kurtuluş Savaşı Cepheleri', 2),
    _KonuSatiri('Çağdaş Türk ve Dünya Tarihi', 2),
    _KonuSatiri('Atatürk İlkeleri', 1),
  ]),
  _DistRow('🗺️', 'Coğrafya', 18, Color(0xFF059669), [
    _KonuSatiri('Yer Şekilleri', 3),
    _KonuSatiri('Tarım ve Hayvancılık', 3),
    _KonuSatiri('Türkiye\'nin Coğrafi Konumu', 2),
    _KonuSatiri('İklim ve Bitki Örtüsü', 2),
    _KonuSatiri('Nüfus ve Yerleşme', 2),
    _KonuSatiri('Sanayi ve Madenler', 2),
    _KonuSatiri('Ulaşım - Ticaret - Turizm', 2),
    _KonuSatiri('Bölgeler ve Projeler', 2),
  ]),
  _DistRow('⚖️', 'Vatandaşlık', 9, Color(0xFF475569), [
    _KonuSatiri('Anayasa ve Temel Kavramlar', 2),
    _KonuSatiri('Yürütme', 2),
    _KonuSatiri('Hukukun Temel Kavramları', 1),
    _KonuSatiri('Yasama', 1),
    _KonuSatiri('Yargı', 1),
    _KonuSatiri('Temel Hak ve Ödevler', 1),
    _KonuSatiri('İdare Hukuku', 1),
  ]),
  _DistRow('📰', 'Güncel Bilgiler', 6, Color(0xFFE11D48), [
    _KonuSatiri('Güncel Olaylar (Türkiye ve Dünya)', 4),
    _KonuSatiri('Kültür - Sanat - Spor', 1),
    _KonuSatiri('Bilim - Teknoloji', 1),
  ]),
];

/// Ders kimlik renkleri KASITLI olarak sabittir (yığılmış çubuk ile kartlar
/// arasında aynı ders hep aynı renkle eşleşsin diye). Ancak bazıları tek başına
/// zemine karışıyordu — Tarih'in kahvesi ve Vatandaşlık'ın kurşun grisi koyu
/// temalarda, canlı tonlar ise açık temalarda okunmuyordu. Bu yüzden rengin
/// KİMLİĞİ korunup yalnızca parlaklığı zemine göre ayarlanır; sadece METİN ve
/// çubuk dolgusu için kullanılır, tint/zemin tonları ham renkten türemeye
/// devam eder.
Color _okunurTon(Color renk, KpssColors c) {
  final parlaklik = renk.computeLuminance();
  if (!c.isLight && parlaklik < 0.22) return Color.lerp(renk, Colors.white, 0.45)!;
  if (c.isLight && parlaklik > 0.55) return Color.lerp(renk, Colors.black, 0.28)!;
  return renk;
}

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

/// Ders kartı — dokununca 2002-2025 ortalamalarına göre KONU kırılımını açar.
class _DistCard extends StatefulWidget {
  final _DistRow row;
  final int total;
  final KpssColors c;
  const _DistCard({required this.row, required this.total, required this.c});

  @override
  State<_DistCard> createState() => _DistCardState();
}

class _DistCardState extends State<_DistCard> {
  bool _acik = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final c = widget.c;
    final pct = row.soru / widget.total;
    final vurgu = _okunurTon(row.renk, c);
    // Konu çubuklarını en yüksek ortalamaya göre ölçekle — böylece ders içinde
    // hangi konunun "ağır" olduğu bir bakışta görülür.
    final enYuksek = row.konular.isEmpty
        ? 1
        : row.konular.map((k) => k.ortalama).reduce((a, b) => a > b ? a : b);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: vurgu.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: row.konular.isEmpty ? null : () => setState(() => _acik = !_acik),
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
                      color: vurgu.withValues(alpha: 0.16),
                    ),
                    child: Center(child: Text(row.icon, style: const TextStyle(fontSize: 18))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(row.ad, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                  Text('${row.soru} soru',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: vurgu)),
                  if (row.konular.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Icon(_acik ? Icons.expand_less : Icons.expand_more,
                        size: 20, color: c.textFaint),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: row.renk.withValues(alpha: c.isLight ? 0.16 : 0.12),
                  color: vurgu,
                ),
              ),
              if (!_acik && row.konular.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Konu dağılımı için dokun',
                    style: TextStyle(fontSize: 11, color: c.textFaint)),
              ],
              if (_acik) ...[
                const SizedBox(height: 12),
                Text(
                  '2002-2025 çıkmış sorulara göre yaklaşık ortalama — ÖSYM '
                  'yıldan yıla 1-2 soru değiştirebilir.',
                  style: TextStyle(fontSize: 11, height: 1.4, color: c.textFaint),
                ),
                const SizedBox(height: 8),
                for (final k in row.konular)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Text(k.ad,
                              style: TextStyle(fontSize: 12.5, height: 1.3, color: c.text)),
                        ),
                        Expanded(
                          flex: 3,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: k.ortalama / enYuksek,
                              minHeight: 6,
                              backgroundColor:
                                  row.renk.withValues(alpha: c.isLight ? 0.12 : 0.10),
                              color: vurgu.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 58,
                          child: Text('ort. ${k.ortalama}',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: vurgu)),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
