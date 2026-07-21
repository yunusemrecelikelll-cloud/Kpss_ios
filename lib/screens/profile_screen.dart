import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/subject.dart';
import '../models/badge.dart';
import '../services/league_service.dart';
import '../services/storage_service.dart';
import '../services/sound_service.dart';
import '../theme/app_theme.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';
import '../utils/exam_dates.dart';
import 'badges_screen.dart';
import 'detailed_stats_screen.dart';
import 'premium_screen.dart';
import 'predictor_screen.dart';
import 'league_screen.dart';
import 'score_calculator_screen.dart';

/// JS karşılığı: renderProfile() (src/js/app.js).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final c = context.watch<ThemeProvider>().colors;
    // İsim önceliği getUserName()'e verildi: profil düzenleme diyaloğu
    // StorageService.setUserName() ile kaydediyor, güncel değer hemen görünsün diye.
    final name = storage.getUserName().isNotEmpty
        ? storage.getUserName()
        : (storage.getActiveUser().isNotEmpty ? storage.getActiveUser() : 'Aday');
    final gender = storage.getUserGender();
    final premium = storage.isPremiumUser();
    final overall = storage.computeOverall();
    final streak = storage.getStreak();
    final streakCount = (streak['count'] as int?) ?? 0;
    final wrongCount = storage.getWrongBank().length;
    final badgeCount = storage.getUnlockedBadges().length;
    final hideStats = storage.getHideStatsEnabled();

    // Bu ekran açıldığında (ya da veriler değişip yeniden çizildiğinde) kendi
    // güncel stat/rozet/gizlilik özetini Firestore'a yayınla — böylece
    // sohbet/DM'den bu kullanıcının profiline bakan BAŞKA kullanıcılar
    // (bkz. PublicProfileScreen) güncel veriyi görür. Sessizce başarısız olur
    // (offline/Firebase yapılandırılmamış/giriş yok) — bu ekranın kendi
    // görünümünü ETKİLEMEZ.
    // ignore: unawaited_futures
    LeagueService().publishMyScore(storage);

    // JS: SUBJECTS.filter(s => s.data).map(...).filter(avg !== null)
    final subjectAverages = <({String id, String label, int avg})>[];
    for (final meta in kSubjects) {
      final avg = storage.computeSubjectAvg(meta.id);
      if (avg != null) subjectAverages.add((id: meta.id, label: meta.ad, avg: avg));
    }
    ({String id, String label, int avg})? bestSub;
    ({String id, String label, int avg})? worstSub;
    for (final s in subjectAverages) {
      if (bestSub == null || s.avg >= bestSub.avg) bestSub = s;
      if (worstSub == null || s.avg <= worstSub.avg) worstSub = s;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('👤 Profil'),
        actions: [
          IconButton(
            tooltip: 'Rozetler',
            icon: const Text('🏆', style: TextStyle(fontSize: 20)),
            onPressed: () {
              context.read<SoundService>().click();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BadgesScreen()));
            },
          ),
          IconButton(
            tooltip: 'İsim / Cinsiyet Düzenle',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {
              context.read<SoundService>().click();
              showDialog(
                context: context,
                builder: (_) => _EditProfileDialog(
                  storage: storage,
                  initialName: name == 'Aday' ? '' : name,
                  initialGender: gender,
                  initialExamType: storage.getExamType(),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Kimlik kartı ───────────────────────────────────────────
            // Büyük avatar + isim + hedef/sınav bilgisi + seviye ilerlemesi.
            DsCard(
              accent: premium ? c.gold : c.violet,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ProfileAvatar(name: name, gender: gender, premium: premium),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w900, color: c.text),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                DsChip(
                                  label: premium ? 'PREMIUM' : 'ÜCRETSİZ',
                                  color: premium ? c.gold : c.textDim,
                                ),
                                if (examInfoFor(storage.getExamType()) case final e?)
                                  DsChip(label: 'KPSS ${e.label}'.toUpperCase(), color: c.violetL),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _LevelXpSection(storage: storage, colors: c),
                  const SizedBox(height: 10),
                  Text(
                    '🗓️ ${storage.getCurrentSeasonLabel()} Sezonu: ${storage.getSeasonXp()} XP',
                    style: TextStyle(fontSize: 11.5, color: c.textFaint, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: kDsGap),
            DsCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                secondary: DsIconBadge(
                  icon: Icons.visibility_off_outlined,
                  color: c.violetL,
                  size: 42,
                  circle: false,
                  glow: false,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kDsRadius)),
                value: hideStats,
                onChanged: (v) async {
                  context.read<SoundService>().click();
                  await storage.setHideStatsEnabled(v);
                  // ignore: unawaited_futures
                  LeagueService().publishMyScore(storage);
                },
                title: const Text('İstatistiklerimi Gizle', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                subtitle: Text(
                  'Açıkken, diğer kullanıcılar sohbet/DM üzerinden profiline baktığında '
                  'gerçek sayılar yerine sadece "istatistiklerini gizli tutuyor" yazısını görür.',
                  style: TextStyle(fontSize: 11, color: c.textFaint),
                ),
              ),
            ),
            const SizedBox(height: kDsGap),
            const DsSectionHeader(title: '📊 Özet İstatistikler'),
            const SizedBox(height: 8),
            DsStatStrip(
              items: [
                DsStatItem(
                  visual: DsIconBadge(emoji: '🎯', color: c.violetL, size: 38, glow: false),
                  value: '${overall.rate}%',
                  label: 'Genel Başarı',
                ),
                DsStatItem(
                  visual: DsIconBadge(emoji: '📝', color: c.mint, size: 38, glow: false),
                  value: '${overall.solved}',
                  label: 'Çözülen Soru',
                ),
                DsStatItem(
                  visual: DsIconBadge(emoji: '🔥', color: c.gold, size: 38, glow: false),
                  value: '$streakCount',
                  label: 'Günlük Seri',
                ),
                DsStatItem(
                  visual: DsIconBadge(emoji: '❌', color: c.roseL, size: 38, glow: false),
                  value: '$wrongCount',
                  label: 'Yanlışlar',
                ),
              ],
            ),
            const SizedBox(height: kDsGap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _InfoBox(
                    title: '$badgeCount Rozet',
                    text: 'Topladığın rozetleri ve başarı puanlarını takip et.',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoBox(
                    title: bestSub != null ? '${bestSub.label} en iyi ders' : 'Daha fazla çöz',
                    text: bestSub != null ? 'Başarı oranın %${bestSub.avg}' : 'Test çözerek ilk dersini belirle.',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoBox(
                    title: worstSub != null ? '${worstSub.label} üzerinde çalış' : 'Henüz veri yok',
                    text: worstSub != null ? 'Başarı oranın %${worstSub.avg}' : 'Çözdüğün sorular burada listelenecek.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const DsSectionHeader(title: '🧭 Analiz Araçları'),
            const SizedBox(height: 8),
            DsListRow(
              icon: Icons.query_stats,
              accent: c.violetL,
              title: 'Detaylı İstatistikler',
              status: 'Ders/konu başarısı, seri geçmişi, çalışma süresi.',
              onTap: () {
                context.read<SoundService>().click();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DetailedStatsScreen()));
              },
            ),
            const SizedBox(height: kDsGap),
            // ÖNCEDEN "Oyunlar" sekmesindeki "Diğer Araçlar" bölümündeydi —
            // üçü de kişisel performansla ilgili olduğu için Profil'e taşındı
            // (bkz. tools_hub_screen.dart). Premium kilidi aynen korunuyor:
            // premium olmayan kullanıcı dokununca Premium ekranına yönlenir.
            DsListRow(
              icon: Icons.track_changes,
              accent: c.rose,
              title: 'Bugün Sınava Girsen Kaç Alırsın?',
              status: premium
                  ? 'Geçmiş performansına göre tahmini puanın.'
                  : '🔒 Premium — tahmini puanını gör.',
              onTap: () {
                context.read<SoundService>().click();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => premium ? const PredictorScreen() : const PremiumScreen()));
              },
            ),
            const SizedBox(height: kDsGap),
            DsListRow(
              icon: Icons.emoji_events,
              accent: c.gold,
              title: 'Özel Lig',
              status: premium
                  ? 'Başarı seviyene göre lig rütbeni gör.'
                  : '🔒 Premium — lig rütbeni gör.',
              onTap: () {
                context.read<SoundService>().click();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => premium ? const LeagueScreen() : const PremiumScreen()));
              },
            ),
            const SizedBox(height: kDsGap),
            DsListRow(
              icon: Icons.calculate,
              accent: c.mint,
              title: 'Puan Hesaplama',
              status: 'Doğru/yanlış gir, net ve tahmini KPSS puanını gör.',
              onTap: () {
                context.read<SoundService>().click();
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ScoreCalculatorScreen()));
              },
            ),
            const SizedBox(height: 18),
            _UnlockedBadgesCard(unlockedIds: storage.getUnlockedBadges().toSet()),
            const SizedBox(height: 16),
            if (premium)
              DsCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📈 Konu Başarı Grafiği',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 15, color: c.text)),
                      const SizedBox(height: 14),
                      if (subjectAverages.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text('Henüz yeterli veri yok. Birkaç test çöz, grafik burada oluşsun.'),
                        )
                      else
                        SizedBox(
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
                                      color: Theme.of(context).colorScheme.primary,
                                      width: 20,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ]),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        'Premium hesapta konu skorların görselleştirilir.',
                        style: TextStyle(fontSize: 11.5, color: c.textFaint),
                      ),
                    ],
                  ),
              )
            else
              DsCard(
                accent: c.gold,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        DsIconBadge(emoji: '🔒', color: c.gold, size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text("Premium İstatistiklere Geç",
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 15, color: c.text)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Ücretsiz hesapla temel verileri görürsün. Premium'da grafikler, konu analizi ve gelişmiş raporlar açılır.",
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textDim),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DsPillButton(
                        label: "Premium'a Geç",
                        color: c.gold,
                        trailingIcon: Icons.arrow_forward,
                        onPressed: () {
                          context.read<SoundService>().click();
                          Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                        },
                      ),
                    ),
                  ],
                ),
              ),
            if (premium) ...[
              const SizedBox(height: 16),
              const _PremiumPerksCard(),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (premium)
                  TextButton(
                    onPressed: () {
                      context.read<SoundService>().click();
                      Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                    },
                    child: const Text('Premium Ayrıntıları Gör'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Profil kimlik kartındaki büyük dairesel avatar — ismin baş harfini,
/// tema renklerinden türeyen bir degrade halka içinde gösterir. Premium
/// kullanıcıda halka altın rengine döner.
class _ProfileAvatar extends StatelessWidget {
  final String name;
  final String gender;
  final bool premium;
  const _ProfileAvatar({required this.name, required this.gender, required this.premium});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final bas = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final halka = premium ? c.gold : c.violetL;
    return Container(
      width: 66,
      height: 66,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            halka.withValues(alpha: c.isLight ? 0.22 : 0.32),
            c.rose.withValues(alpha: c.isLight ? 0.14 : 0.22),
          ],
        ),
        border: Border.all(color: halka.withValues(alpha: 0.55), width: 2),
        boxShadow: [BoxShadow(color: halka.withValues(alpha: 0.25), blurRadius: 16)],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(bas,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: c.text)),
          // Cinsiyet seçilmişse küçük bir işaret — profil düzenlemede
          // kaydedilen mevcut değer, uydurma bir alan değil.
          if (gender == 'k' || gender == 'e')
            Positioned(
              right: 2,
              bottom: 0,
              child: Text(gender == 'k' ? '👩' : '👨',
                  style: const TextStyle(fontSize: 15)),
            ),
        ],
      ),
    );
  }
}

