import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subject.dart';
import '../services/data_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';
import 'tools_hub_screen.dart';

class _MnemonicItem {
  final String subjectAd;
  final String topicBaslik;
  final String text;
  const _MnemonicItem({required this.subjectAd, required this.topicBaslik, required this.text});
}

/// Bir kodlama metninden çıkarılan yapı: başlık, gövde, kod kelimesi ve
/// koddaki harflere karşılık gelen açılım kelimeleri.
class _Kodlama {
  final String baslik;
  final String govde;

  /// Örn. "BEST-VAN" → "BESTVAN" (sadece harfler). Bulunamazsa null.
  final String? kod;

  /// Kodun harfleriyle BİREBİR aynı sırada eşleşen açılım kelimeleri.
  /// Eşleşme güvenli şekilde doğrulanamadıysa boş liste döner.
  final List<String> acilim;

  const _Kodlama({required this.baslik, required this.govde, this.kod, this.acilim = const []});

  /// Renkli gösterim ancak kod ve açılım birebir eşleştiyse yapılır.
  bool get renklenebilir =>
      kod != null && acilim.isNotEmpty && acilim.length == _sadeceHarfler(kod!).length;
}

/// Türkçe'ye duyarlı büyük harf çevirimi (i→İ, ı→I).
String _buyuk(String s) => s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Tırnak içindeki kod (ör. 'BEST-VAN', 'CAM KS') — boşluk/tire içerebilir.
final _kTirnakRe = RegExp("['‘’\"]([A-ZÇĞİÖŞÜ]{2,}(?:[- ][A-ZÇĞİÖŞÜ]+)*)['‘’\"]");

/// Düz kod (ör. AKTAKA, BEST-VAN).
final _kKodRe = RegExp(r'[A-ZÇĞİÖŞÜ]{2,}(?:-[A-ZÇĞİÖŞÜ]+)*');
final _kParantezRe = RegExp(r'\(([^()]*)\)');
final _kHarfDisiRe = RegExp(r'[^A-ZÇĞİÖŞÜ]');

/// Koddaki sadece harfler (tire/boşluk atılmış hâli).
String _sadeceHarfler(String kod) => kod.replaceAll(_kHarfDisiRe, '');

/// Ham mnemonic metnini ayrıştırır. Beklenen biçim:
/// "KOD Tekniği: ... (Kelime1, Kelime2, ...) ..." — biçim tutmazsa
/// sadece düz metin döner, ASLA istisna fırlatmaz.
_Kodlama _ayristir(String text) {
  final i = text.indexOf(':');
  final baslik = i > 0 && i < 60 ? text.substring(0, i).trim() : '';
  final govde = i > 0 && i < 60 ? text.substring(i + 1).trim() : text.trim();

  // 1) Kod adayları: tırnak içindeki kod, başlıktaki kod, metindeki ilk kod.
  final adaylar = <String>[];
  final tirnakli = _kTirnakRe.firstMatch(text)?.group(1);
  if (tirnakli != null) adaylar.add(tirnakli);
  final baslikKodu = _kKodRe.firstMatch(baslik)?.group(0);
  if (baslikKodu != null) adaylar.add(baslikKodu);
  final metinKodu = _kKodRe.firstMatch(text)?.group(0);
  if (metinKodu != null) adaylar.add(metinKodu);
  if (adaylar.isEmpty) return _Kodlama(baslik: baslik, govde: govde);
  final ilkKod = adaylar.first;

  // 2) Açılım: ilk parantez içindeki virgülle ayrılmış öğelerin ilk kelimeleri.
  final ic = _kParantezRe.firstMatch(text)?.group(1);
  if (ic == null) return _Kodlama(baslik: baslik, govde: govde, kod: ilkKod);

  final kelimeler = <String>[];
  for (final parca in ic.split(',')) {
    var p = parca.trim();
    if (p.isEmpty) continue;
    final ik = p.indexOf(':');
    if (ik > 0) p = p.substring(0, ik).trim(); // "Kut: siyasi güç" → "Kut"
    final ilk = p.split(RegExp(r'\s+')).first.trim();
    if (ilk.isNotEmpty) kelimeler.add(ilk);
  }

  // 3) Güvenli eşleştirme: adaylardan harf sayısı VE baş harfleri birebir
  // tutan ilkini seç; hiçbiri tutmazsa renklendirme yapılmaz (çökmez).
  for (final aday in adaylar) {
    final harfler = _sadeceHarfler(aday);
    if (harfler.length < 2 || harfler.length != kelimeler.length) continue;
    var uyumlu = true;
    for (var k = 0; k < harfler.length; k++) {
      if (_buyuk(kelimeler[k].characters.first) != _buyuk(harfler[k])) {
        uyumlu = false;
        break;
      }
    }
    if (uyumlu) return _Kodlama(baslik: baslik, govde: govde, kod: aday, acilim: kelimeler);
  }
  return _Kodlama(baslik: baslik, govde: govde, kod: ilkKod);
}

