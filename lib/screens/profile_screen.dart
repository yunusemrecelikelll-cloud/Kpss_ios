import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/subject.dart';
import '../models/badge.dart';
import '../services/league_service.dart';
import '../services/storage_service.dart';
import '../services/sound_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import '../utils/exam_dates.dart';
import 'badges_screen.dart';
import 'detailed_stats_screen.dart';
import 'premium_screen.dart';

/// Kullanıcının hedeflediği KPSS mesleği — profilde ve isteğe bağlı olarak
/// ileride kişiselleştirilmiş içerikte (ör. ilgili kadro soruları) kullanılmak
/// üzere sadece yerelde saklanır.
const List<({String id, String label, String icon})> kTargetProfessions = [
  (id: 'polis', label: 'Polis', icon: '👮'),
  (id: 'ogretmen', label: 'Öğretmen', icon: '👨‍🏫'),
  (id: 'memur', label: 'Memur', icon: '👨‍💼'),
  (id: 'uzman-yardimcisi', label: 'Uzman Yardımcısı', icon: '👨‍⚖️'),
];

({String id, String label, String icon})? _targetProfessionOrNull(String id) {
  for (final p in kTargetProfessions) {
    if (p.id == id) return p;
  }
  return null;
}

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
                  initialProfession: storage.getTargetProfession(),
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('👤 $name Profili',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text(
                                "Ücretsiz hesabın temel özetini, Premium'da ise detaylı analizleri gör.",
                                style: TextStyle(fontSize: 12.5, color: c.textFaint),
                              ),
                              if (_targetProfessionOrNull(storage.getTargetProfession()) case final p?) ...[
                                const SizedBox(height: 6),
                                Chip(
                                  label: Text('${p.icon} Hedef: ${p.label}', style: const TextStyle(fontSize: 11.5)),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: c.violet.withValues(alpha: 0.12),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Chip(
                              label: Text(premium ? 'Premium' : 'Ücretsiz'),
                              backgroundColor: premium
                                  ? c.gold.withValues(alpha: 0.2)
                                  : null,
                            ),
                            if (premium) ...[
                              const SizedBox(height: 4),
                              const Text('VIP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    _LevelXpSection(storage: storage, colors: c),
                    const SizedBox(height: 10),
                    Text(
                      '🗓️ ${storage.getCurrentSeasonLabel()} Sezonu: ${storage.getSeasonXp()} XP',
                      style: TextStyle(fontSize: 11.5, color: c.textFaint, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: SwitchListTile(
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
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.6,
              children: [
                _StatCard(label: 'Genel Başarı', value: '${overall.rate}%', foot: 'Çözdüğün soruların başarı oranı.'),
                _StatCard(label: 'Çözülen Soru', value: '${overall.solved}', foot: 'Toplam tamamlanan soru adedi.'),
                _StatCard(label: 'Günlük Seri', value: '$streakCount', foot: 'Kesintisiz çalışma gün sayısı.'),
                _StatCard(label: 'Yanlışlar', value: '$wrongCount', foot: 'Yanlış soruların özel çalışma bankası.'),
              ],
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 14),
            Card(
              child: ListTile(
                leading: Icon(Icons.query_stats, color: c.violet),
                title: const Text('Detaylı İstatistikler', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                subtitle: Text(
                  'Ders/konu bazlı başarı, seri geçmişi, çalışma süresi ve rozet ilerlemeni gör.',
                  style: TextStyle(fontSize: 11.5, color: c.textFaint),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  context.read<SoundService>().click();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DetailedStatsScreen()));
                },
              ),
            ),
            const SizedBox(height: 16),
            _UnlockedBadgesCard(unlockedIds: storage.getUnlockedBadges().toSet()),
            const SizedBox(height: 16),
            if (premium)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📈 Konu Başarı Grafiği', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
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
                ),
              )
            else
              Card(
                color: c.gold.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("🔒 Premium İstatistiklere Geç",
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 6),
                      const Text(
                        "Ücretsiz hesapla temel verileri görürsün. Premium'da grafikler, konu analizi ve gelişmiş raporlar açılır.",
                        style: TextStyle(fontSize: 12.5),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () {
                          context.read<SoundService>().click();
                          Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                        },
                        child: const Text("Premium'a Geç →"),
                      ),
                    ],
                  ),
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('⭐ Seviye $level', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            Text('$xp XP toplam', style: TextStyle(fontSize: 11.5, color: colors.textFaint)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: ratio, minHeight: 8),
        ),
        const SizedBox(height: 4),
        Text(
          'Sonraki seviyeye $into / $span XP',
          style: TextStyle(fontSize: 10.5, color: colors.textFaint),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value, foot;
  const _StatCard({required this.label, required this.value, required this.foot});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(fontSize: 11.5, color: c.textFaint)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(foot, style: const TextStyle(fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🏅 Rozetlerim (${unlocked.length}/${kBadgeDefs.length})',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 12),
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
                          color: b.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
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
                                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            const SizedBox(height: 4),
            Text(text, style: TextStyle(fontSize: 10.5, color: c.textFaint)),
          ],
        ),
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
    return Card(
      color: c.gold.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('✨ Premium Ayrıcalıkların',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 10),
            for (final p in _perks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(p.$1, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(p.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    Icon(Icons.check_circle, size: 16, color: c.success),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// İsim ve cinsiyet düzenleme diyaloğu.
/// Kaydedince StorageService.setUserName() / setUserGender() çağrılır.
class _EditProfileDialog extends StatefulWidget {
  final StorageService storage;
  final String initialName;
  final String initialGender;
  final String initialExamType;
  final String initialProfession;
  const _EditProfileDialog({
    required this.storage,
    required this.initialName,
    required this.initialGender,
    required this.initialExamType,
    required this.initialProfession,
  });

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final TextEditingController _nameCtrl;
  late String _gender;
  late String _examType;
  late String _profession;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _gender = widget.initialGender;
    _examType = widget.initialExamType;
    _profession = widget.initialProfession;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Lütfen bir isim gir.')));
      return;
    }
    await widget.storage.setUserName(name);
    await widget.storage.setUserGender(_gender);
    await widget.storage.setExamType(_examType);
    await widget.storage.setTargetProfession(_profession);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Profili Düzenle'),
      content: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'İsim'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          const Text('Cinsiyet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('👩 Kadın'),
                  selected: _gender == 'k',
                  onSelected: (_) => setState(() => _gender = 'k'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(
                  label: const Text('👨 Erkek'),
                  selected: _gender == 'e',
                  onSelected: (_) => setState(() => _gender = 'e'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Hangi sınava gireceksin?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in kExamTypes)
                ChoiceChip(
                  label: Text(e.label),
                  selected: _examType == e.id,
                  onSelected: (_) => setState(() => _examType = e.id),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Hedef mesleğin', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in kTargetProfessions)
                ChoiceChip(
                  label: Text('${p.icon} ${p.label}'),
                  selected: _profession == p.id,
                  onSelected: (_) => setState(() => _profession = p.id),
                ),
            ],
          ),
        ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            context.read<SoundService>().click();
            Navigator.of(context).pop();
          },
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          onPressed: () {
            context.read<SoundService>().click();
            _save();
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