/// Seviye + XP ilerleme çubuğu — mevcut seviyeden bir sonraki seviyeye olan
/// ilerlemeyi gösterir (bkz. StorageService.getLevelForXp/xpForNextLevel).
class _LevelXpSection extends StatelessWidget {
  final StorageService storage;
  final KpssColors colors;
  const _LevelXpSection({required this.storage, required this.colors});

  @override
  Widget build(BuildContext context) {
    final xp = storage.getTotalXp();
    final level = StorageService.getLevelForXp(xp);
    final levelStartXp = StorageService.xpForLevel(level);
    final nextLevelXp = StorageService.xpForNextLevel(level);
    final span = nextLevelXp - levelStartXp;
    final into = xp - levelStartXp;
    final ratio = span <= 0 ? 1.0 : (into / span).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('⭐ Seviye $level',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13.5, color: colors.text)),
            ),
            const SizedBox(width: 8),
            Text('$xp XP toplam', style: TextStyle(fontSize: 11.5, color: colors.textFaint)),
          ],
        ),
        const SizedBox(height: 8),
        DsProgressBar(value: ratio.toDouble(), color: colors.violetL, height: 8),
        const SizedBox(height: 6),
        Text(
          'Sonraki seviyeye $into / $span XP',
          style: TextStyle(fontSize: 10.5, color: colors.textFaint),
        ),
      ],
    );
  }
}

