import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// styles.css'teki CSS değişkenlerinin (:root ve [data-theme="..."]) birebir karşılığı.
class KpssColors {
  final String id;
  final String name;
  final String icon;
  final Color bg;
  final Color bg2;
  final Color bg3;
  final Color headerBg;
  final Color glass;
  final Color glass2;
  final Color border;
  final Color violet;
  final Color violetL;
  final Color rose;
  final Color roseL;
  final Color gold;
  final Color mint;
  final Color text;
  final Color textDim;
  final Color textFaint;
  final Color success;
  final Color danger;
  final Color warn;
  final bool isLight;

  const KpssColors({
    required this.id,
    required this.name,
    required this.icon,
    required this.bg,
    required this.bg2,
    required this.bg3,
    required this.headerBg,
    required this.glass,
    required this.glass2,
    required this.border,
    required this.violet,
    required this.violetL,
    required this.rose,
    required this.roseL,
    required this.gold,
    required this.mint,
    required this.text,
    required this.textDim,
    required this.textFaint,
    required this.success,
    required this.danger,
    required this.warn,
    required this.isLight,
  });
}

const Color _c1 = Color(0xFF0A0612);

const kThemes = <String, KpssColors>{
  'default': KpssColors(
    id: 'default', name: 'Gece Yarısı', icon: '🌙',
    bg: _c1, bg2: Color(0xFF110920), bg3: Color(0xFF170D2A),
    headerBg: Color(0xCC0A0612), glass: Color(0x0EFFFFFF), glass2: Color(0x17FFFFFF),
    border: Color(0x1CFFFFFF),
    violet: Color(0xFF8B5CF6), violetL: Color(0xFFA78BFA),
    rose: Color(0xFFF472B6), roseL: Color(0xFFFB7185),
    gold: Color(0xFFFBBF24), mint: Color(0xFF34D399),
    text: Color(0xFFF1EEFF), textDim: Color(0xFFC4B5FD), textFaint: Color(0xFF8B7AA8),
    success: Color(0xFF34D399), danger: Color(0xFFFB7185), warn: Color(0xFFFBBF24),
    isLight: false,
  ),
  'safak': KpssColors(
    id: 'safak', name: 'Şafak', icon: '🌤️',
    bg: Color(0xFFFAF7FF), bg2: Color(0xFFF3EDFF), bg3: Color(0xFFEBE0FF),
    headerBg: Color(0xE0FAF7FF), glass: Color(0x9EFFFFFF), glass2: Color(0xCCFFFFFF),
    border: Color(0x2E8B5CF6),
    violet: Color(0xFF7C3AED), violetL: Color(0xFF8B5CF6),
    rose: Color(0xFFDB2777), roseL: Color(0xFFEC4899),
    gold: Color(0xFFD97706), mint: Color(0xFF059669),
    text: Color(0xFF1E0835), textDim: Color(0xFF4A2D70), textFaint: Color(0xFF73618E),
    success: Color(0xFF059669), danger: Color(0xFFDC2626), warn: Color(0xFFD97706),
    isLight: true,
  ),
  'pembe': KpssColors(
    id: 'pembe', name: 'Pembe Rüya', icon: '🌸',
    bg: Color(0xFFFFF0F6), bg2: Color(0xFFFFE4F0), bg3: Color(0xFFFFD6E8),
    headerBg: Color(0xE0FFF0F6), glass: Color(0x99FFFFFF), glass2: Color(0xC7FFFFFF),
    border: Color(0x33EC4899),
    violet: Color(0xFF9333EA), violetL: Color(0xFFA855F7),
    rose: Color(0xFFE11D48), roseL: Color(0xFFF43F5E),
    gold: Color(0xFFD97706), mint: Color(0xFF0D9488),
    text: Color(0xFF3B0A2A), textDim: Color(0xFF6B2349), textFaint: Color(0xFF89576E),
    success: Color(0xFF0D9488), danger: Color(0xFFE11D48), warn: Color(0xFFD97706),
    isLight: true,
  ),
  'zumrut': KpssColors(
    id: 'zumrut', name: 'Zümrüt', icon: '🌿',
    bg: Color(0xFF020D0A), bg2: Color(0xFF041410), bg3: Color(0xFF071C16),
    headerBg: Color(0xCC020D0A), glass: Color(0x0DFFFFFF), glass2: Color(0x14FFFFFF),
    border: Color(0x2634D399),
    violet: Color(0xFF34D399), violetL: Color(0xFF6EE7B7),
    rose: Color(0xFFA3E635), roseL: Color(0xFFBEF264),
    gold: Color(0xFFFBBF24), mint: Color(0xFF06B6D4),
    text: Color(0xFFECFDF5), textDim: Color(0xFFA7F3D0), textFaint: Color(0xFF6EE7B7),
    success: Color(0xFF34D399), danger: Color(0xFFF87171), warn: Color(0xFFFBBF24),
    isLight: false,
  ),
  'gunbatimi': KpssColors(
    id: 'gunbatimi', name: 'Gün Batımı', icon: '🌅',
    bg: Color(0xFF120508), bg2: Color(0xFF1E0810), bg3: Color(0xFF2A0C18),
    headerBg: Color(0xCC120508), glass: Color(0x0EFFFFFF), glass2: Color(0x17FFFFFF),
    border: Color(0x2EFB923C),
    violet: Color(0xFFF97316), violetL: Color(0xFFFB923C),
    rose: Color(0xFFEF4444), roseL: Color(0xFFF87171),
    gold: Color(0xFFFBBF24), mint: Color(0xFF34D399),
    text: Color(0xFFFFF7ED), textDim: Color(0xFFFED7AA), textFaint: Color(0xFFD97706),
    success: Color(0xFF34D399), danger: Color(0xFFEF4444), warn: Color(0xFFFBBF24),
    isLight: false,
  ),
  'kutup': KpssColors(
    id: 'kutup', name: 'Kutup Gecesi', icon: '🧊',
    bg: Color(0xFF010B18), bg2: Color(0xFF021628), bg3: Color(0xFF042038),
    headerBg: Color(0xCC010B18), glass: Color(0x0DFFFFFF), glass2: Color(0x14FFFFFF),
    border: Color(0x2638BDF8),
    violet: Color(0xFF0EA5E9), violetL: Color(0xFF38BDF8),
    rose: Color(0xFF818CF8), roseL: Color(0xFFA5B4FC),
    gold: Color(0xFFFBBF24), mint: Color(0xFF34D399),
    text: Color(0xFFF0F9FF), textDim: Color(0xFFBAE6FD), textFaint: Color(0xFF7DD3FC),
    success: Color(0xFF34D399), danger: Color(0xFFF87171), warn: Color(0xFFFBBF24),
    isLight: false,
  ),
  'lacivert': KpssColors(
    id: 'lacivert', name: 'Gece Mavisi', icon: '🌌',
    bg: Color(0xFF060A1E), bg2: Color(0xFF0B1230), bg3: Color(0xFF121B42),
    headerBg: Color(0xCC060A1E), glass: Color(0x0EFFFFFF), glass2: Color(0x17FFFFFF),
    border: Color(0x266366F1),
    violet: Color(0xFF6366F1), violetL: Color(0xFF818CF8),
    rose: Color(0xFFEC4899), roseL: Color(0xFFF472B6),
    gold: Color(0xFFFBBF24), mint: Color(0xFF22D3EE),
    text: Color(0xFFEEF2FF), textDim: Color(0xFFC7D2FE), textFaint: Color(0xFF8B93C4),
    success: Color(0xFF34D399), danger: Color(0xFFF87171), warn: Color(0xFFFBBF24),
    isLight: false,
  ),
  'altin': KpssColors(
    id: 'altin', name: 'Kraliyet Altını', icon: '👑',
    bg: Color(0xFF120D02), bg2: Color(0xFF1D1505), bg3: Color(0xFF2A1E08),
    headerBg: Color(0xCC120D02), glass: Color(0x0FFFFFFF), glass2: Color(0x18FFFFFF),
    border: Color(0x33D4AF37),
    violet: Color(0xFFD4AF37), violetL: Color(0xFFE8C766),
    rose: Color(0xFFB45309), roseL: Color(0xFFD97706),
    gold: Color(0xFFFDE68A), mint: Color(0xFF34D399),
    text: Color(0xFFFEF9E7), textDim: Color(0xFFE8D9A8), textFaint: Color(0xFFA8925C),
    success: Color(0xFF34D399), danger: Color(0xFFF87171), warn: Color(0xFFFDE68A),
    isLight: false,
  ),
  'ferahlik': KpssColors(
    id: 'ferahlik', name: 'Ferahlık', icon: '🍃',
    bg: Color(0xFFF0FBF9), bg2: Color(0xFFE1F6F1), bg3: Color(0xFFD1EFE7),
    headerBg: Color(0xE0F0FBF9), glass: Color(0x9EFFFFFF), glass2: Color(0xCCFFFFFF),
    border: Color(0x2E14B8A6),
    violet: Color(0xFF0D9488), violetL: Color(0xFF14B8A6),
    rose: Color(0xFFDB2777), roseL: Color(0xFFEC4899),
    gold: Color(0xFFD97706), mint: Color(0xFF059669),
    text: Color(0xFF042F2E), textDim: Color(0xFF115E59), textFaint: Color(0xFF36736D),
    success: Color(0xFF059669), danger: Color(0xFFDC2626), warn: Color(0xFFD97706),
    isLight: true,
  ),
};

