import 'package:flutter/material.dart';

/// Akılda kalıcı kodlama "yapışkan not kâğıdı" tasarımı — HEM anasayfadaki
/// (mnemonics) ekran HEM de konu detayındaki Akılda Kalıcı sekmesi AYNI
/// görünümü kullansın diye tek yerde toplandı. Renkli kâğıt, hafif eğim,
/// üst yapışkan bant, sağ alt kıvrık köşe ve dokununca açılan detay sayfası.

/// Bir kodlama metninden çıkarılan yapı: başlık, gövde, kod kelimesi ve
/// koddaki harflere karşılık gelen açılım kelimeleri.
class Kodlama {
  final String baslik;
  final String govde;

  /// Örn. "BEST-VAN" → "BESTVAN" (sadece harfler). Bulunamazsa null.
  final String? kod;

  /// Kodun harfleriyle BİREBİR aynı sırada eşleşen açılım kelimeleri.
  final List<String> acilim;

  const Kodlama(
      {required this.baslik,
      required this.govde,
      this.kod,
      this.acilim = const []});

  /// Renkli gösterim ancak kod ve açılım birebir eşleştiyse yapılır.
  bool get renklenebilir =>
      kod != null &&
      acilim.isNotEmpty &&
      acilim.length == _sadeceHarfler(kod!).length;
}

/// Türkçe'ye duyarlı büyük harf çevirimi (i→İ, ı→I).
String _buyuk(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Tırnak içindeki kod (ör. 'BEST-VAN', 'CAM KS') — boşluk/tire içerebilir.
final _kTirnakRe =
    RegExp("['‘’\"]([A-ZÇĞİÖŞÜ]{2,}(?:[- ][A-ZÇĞİÖŞÜ]+)*)['‘’\"]");

/// Düz kod (ör. AKTAKA, BEST-VAN).
final _kKodRe = RegExp(r'[A-ZÇĞİÖŞÜ]{2,}(?:-[A-ZÇĞİÖŞÜ]+)*');
final _kParantezRe = RegExp(r'\(([^()]*)\)');
final _kHarfDisiRe = RegExp(r'[^A-ZÇĞİÖŞÜ]');

/// Koddaki sadece harfler (tire/boşluk atılmış hâli).
String _sadeceHarfler(String kod) => kod.replaceAll(_kHarfDisiRe, '');

/// Ham mnemonic metnini ayrıştırır. Biçim tutmazsa sadece düz metin döner,
/// ASLA istisna fırlatmaz.
Kodlama kodlamaAyristir(String text) {
  final i = text.indexOf(':');
  final baslik = i > 0 && i < 60 ? text.substring(0, i).trim() : '';
  final govde = i > 0 && i < 60 ? text.substring(i + 1).trim() : text.trim();

  final adaylar = <String>[];
  final tirnakli = _kTirnakRe.firstMatch(text)?.group(1);
  if (tirnakli != null) adaylar.add(tirnakli);
  final baslikKodu = _kKodRe.firstMatch(baslik)?.group(0);
  if (baslikKodu != null) adaylar.add(baslikKodu);
  final metinKodu = _kKodRe.firstMatch(text)?.group(0);
  if (metinKodu != null) adaylar.add(metinKodu);
  if (adaylar.isEmpty) return Kodlama(baslik: baslik, govde: govde);
  final ilkKod = adaylar.first;

  final ic = _kParantezRe.firstMatch(text)?.group(1);
  if (ic == null) return Kodlama(baslik: baslik, govde: govde, kod: ilkKod);

  final kelimeler = <String>[];
  for (final parca in ic.split(',')) {
    var p = parca.trim();
    if (p.isEmpty) continue;
    final ik = p.indexOf(':');
    if (ik > 0) p = p.substring(0, ik).trim();
    final ilk = p.split(RegExp(r'\s+')).first.trim();
    if (ilk.isNotEmpty) kelimeler.add(ilk);
  }

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
    if (uyumlu) {
      return Kodlama(
          baslik: baslik, govde: govde, kod: aday, acilim: kelimeler);
    }
  }
  return Kodlama(baslik: baslik, govde: govde, kod: ilkKod);
}

// ── Renk paleti ────────────────────────────────────────────────────────────
const _kHarfTonlari = <double>[
  352, 24, 42, 86, 148, 186, 214, 258, 288, 322
];
const _kKagitTonlari = <double>[48, 96, 168, 200, 256, 320, 12];

Color kodlamaHarfRengi(int i, bool acikKagit) {
  final h = _kHarfTonlari[i % _kHarfTonlari.length];
  return HSLColor.fromAHSL(
          1, h, acikKagit ? 0.78 : 0.68, acikKagit ? 0.34 : 0.72)
      .toColor();
}

Color kodlamaKagitRengi(int i, bool acikTema) {
  final h = _kKagitTonlari[i % _kKagitTonlari.length];
  return HSLColor.fromAHSL(
          1, h, acikTema ? 0.82 : 0.30, acikTema ? 0.90 : 0.17)
      .toColor();
}