// ── Renk paleti ────────────────────────────────────────────────────────────
// Harf renkleri ton (hue) üzerinden üretilir; kâğıt açıkken koyu, kâğıt
// koyuyken açık ton seçilerek her iki temada da kontrast garanti edilir.
const _kHarfTonlari = <double>[352, 24, 42, 86, 148, 186, 214, 258, 288, 322];
const _kKagitTonlari = <double>[48, 96, 168, 200, 256, 320, 12];

Color _harfRengi(int i, bool acikKagit) {
  final h = _kHarfTonlari[i % _kHarfTonlari.length];
  return HSLColor.fromAHSL(1, h, acikKagit ? 0.78 : 0.68, acikKagit ? 0.34 : 0.72).toColor();
}

Color _kagitRengi(int i, bool acikTema) {
  final h = _kKagitTonlari[i % _kKagitTonlari.length];
  return HSLColor.fromAHSL(1, h, acikTema ? 0.82 : 0.30, acikTema ? 0.90 : 0.17).toColor();
}

/// Kâğıdın üstündeki "mürekkep" rengi — kâğıt her iki temada da kendi
/// tonunda kaldığı için metin rengi temaya göre sabitlenir.
Color _murekkep(bool acikTema) => acikTema ? const Color(0xFF241C33) : const Color(0xFFEFE9F7);

/// Kodun harflerini, açılımdaki karşılık gelen kelimenin baş harfiyle AYNI
/// renge boyayarak TextSpan listesi üretir.
List<TextSpan> _renkliKod(String kod, List<String> acilim, bool acikKagit, double fontSize) {
  final spans = <TextSpan>[];
  var harfSirasi = 0; // tire/boşluk gibi ayraçlar renk sırasını ilerletmez
  for (var i = 0; i < kod.length; i++) {
    final ch = kod[i];
    final harfMi = !_kHarfDisiRe.hasMatch(ch);
    spans.add(TextSpan(
      text: ch,
      style: TextStyle(
        color: harfMi
            ? _harfRengi(harfSirasi, acikKagit)
            : (acikKagit ? const Color(0x66241C33) : const Color(0x66EFE9F7)),
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
      ),
    ));
    if (harfMi) harfSirasi++;
  }
  return spans;
}

/// Açılım kelimesi: baş harfi koddaki harfle aynı renkte, gerisi mürekkep.
List<TextSpan> _renkliKelime(String kelime, int i, bool acikKagit, Color ink, double fontSize) {
  final ilk = kelime.characters.first;
  final kalan = kelime.substring(ilk.length);
  return [
    TextSpan(
      text: ilk,
      style: TextStyle(color: _harfRengi(i, acikKagit), fontSize: fontSize, fontWeight: FontWeight.w900),
    ),
    TextSpan(
      text: kalan,
      style: TextStyle(color: ink, fontSize: fontSize, fontWeight: FontWeight.w600),
    ),
  ];
}

/// Akılda Kalıcı Kodlama — gerçek, araştırılmış mnemonic teknikleri
/// (assets/data/mnemonics.json). Sadece Tarih ve Coğrafya konularında içerik
/// var; aynı veri topic_screen.dart'ta da konu altında gösteriliyor, burası
/// tüm teknikleri küçük renkli not kâğıtları hâlinde tek ızgarada sunar.
class MnemonicsScreen extends StatefulWidget {
  final List<Subject> subjects;
  const MnemonicsScreen({super.key, required this.subjects});

  @override
  State<MnemonicsScreen> createState() => _MnemonicsScreenState();
}