/// Kullanıcının şu ana kadar açtığı rozetleri gösterir. Hiç rozet açılmadıysa
/// teşvik edici bir boş durum mesajı gösterir.
class _UnlockedBadgesCard extends StatelessWidget {
  final Set<String> unlockedIds;
  const _UnlockedBadgesCard({required this.unlockedIds});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final unlocked = kBadgeDefs.where((b) => unlockedIds.contains(b.id)).toList();
    return DsCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DsIconBadge(emoji: '🏅', color: c.gold, size: 42, circle: false, glow: false),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Rozetlerim',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15, color: c.text)),
              ),
              DsChip(label: '${unlocked.length}/${kBadgeDefs.length}', color: c.gold),
            ],
          ),
          const SizedBox(height: 14),
          if (unlocked.isEmpty)
            Text('Henüz rozet açmadın. Test çözmeye devam et, ilk rozetin yakında!',
                style: TextStyle(fontSize: 12.5, color: c.textFaint))
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final b in unlocked)
                  Tooltip(
                    message: b.desc,
                    child: Container(
                      width: 72,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                      decoration: BoxDecoration(
                        color: b.color.withValues(alpha: c.isLight ? 0.10 : 0.14),
                        borderRadius: BorderRadius.circular(kDsRadiusSm),
                        border: Border.all(color: b.color.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(b.icon, style: const TextStyle(fontSize: 22)),
                          const SizedBox(height: 4),
                          Text(b.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: c.text)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String title, text;
  const _InfoBox({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return DsCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: c.text)),
          const SizedBox(height: 4),
          Text(text, style: TextStyle(fontSize: 10.5, height: 1.3, color: c.textFaint)),
        ],
      ),
    );
  }
}