Color kodlamaMurekkep(bool acikTema) =>
    acikTema ? const Color(0xFF241C33) : const Color(0xFFEFE9F7);

List<TextSpan> _renkliKod(
    String kod, List<String> acilim, bool acikKagit, double fontSize) {
  final spans = <TextSpan>[];
  var harfSirasi = 0;
  for (var i = 0; i < kod.length; i++) {
    final ch = kod[i];
    final harfMi = !_kHarfDisiRe.hasMatch(ch);
    spans.add(TextSpan(
      text: ch,
      style: TextStyle(
        color: harfMi
            ? kodlamaHarfRengi(harfSirasi, acikKagit)
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

List<TextSpan> _renkliKelime(
    String kelime, int i, bool acikKagit, Color ink, double fontSize) {
  final ilk = kelime.characters.first;
  final kalan = kelime.substring(ilk.length);
  return [
    TextSpan(
      text: ilk,
      style: TextStyle(
          color: kodlamaHarfRengi(i, acikKagit),
          fontSize: fontSize,
          fontWeight: FontWeight.w900),
    ),
    TextSpan(
      text: kalan,
      style: TextStyle(
          color: ink, fontSize: fontSize, fontWeight: FontWeight.w600),
    ),
  ];
}

/// Dokununca açılan detay sayfası (kâğıt renginde bottom sheet).
void kodlamaDetayAc(BuildContext context,
    {required String text,
    required String ustEtiket,
    required int index,
    required bool acikTema}) {
  final k = kodlamaAyristir(text);
  final kagit = kodlamaKagitRengi(index, acikTema);
  final ink = kodlamaMurekkep(acikTema);

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
              ustEtiket,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: ink.withValues(alpha: 0.6),
                  letterSpacing: 0.4),
            ),
            const SizedBox(height: 12),
            if (k.renklenebilir)
              RichText(
                text: TextSpan(children: _renkliKod(k.kod!, k.acilim, acikTema, 30)),
              )
            else if (k.baslik.isNotEmpty)
              Text(k.baslik,
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900, color: ink)),
            if (k.renklenebilir) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < k.acilim.length; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: ink.withValues(alpha: acikTema ? 0.05 : 0.09),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: kodlamaHarfRengi(i, acikTema)
                                .withValues(alpha: 0.45)),
                      ),
                      child: RichText(
                        text: TextSpan(
                            children:
                                _renkliKelime(k.acilim[i], i, acikTema, ink, 13.5)),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Text(
              k.govde,
              style: TextStyle(
                  fontSize: 14.5,
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                  color: ink),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Küçük renkli yapışkan not — hafif eğim, bant detayı, kıvrık köşe.
/// [ustEtiket] üstteki küçük etiket (ör. konu başlığı), [altEtiket] alttaki
/// iğneli etiket (ör. ders adı). [onTap] verilmezse dokununca detay açılır.
class KodlamaNotu extends StatelessWidget {
  final String text;
  final String ustEtiket;
  final String altEtiket;
  final int index;
  final bool acikTema;
  final VoidCallback? onTap;

  const KodlamaNotu({
    super.key,
    required this.text,
    required this.ustEtiket,
    required this.altEtiket,
    required this.index,
    required this.acikTema,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final k = kodlamaAyristir(text);
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
          child: InkWell(
            onTap: onTap ??
                () => kodlamaDetayAc(context,
                    text: text,
                    ustEtiket: '$altEtiket • $ustEtiket',
                    index: index,
                    acikTema: acikTema),
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
                          ustEtiket,
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
                            text: TextSpan(
                                children:
                                    _renkliKod(k.kod!, k.acilim, acikTema, 22)),
                          )
                        else
                          Text(
                            k.baslik.isNotEmpty ? k.baslik : 'Teknik',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w900,
                                color: ink,
                                height: 1.2),
                          ),
                        const SizedBox(height: 8),
                        if (k.renklenebilir)
                          RichText(
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(children: [
                              for (var i = 0; i < k.acilim.length; i++) ...[
                                ..._renkliKelime(
                                    k.acilim[i], i, acikTema, ink, 12),
                                if (i < k.acilim.length - 1)
                                  TextSpan(
                                    text: ' · ',
                                    style: TextStyle(
                                        color: ink.withValues(alpha: 0.4),
                                        fontSize: 12),
                                  ),
                              ],
                            ]),
                          )
                        else
                          Text(
                            k.govde,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                                color: ink.withValues(alpha: 0.85)),
                          ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.push_pin_rounded,
                                size: 11, color: ink.withValues(alpha: 0.35)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                altEtiket,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: ink.withValues(alpha: 0.45)),
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
                              color: ink.withValues(
                                  alpha: acikTema ? 0.10 : 0.18)),
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