/// Ücretsiz kullanıcıların erişebildiği 3 tema; kalan 6'sı premium'a özel.
const List<String> kFreeThemeIds = ['default', 'safak', 'pembe'];

ThemeData buildThemeData(KpssColors c) {
  final base = c.isLight ? ThemeData.light() : ThemeData.dark();
  // Uygulama genelinde daha okunaklı/modern bir tipografi: gövde metni için
  // yuvarlak hatlı, sıcak bir yazı tipi (Nunito); başlıklar için mevcut
  // Baloo2 markası (bkz. home_screen.dart'taki "KPSS Hazırlık" başlığı) ile
  // tutarlı bir görünüm.
  final googleTextTheme = GoogleFonts.nunitoTextTheme(base.textTheme);
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    colorScheme: (c.isLight ? const ColorScheme.light() : const ColorScheme.dark()).copyWith(
      primary: c.violet,
      secondary: c.rose,
      surface: c.bg2,
      error: c.danger,
      onSurface: c.text,
    ),
    textTheme: googleTextTheme.apply(bodyColor: c.text, displayColor: c.text),
    appBarTheme: AppBarTheme(
      backgroundColor: c.headerBg,
      foregroundColor: c.text,
      elevation: 0,
      titleTextStyle: GoogleFonts.baloo2(color: c.text, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    // NOT: Alt navigasyon etiketlerinde (ör. "Yanlışlarım") harflerin alt
    // uzantısı (ör. 'm', 'ğ') önceden kesiliyordu — varsayılan labelSmall
    // stilinin satır yüksekliği çok dardı. Burada AÇIKÇA daha ferah bir
    // `height` ve biraz küçültülmüş font boyutu veriyoruz.
    navigationBarTheme: NavigationBarThemeData(
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return GoogleFonts.nunito(
          fontSize: 10.5,
          height: 1.5,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? c.violet : c.textFaint,
        );
      }),
    ),
    cardColor: c.glass2,
    dividerColor: c.border,
  );
}
