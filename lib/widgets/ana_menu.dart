import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/subject.dart';
import '../services/sound_service.dart';
import '../screens/mentor_screen.dart';
import '../screens/mnemonics_screen.dart';
import '../screens/premium_screen.dart';
import '../screens/score_distribution_screen.dart';
import '../screens/stopwatch_screen.dart';
import '../screens/study_plan_screen.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';

/// Anasayfanın sol çekmecesi (Drawer).
///
/// Tasarım hedefi: sade ama premium. Varsayılan `ListTile` yığını yerine her
/// satır kendi vurgu rengiyle boyanmış bir kart; üstte kullanıcının adını ve
/// plan rozetini taşıyan degrade bir başlık.
///
/// Buradaki araçlar ÖNCEDEN "Oyunlar" sekmesindeki "Diğer Araçlar"
/// bölümündeydi; oyun değil çalışma aracı oldukları için buraya taşındılar
/// (bkz. tools_hub_screen.dart).
class AnaMenu extends StatelessWidget {
  final List<Subject> subjects;
  final bool premium;
  final String name;

  const AnaMenu({
    super.key,
    required this.subjects,
    required this.premium,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;

    void git(Widget ekran) {
      context.read<SoundService>().click();
      Navigator.of(context).pop(); // önce çekmeceyi kapat
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ekran));
    }

    return Drawer(
      backgroundColor: c.bg2,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          children: [
            _Baslik(name: name, premium: premium),
            const SizedBox(height: 18),

            const DsSectionHeader(title: 'Çalışma'),
            const SizedBox(height: 8),
            _MenuSatiri(
              emoji: '🗓️',
              baslik: 'Günlük Çalışma Planı',
              altBaslik: 'Hangi gün, hangi saatte çalışacağını planla',
              renk: c.mint,
              onTap: () => git(const StudyPlanScreen()),
            ),
            const SizedBox(height: 8),
            _MenuSatiri(
              emoji: '🧠',
              baslik: 'Akılda Kalıcı Kodlama',
              altBaslik: 'Kısa, şifreli özetlerle hızlı tekrar',
              renk: c.violetL,
              onTap: () => git(MnemonicsScreen(subjects: subjects)),
            ),
            const SizedBox(height: 8),
            _MenuSatiri(
              emoji: '⏱️',
              baslik: 'Çalışma Kronometresi',
              altBaslik: 'Ders bazlı süre tut ve analiz et',
              renk: c.roseL,
              onTap: () => git(const StopwatchScreen()),
            ),
            const SizedBox(height: 8),
            _MenuSatiri(
              emoji: '🎓',
              baslik: 'Mentörlük Seansları',
              altBaslik: 'Sınav stratejileri ve haftalık plan',
              renk: c.success,
              onTap: () => git(const MentorScreen()),
            ),

            const SizedBox(height: 18),
            const DsSectionHeader(title: 'Keşfet'),
            const SizedBox(height: 8),
            _MenuSatiri(
              emoji: '📊',
              baslik: 'Soru Dağılımı',
              altBaslik: 'Hangi dersten kaç soru geliyor?',
              renk: c.violet,
              onTap: () => git(const ScoreDistributionScreen()),
            ),
            const SizedBox(height: 8),
            _MenuSatiri(
              emoji: '💎',
              baslik: premium ? 'Premium Aboneliğin' : 'Premium\'a Geç',
              altBaslik: premium
                  ? 'Aboneliğini görüntüle ve yönet'
                  : 'Sınırsız soru, oyun ve analiz',
              renk: c.gold,
              vurgulu: !premium,
              onTap: () => git(const PremiumScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Çekmecenin üstündeki kullanıcı kartı.
class _Baslik extends StatelessWidget {
  final String name;
  final bool premium;
  const _Baslik({required this.name, required this.premium});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final gorunenAd = name.trim().isEmpty ? 'Aday' : name.trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kDsRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.violet.withValues(alpha: c.isLight ? 0.18 : 0.30),
            c.rose.withValues(alpha: c.isLight ? 0.10 : 0.16),
          ],
        ),
        border: Border.all(color: c.violet.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.violet.withValues(alpha: 0.22),
              border: Border.all(
                color: premium ? c.gold : c.violetL,
                width: 1.6,
              ),
            ),
            child: Text(
              gorunenAd.characters.first.toUpperCase(),
              style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w900, color: c.text),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  gorunenAd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.baloo2(
                      fontSize: 18, fontWeight: FontWeight.w700, color: c.text),
                ),
                const SizedBox(height: 4),
                DsChip(
                  label: premium ? '👑 PREMIUM' : 'ÜCRETSİZ',
                  color: premium ? c.gold : c.textFaint,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Çekmecedeki tek bir menü satırı — renkli zeminli kart.
class _MenuSatiri extends StatelessWidget {
  final String emoji;
  final String baslik;
  final String altBaslik;
  final Color renk;
  final VoidCallback onTap;

  /// true ise kart daha belirgin (dolgu + ışıma) çizilir — Premium gibi
  /// dikkat çekmesi istenen satırlar için.
  final bool vurgulu;

  const _MenuSatiri({
    required this.emoji,
    required this.baslik,
    required this.altBaslik,
    required this.renk,
    required this.onTap,
    this.vurgulu = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(kDsRadiusSm),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kDsRadiusSm),
            color: renk.withValues(
                alpha: vurgulu
                    ? (c.isLight ? 0.16 : 0.20)
                    : (c.isLight ? 0.08 : 0.12)),
            border: Border.all(
              color: renk.withValues(alpha: vurgulu ? 0.55 : 0.30),
              width: vurgulu ? 1.4 : 1,
            ),
            boxShadow: vurgulu
                ? [BoxShadow(color: renk.withValues(alpha: 0.22), blurRadius: 14)]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    color: renk.withValues(alpha: 0.20),
                    border: Border.all(color: renk.withValues(alpha: 0.45)),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(baslik,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: c.text)),
                      const SizedBox(height: 2),
                      Text(altBaslik,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, height: 1.3, color: c.textFaint)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: renk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
