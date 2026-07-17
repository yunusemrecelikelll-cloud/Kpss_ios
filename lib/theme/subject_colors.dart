import 'package:flutter/material.dart';

/// Ders/konu seçim ekranlarına (ana sayfadaki "Dersler" ızgarası ve bir dersin
/// konu listesi) canlı, birbirinden ayırt edilebilir renk kimliği kazandırmak
/// için kullanılan sabit palet. "81 İl Fethi" harita oyunundaki bölge-bazlı
/// renklendirme yaklaşımıyla aynı ruhtadır (bkz. map_game/map_shared.dart
/// `kRegionColors`), ancak burada haritanın kendisi yok — sadece her dersin
/// kendine özgü, iki temel rengin oluşturduğu bir gradyanı var.
///
/// Bu renkler mevcut tema (`KpssColors`) sisteminin YERİNE geçmez; onun
/// üzerine `withValues(alpha: ...)` ile hafif bir renkli yıkama (wash) olarak
/// bindirilir — tıpkı premium_screen.dart'ta `c.violet.withValues(alpha: ...)`
/// deseninde olduğu gibi — böylece hem koyu hem açık temalarda okunaklı kalır.
class SubjectPalette {
  final Color a;
  final Color b;
  const SubjectPalette(this.a, this.b);
}

/// Her ders için sıcak/soğuk açıdan belirgin şekilde ayrışan iki renk.
const Map<String, SubjectPalette> kSubjectPalettes = {
  // Türkçe — sıcak gül/turuncu.
  'turkce': SubjectPalette(Color(0xFFFB7185), Color(0xFFF97316)),
  // Matematik-Geometri — soğuk mavi/mor.
  'matematik': SubjectPalette(Color(0xFF60A5FA), Color(0xFF8B5CF6)),
  // Tarih — amber/kahve.
  'tarih': SubjectPalette(Color(0xFFF59E0B), Color(0xFF92400E)),
  // Coğrafya — yeşil/deniz mavisi (teal).
  'cografya': SubjectPalette(Color(0xFF34D399), Color(0xFF0D9488)),
  // Vatandaşlık — koyu mavi/mor (adalet/otorite hissi).
  'vatandaslik': SubjectPalette(Color(0xFF6366F1), Color(0xFF7C3AED)),
  // Güncel Bilgiler — kırmızı/altın (haber/manşet hissi).
  'guncel': SubjectPalette(Color(0xFFF43F5E), Color(0xFFFACC15)),
};

const SubjectPalette _kFallbackPalette = SubjectPalette(Color(0xFF8B5CF6), Color(0xFFF472B6));

SubjectPalette subjectPaletteFor(String subjectId) => kSubjectPalettes[subjectId] ?? _kFallbackPalette;

Color _shiftHue(Color base, double degrees) {
  final hsl = HSLColor.fromColor(base);
  var hue = (hsl.hue + degrees) % 360.0;
  if (hue < 0) hue += 360.0;
  return hsl.withHue(hue).toColor();
}

/// Bir ders içindeki konular, dersin renk ailesini paylaşır ama sıraya göre
/// hafifçe ton kayması (hue-shift) alır — 100'den fazla konuya tek tek özel
/// renk tanımlamak yerine, indeks bazlı küçük bir varyasyon yeterli ve tutarlı.
SubjectPalette topicPaletteFor(String subjectId, int index) {
  final base = subjectPaletteFor(subjectId);
  final shift = ((index % 6) - 2.5) * 9.0; // yaklaşık -22°..+23° arası kayma
  return SubjectPalette(_shiftHue(base.a, shift), _shiftHue(base.b, shift));
}

/// Ders/konu kartları için tema-duyarlı gradyan dekorasyonu. Koyu temalarda
/// renkler daha doygun/parlak bir vurgu olarak, açık temalarda ise yumuşak bir
/// pastel yıkama olarak belirir — böylece her iki modda da metin okunaklı
/// kalır ve mevcut cam-efekti (glass) kart görünümüyle çakışmaz.
BoxDecoration subjectCardDecoration({
  required SubjectPalette palette,
  required bool isLight,
  double radius = 16,
}) {
  final alphaA = isLight ? 0.20 : 0.32;
  final alphaB = isLight ? 0.10 : 0.16;
  final borderAlpha = isLight ? 0.35 : 0.45;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        palette.a.withValues(alpha: alphaA),
        palette.b.withValues(alpha: alphaB),
      ],
    ),
    border: Border.all(color: palette.a.withValues(alpha: borderAlpha)),
  );
}