/// Premium kullanıcılara özel ayrıcalık listesi. Özellik isimleri
/// lib/screens/premium_screen.dart'taki _FeatureTile listesiyle uyumlu,
/// ayrıca birkaç ek premium özellik (karakterler, kodlama, oyun) eklendi.
class _PremiumPerksCard extends StatelessWidget {
  const _PremiumPerksCard();

  static const _perks = <(String, String)>[
    ('♾️', 'Sınırsız Test'),
    ('🧠', 'Yanlışlarımı Sına'),
    ('📊', 'Detaylı İstatistik'),
    ('🎧', 'Sesli Özetler'),
    ('⭐', 'VIP Rozet'),
    ('🎭', 'Premium Karakterler'),
    ('🧩', 'Akılda Kalıcı Kodlama'),
    ('🎮', 'Sınırsız Oyun'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return DsCard(
      accent: c.gold,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DsIconBadge(emoji: '✨', color: c.gold, size: 42, circle: false, glow: false),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Premium Ayrıcalıkların',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15, color: c.text)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final p in _perks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(p.$1, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(p.$2,
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: c.text))),
                  Icon(Icons.check_circle, size: 16, color: c.success),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// İsim / cinsiyet / sınav türü düzenleme diyaloğu.
///
/// Tasarım dili uygulamanın geri kalanıyla aynı: zemin `c.bg2`, bölümler
/// [DsCard] içinde, seçimler hap biçimli, eylemler [DsPillButton]. Tüm renkler
/// [ThemeProvider] token'larından gelir — 9 tema + açık temada okunur kalır.
/// Kaydedince StorageService.setUserName() / setUserGender() / setExamType()
/// çağrılır.
class _EditProfileDialog extends StatefulWidget {
  final StorageService storage;
  final String initialName;
  final String initialGender;
  final String initialExamType;
  const _EditProfileDialog({
    required this.storage,
    required this.initialName,
    required this.initialGender,
    required this.initialExamType,
  });

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final TextEditingController _nameCtrl;
  late String _gender;
  late String _examType;