class _MnemonicsScreenState extends State<MnemonicsScreen> {
  final _rng = Random();
  List<_MnemonicItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mnemonics = await context.read<DataService>().loadMnemonics();
    final items = <_MnemonicItem>[];
    for (final s in widget.subjects) {
      for (final t in s.konular) {
        final tips = mnemonics[t.id];
        if (tips == null) continue;
        for (final tip in tips) {
          items.add(_MnemonicItem(subjectAd: s.ad, topicBaslik: t.baslik, text: tip));
        }
      }
    }
    if (!mounted) return;
    setState(() => _items = items);
  }

  void _karistir() {
    context.read<SoundService>().click();
    setState(() => _items!.shuffle(_rng));
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    if (!storage.isPremiumUser()) {
      return const LockedFeatureCard(
        title: 'Akılda Kalıcı Kodlama',
        desc: 'Tarih ve coğrafya konuları için gerçek ezber teknikleriyle hızlı tekrar yapmak için Premium\'a geç.',
      );
    }
    if (_items == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('🧠 Akılda Kalıcı Kodlama')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_items!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('🧠 Akılda Kalıcı Kodlama')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('🧠  Henüz içerik yüklenemedi, birazdan tekrar dene.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final c = context.watch<ThemeProvider>().colors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🧠 Akılda Kalıcı Kodlama'),
        actions: [
          IconButton(
            tooltip: 'Karıştır',
            onPressed: _karistir,
            icon: const Icon(Icons.shuffle_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          // Ekran genişliğine göre sütun sayısı — küçük telefonlarda bile
          // notlar "küçük" görünsün diye en az 2 sütun.
          final w = box.maxWidth;
          final sutun = w > 1100 ? 4 : (w > 760 ? 3 : 2);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    '${_items!.length} kodlama notu • bir nota dokunarak tamamını oku',
                    style: TextStyle(fontSize: 12.5, color: c.textFaint, fontWeight: FontWeight.w600),
                  ),
                ),
                _masonry(sutun, c.isLight),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Basit masonry: notlar tahmini yüksekliğe göre en kısa sütuna eklenir.
  Widget _masonry(int sutun, bool acikTema) {
    final sutunlar = List.generate(sutun, (_) => <Widget>[]);
    final yukseklikler = List.filled(sutun, 0.0);

    for (var i = 0; i < _items!.length; i++) {
      var enKisa = 0;
      for (var k = 1; k < sutun; k++) {
        if (yukseklikler[k] < yukseklikler[enKisa]) enKisa = k;
      }
      final it = _items![i];
      sutunlar[enKisa].add(Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: _NotKagidi(
          item: it,
          index: i,
          acikTema: acikTema,
          onTap: () => _detayAc(it, i, acikTema),
        ),
      ));
      yukseklikler[enKisa] += 130 + it.text.length * 0.22;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var k = 0; k < sutun; k++) ...[
          if (k > 0) const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sutunlar[k])),
        ],
      ],
    );
  }

  void _detayAc(_MnemonicItem it, int index, bool acikTema) {
    context.read<SoundService>().click();
    final k = _ayristir(it.text);
    final kagit = _kagitRengi(index, acikTema);
    final ink = _murekkep(acikTema);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => Container(
          decoration: BoxDecoration(
            color: kagit,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 32),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${it.subjectAd} • ${it.topicBaslik}',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: ink.withValues(alpha: 0.6), letterSpacing: 0.4),
              ),
              const SizedBox(height: 12),
              if (k.renklenebilir)
                RichText(
                  text: TextSpan(children: _renkliKod(k.kod!, k.acilim, acikTema, 30)),
                )
              else if (k.baslik.isNotEmpty)
                Text(k.baslik, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ink)),
              if (k.renklenebilir) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < k.acilim.length; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: ink.withValues(alpha: acikTema ? 0.05 : 0.09),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _harfRengi(i, acikTema).withValues(alpha: 0.45)),
                        ),
                        child: RichText(
                          text: TextSpan(children: _renkliKelime(k.acilim[i], i, acikTema, ink, 13.5)),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Text(
                k.govde,
                style: TextStyle(fontSize: 14.5, height: 1.6, fontWeight: FontWeight.w500, color: ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Küçük renkli yapışkan not — hafif eğim, bant detayı, kıvrık köşe.
class _NotKagidi extends StatelessWidget {
  final _MnemonicItem item;
  final int index;
  final bool acikTema;
  final VoidCallback onTap;

  const _NotKagidi({required this.item, required this.index, required this.acikTema, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final k = _ayristir(item.text);
    final kagit = _kagitRengi(index, acikTema);
    final ink = _murekkep(acikTema);
    // Deterministik küçük eğim — her not biraz farklı dursun.
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
          child: InkWell(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ink.withValues(alpha: 0.10)),
              ),
              child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.topicBaslik,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: ink.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (k.renklenebilir)
                        RichText(
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(children: _renkliKod(k.kod!, k.acilim, acikTema, 22)),
                        )
                      else
                        Text(
                          k.baslik.isNotEmpty ? k.baslik : 'Teknik',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: ink, height: 1.2),
                        ),
                      const SizedBox(height: 8),
                      if (k.renklenebilir)
                        RichText(
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(children: [
                            for (var i = 0; i < k.acilim.length; i++) ...[
                              ..._renkliKelime(k.acilim[i], i, acikTema, ink, 12),
                              if (i < k.acilim.length - 1)
                                TextSpan(
                                  text: ' · ',
                                  style: TextStyle(color: ink.withValues(alpha: 0.4), fontSize: 12),
                                ),
                            ],
                          ]),
                        )
                      else
                        Text(
                          k.govde,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, height: 1.45, fontWeight: FontWeight.w500, color: ink.withValues(alpha: 0.85)),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.push_pin_rounded, size: 11, color: ink.withValues(alpha: 0.35)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.subjectAd,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: ink.withValues(alpha: 0.45)),
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
                        color: Colors.white.withValues(alpha: acikTema ? 0.65 : 0.16),
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
                    borderRadius: const BorderRadius.only(bottomRight: Radius.circular(10)),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: Transform.rotate(
                        angle: 0.785,
                        origin: const Offset(6, 6),
                        child: Container(color: ink.withValues(alpha: acikTema ? 0.10 : 0.18)),
                      ),
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