  /// İsim boşken "Kaydet"e basılırsa alan altında gösterilen uyarı.
  String? _isimHata;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _gender = widget.initialGender;
    _examType = widget.initialExamType;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _isimHata = 'Lütfen bir isim gir.');
      return;
    }
    await widget.storage.setUserName(name);
    await widget.storage.setUserGender(_gender);
    await widget.storage.setExamType(_examType);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final secilenSinav = examInfoFor(_examType);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          decoration: BoxDecoration(
            color: c.bg2,
            borderRadius: BorderRadius.circular(kDsRadius),
            border: Border.all(color: c.border),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Başlık ────────────────────────────────────────────────
              Row(
                children: [
                  DsIconBadge(
                    icon: Icons.edit_outlined,
                    color: c.violetL,
                    size: 42,
                    circle: false,
                    glow: false,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Profili Düzenle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w900,
                              color: c.text),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Bu bilgiler yalnızca cihazında saklanır.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: c.textFaint),
                        ),
                      ],
                    ),
                  ),
                  if (secilenSinav != null) ...[
                    const SizedBox(width: 8),
                    DsChip(
                        label: 'KPSS ${secilenSinav.label}'.toUpperCase(),
                        color: c.violetL),
                  ],
                ],
              ),
              const SizedBox(height: 14),

              // ── Alanlar (klavye açıkken kaydırılabilir) ───────────────
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DsCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _AlanBasligi(text: 'İsmin'),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _nameCtrl,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.done,
                              onChanged: (_) {
                                if (_isimHata != null) {
                                  setState(() => _isimHata = null);
                                }
                              },
                              onSubmitted: (_) => _save(),
                              style: TextStyle(fontSize: 14.5, color: c.text),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor: c.glass2,
                                hintText: 'Adın nasıl görünsün?',
                                hintStyle:
                                    TextStyle(fontSize: 13.5, color: c.textFaint),
                                prefixIcon: Icon(Icons.person_outline,
                                    size: 19, color: c.textFaint),
                                errorText: _isimHata,
                                errorStyle:
                                    TextStyle(fontSize: 11.5, color: c.danger),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 14),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(kDsRadiusSm),
                                  borderSide: BorderSide(color: c.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(kDsRadiusSm),
                                  borderSide:
                                      BorderSide(color: c.violetL, width: 1.6),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(kDsRadiusSm),
                                  borderSide: BorderSide(color: c.danger),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(kDsRadiusSm),
                                  borderSide:
                                      BorderSide(color: c.danger, width: 1.6),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: kDsGap),
                      DsCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _AlanBasligi(text: 'Cinsiyet'),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _SecimPili(
                                  label: '👩 Kadın',
                                  selected: _gender == 'k',
                                  onTap: () => setState(() => _gender = 'k'),
                                ),
                                _SecimPili(
                                  label: '👨 Erkek',
                                  selected: _gender == 'e',
                                  onTap: () => setState(() => _gender = 'e'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: kDsGap),
                      DsCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _AlanBasligi(text: 'Hangi sınava gireceksin?'),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final e in kExamTypes)
                                  _SecimPili(
                                    label: e.label,
                                    selected: _examType == e.id,
                                    onTap: () =>
                                        setState(() => _examType = e.id),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Eylemler ──────────────────────────────────────────────
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      context.read<SoundService>().click();
                      Navigator.of(context).pop();
                    },
                    child: Text('Vazgeç',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: c.textDim)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: DsPillButton(
                      label: 'Kaydet',
                      color: c.violetL,
                      leadingIcon: Icons.check_rounded,
                      onPressed: () {
                        context.read<SoundService>().click();
                        _save();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Düzenleme diyaloğundaki bölüm başlığı ("İsmin", "Cinsiyet" ...).
class _AlanBasligi extends StatelessWidget {
  final String text;
  const _AlanBasligi({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w800, color: c.textDim),
    );
  }
}

/// Seçilebilir hap etiketi — cinsiyet ve sınav türü seçimlerinde kullanılır.
/// Seçiliyken tema vurgu rengine boyanır, değilken cam zeminde sönük durur;
/// her iki durumda da metin kontrastı korunur.
class _SecimPili extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SecimPili({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected
              ? c.violetL.withValues(alpha: c.isLight ? 0.16 : 0.22)
              : c.glass2,
          border: Border.all(
            color: selected ? c.violetL : c.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: 15, color: c.violetL),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? c.violetL : c.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
