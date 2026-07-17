import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subject.dart';
import '../services/data_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';
import 'card_game_screen.dart';
import 'card_game_v2_screen.dart';
import 'map_game/map_game_screen.dart';
import 'map_game/map_shared.dart';
import 'solitaire_screen.dart';
import 'mnemonics_screen.dart';
import 'predictor_screen.dart';
import 'league_screen.dart';
import 'stopwatch_screen.dart';
import 'mentor_screen.dart';
import 'premium_screen.dart';
import 'quick_modes/hizli_karar_screen.dart';
import 'quick_modes/bilgi_maratonu_screen.dart';
import 'quick_modes/gunun_patronu_screen.dart';
import 'quick_modes/hiz_60_screen.dart';
import 'quick_modes/balon_patlat_screen.dart';
import 'quick_modes/zincirleme_bilgi_screen.dart';
import 'quick_modes/kimim_ben_screen.dart';
import 'quick_modes/yazim_yanlislari_screen.dart';
import 'quick_modes/tarihleri_bil_screen.dart';
import 'score_calculator_screen.dart';
import 'duel/duel_lobby_screen.dart';
import '../theme/subject_colors.dart';

/// JS: FREE_CARDGAME_DAILY / FREE_GAME_DAILY — üç oyunun da günlük ücretsiz hakkı 10'dur
/// (JS'te her oyunun kendi ayrı sayacı vardır, bkz. StorageService.getGamePlayState).
const int kFreeGameDailyLimit = 10;

/// Kart Oyunu (v1 "Kart Eşleştirme Oyunu" + v2 "Kart Oyunu V2") ikisi birden
/// TEK bir toplam oynama süresi altında toplansın diye kullanılan ortak oyun
/// kimliği — StorageService.getGameTimeSpent/addGameTimeSpent içindir; günlük
/// hak sayaçları (getCardGameState / getGamePlayState('cardgame2')) bundan
/// AYRIDIR ve değişmeden kalır.
const String kKartOyunuGameId = 'kart_oyunu';

/// Saniye cinsinden bir süreyi "1 sa 12 dk" / "8 dk" / "45 sn" gibi kısa,
/// kullanıcı dostu bir Türkçe metne çevirir — Kart Oyunu / Balon Patlat /
/// Hız 60 / Düello ekranlarındaki "Toplam ... oynadın" etiketlerinde kullanılır.
String formatPlayDuration(int totalSeconds) {
  if (totalSeconds < 60) return '$totalSeconds sn';
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  if (h > 0) return '$h sa $m dk';
  return '$m dk';
}

/// Oyun ekranlarının AppBar'ına eklenen "ℹ️" bilgi butonu — kısa bir "nasıl
/// oynanır" açıklamasını AlertDialog içinde gösterir. Kart Oyunu / Balon
/// Patlat / Hız 60 / Düello ekranlarının HEPSİNDE AYNI keşfedilebilir mekanizma
/// (bir bilgi ikonu) kullanılsın diye burada tek noktadan tanımlanır.
class HowToPlayButton extends StatelessWidget {
  final String title;
  final String body;
  const HowToPlayButton({super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Nasıl oynanır?',
      icon: const Icon(Icons.info_outline),
      onPressed: () {
        context.read<SoundService>().click();
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(body, style: const TextStyle(height: 1.5)),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Anladım')),
            ],
          ),
        );
      },
    );
  }
}

/// Oyunlar Hub — JS: renderToolsHub (eski adıyla "Araçlar").
class ToolsHubScreen extends StatefulWidget {
  const ToolsHubScreen({super.key});

  @override
  State<ToolsHubScreen> createState() => _ToolsHubScreenState();
}

class _ToolsHubScreenState extends State<ToolsHubScreen> {
  late final Future<List<Subject>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<DataService>().loadAll();
  }

  void _goPremiumGated(BuildContext context, bool premium, Widget screen) {
    if (!premium) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final premium = storage.isPremiumUser();

    return Scaffold(
      appBar: AppBar(title: const Text('🎮 Oyunlar')),
      body: FutureBuilder<List<Subject>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final subjects = snap.data!.where((s) => s.konular.isNotEmpty).toList();

          final cg = storage.getCardGameState();
          final cgLeft = (kFreeGameDailyLimit - (cg['plays'] as int)).clamp(0, kFreeGameDailyLimit);
          final g2 = storage.getGamePlayState('cardgame2');
          final g2Left = (kFreeGameDailyLimit - (g2['plays'] as int)).clamp(0, kFreeGameDailyLimit);
          final sol = storage.getGamePlayState('solitaire');
          final solLeft = (kFreeGameDailyLimit - (sol['plays'] as int)).clamp(0, kFreeGameDailyLimit);
          final haritaLeft = mapGameDailyLeft(storage);

          final hk = storage.getGamePlayState(kHizliKararGameId);
          final hkLeft = (kFreeGameDailyLimit - (hk['plays'] as int)).clamp(0, kFreeGameDailyLimit);
          final bm = storage.getGamePlayState(kBilgiMaratonuGameId);
          final bmLeft = (kFreeGameDailyLimit - (bm['plays'] as int)).clamp(0, kFreeGameDailyLimit);
          final h60 = storage.getGamePlayState(kHiz60GameId);
          final h60Left = (kFreeGameDailyLimit - (h60['plays'] as int)).clamp(0, kFreeGameDailyLimit);
          final gununPatronuOynandi = storage.hasPlayedGununPatronuToday();

          final bp = storage.getGamePlayState(kBalonPatlatGameId);
          final bpLeft = (kFreeGameDailyLimit - (bp['plays'] as int)).clamp(0, kFreeGameDailyLimit);
          final zb = storage.getGamePlayState(kZincirlemeBilgiGameId);
          final zbLeft = (kFreeGameDailyLimit - (zb['plays'] as int)).clamp(0, kFreeGameDailyLimit);
          final kb = storage.getGamePlayState(kKimimBenGameId);
          final kbLeft = (kFreeGameDailyLimit - (kb['plays'] as int)).clamp(0, kFreeGameDailyLimit);

          final yy = storage.getGamePlayState(kYazimYanlislariGameId);
          final yyLeft = (kFreeGameDailyLimit - (yy['plays'] as int)).clamp(0, kFreeGameDailyLimit);
          final tb = storage.getGamePlayState(kTarihleriBilGameId);
          final tbLeft = (kFreeGameDailyLimit - (tb['plays'] as int)).clamp(0, kFreeGameDailyLimit);

          final c = context.watch<ThemeProvider>().colors;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Çalışmanı güçlendirecek oyunlar ve ekstra araçlar.',
                  style: TextStyle(fontSize: 13.5, color: c.textFaint)),
              const SizedBox(height: 18),
              const _SectionTitle('🎮 Oyunlar'),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.0,
                children: [
                  ToolCard(
                    icon: '⚔️',
                    title: 'KPSS Düello',
                    desc: 'POPÜLER! Rakiplerinle canlı 1v1 düello ya da çok kişilik Royale. '
                        '${premium ? "Sınırsız oyna." : "Günde $kFreeGameDailyLimit ücretsiz maç."}',
                    palette: const SubjectPalette(Color(0xFFEF4444), Color(0xFF7C2D12)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const DuelLobbyScreen())),
                  ),
                  ToolCard(
                    icon: '🃏',
                    title: 'Kart Eşleştirme Oyunu',
                    desc: premium ? 'Sınırsız oyna.' : 'Bugün $cgLeft hakkın kaldı.',
                    palette: const SubjectPalette(Color(0xFFF472B6), Color(0xFFC026D3)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => CardGameScreen(subjects: subjects))),
                  ),
                  ToolCard(
                    icon: '🃏',
                    title: 'Kart Oyunu V2',
                    desc: 'Ders/konu seç, açık kartları eşleştir. '
                        '${premium ? "Sınırsız oyna." : "Bugün $g2Left hakkın kaldı."}',
                    palette: const SubjectPalette(Color(0xFFA78BFA), Color(0xFF7C3AED)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => CardGameV2Screen(subjects: subjects))),
                  ),
                  ToolCard(
                    icon: '🂡',
                    title: 'Solitaire',
                    desc: 'Ders/konu seç, kartları sırayla temizle. '
                        '${premium ? "Sınırsız oyna." : "Bugün $solLeft hakkın kaldı."}',
                    palette: const SubjectPalette(Color(0xFF34D399), Color(0xFF059669)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => SolitaireScreen(subjects: subjects))),
                  ),
                  ToolCard(
                    icon: '🗺️',
                    title: 'Harita Oyunu',
                    // "Haritadan Öğren" ARTIK burada AYRI bir kart DEĞİL — Harita
                    // Oyunu'na girince (bkz. map_game/map_game_screen.dart) hem
                    // puansız "Haritadan Öğren" kütüphanesi hem TÜM skorlu mini
                    // oyun modları tek ekranda birlikte listeleniyor.
                    desc: 'Türkiye haritasında illeri, bölgeleri fethet ya da puansız öğren. '
                        '${premium ? "Sınırsız oyna." : "Bugün $haritaLeft hakkın kaldı."}',
                    palette: const SubjectPalette(Color(0xFF60A5FA), Color(0xFF2563EB)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => MapGameScreen(subjects: subjects))),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              const _SectionTitle('⚡ Hızlı Modlar'),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.0,
                children: [
                  ToolCard(
                    icon: '⚡',
                    title: 'Hızlı Karar',
                    desc: 'Her soru için sadece birkaç saniyen var, doğru/yanlış hızlı seç. '
                        '${premium ? "Sınırsız oyna." : "Bugün $hkLeft hakkın kaldı."}',
                    palette: const SubjectPalette(Color(0xFFFBBF24), Color(0xFFD97706)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => HizliKararScreen(subjects: subjects))),
                  ),
                  ToolCard(
                    icon: '🏃',
                    title: 'Bilgi Maratonu',
                    desc: 'Tüm derslerden sonsuz soru akışı, ilk yanlışta seri biter. '
                        '${premium ? "Sınırsız oyna." : "Bugün $bmLeft hakkın kaldı."}',
                    palette: const SubjectPalette(Color(0xFFFB923C), Color(0xFFDC2626)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => BilgiMaratonuScreen(subjects: subjects))),
                  ),
                  ToolCard(
                    icon: '👑',
                    title: 'Günün Patronu',
                    desc: gununPatronuOynandi
                        ? 'Bugün zaten oynadın, yarın tekrar gel.'
                        : '20 özel soruluk günlük tur. Günde 1 kez oynanır.',
                    palette: const SubjectPalette(Color(0xFFFACC15), Color(0xFF7C3AED)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => GununPatronuScreen(subjects: subjects))),
                  ),
                  ToolCard(
                    icon: '⏱️',
                    title: '60 Saniye Challenge',
                    desc: 'Tüm derslerden karışık sorularla 60 saniyede kaç doğru yapabilirsin? '
                        '${premium ? "Sınırsız oyna." : "Bugün $h60Left hakkın kaldı."}',
                    palette: const SubjectPalette(Color(0xFFF87171), Color(0xFFEA580C)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => Hiz60Screen(subjects: subjects))),
                  ),
                  ToolCard(
                    icon: '✍️',
                    title: 'Yazım Yanlışları',
                    desc: 'Doğru yazımı bul, süre dolmadan seç! '
                        '${premium ? "Sınırsız oyna." : "Bugün $yyLeft hakkın kaldı."}',
                    palette: const SubjectPalette(Color(0xFF2DD4BF), Color(0xFF0891B2)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const YazimYanlislariScreen())),
                  ),
                  ToolCard(
                    icon: '📅',
                    title: 'Tarihleri Bil',
                    desc: 'Önemli olayların doğru yılını bil. '
                        '${premium ? "Sınırsız oyna." : "Bugün $tbLeft hakkın kaldı."}',
                    palette: const SubjectPalette(Color(0xFFB45309), Color(0xFF78350F)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const TarihleriBilScreen())),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              const _SectionTitle('🧩 Ek Oyunlar'),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.0,
                children: [
                  ToolCard(
                    icon: '🎈',
                    title: 'Balon Patlat',
                    desc: 'Doğru cevabın balonuna dokun, yanlışlardan kaç. '
                        '${premium ? "Sınırsız oyna." : "Bugün $bpLeft hakkın kaldı."}',
                    palette: const SubjectPalette(Color(0xFF38BDF8), Color(0xFFF472B6)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => BalonPatlatScreen(subjects: subjects))),
                  ),
                  ToolCard(
                    icon: '🔗',
                    title: 'Zincirleme Bilgi',
                    desc: 'Tarihi/coğrafi bilgi zincirlerini adım adım çöz. '
                        '${premium ? "Sınırsız oyna." : "Bugün $zbLeft zincir hakkın kaldı."}',
                    palette: const SubjectPalette(Color(0xFF6366F1), Color(0xFF3B82F6)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const ZincirlemeBilgiScreen())),
                  ),
                  ToolCard(
                    icon: '🕵️',
                    title: 'Kimim Ben',
                    desc: 'İpuçlarıyla tarihi kişiyi bil, erken bilirsen daha çok puan al. '
                        '${premium ? "Sınırsız oyna." : "Bugün $kbLeft hakkın kaldı."}',
                    palette: const SubjectPalette(Color(0xFF8B5CF6), Color(0xFFD946EF)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const KimimBenScreen())),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              const _SectionTitle('🧰 Diğer Araçlar'),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.0,
                children: [
                  ToolCard(
                    icon: '🧠',
                    title: 'Akılda Kalıcı Kodlama',
                    desc: 'Konuların kısa, şifreli özetleriyle hızlı tekrar.',
                    locked: !premium,
                    palette: const SubjectPalette(Color(0xFF14B8A6), Color(0xFF16A34A)),
                    onTap: () => _goPremiumGated(context, premium, MnemonicsScreen(subjects: subjects)),
                  ),
                  ToolCard(
                    icon: '🎯',
                    title: 'Bugün Sınava Girsen Kaç Alırsın?',
                    desc: 'Geçmiş performansına göre tahmini puan.',
                    locked: !premium,
                    palette: const SubjectPalette(Color(0xFFF59E0B), Color(0xFFEA580C)),
                    onTap: () => _goPremiumGated(context, premium, const PredictorScreen()),
                  ),
                  ToolCard(
                    icon: '🏆',
                    title: 'Özel Lig',
                    desc: 'Başarı seviyene göre lig rütbeni gör.',
                    locked: !premium,
                    palette: const SubjectPalette(Color(0xFFFACC15), Color(0xFFB45309)),
                    onTap: () => _goPremiumGated(context, premium, const LeagueScreen()),
                  ),
                  ToolCard(
                    icon: '⏱️',
                    title: 'Çalışma Kronometresi',
                    desc: 'Ders bazlı çalışma sürelerini kaydet ve analiz et.',
                    locked: !premium,
                    palette: const SubjectPalette(Color(0xFF60A5FA), Color(0xFF1E3A8A)),
                    onTap: () => _goPremiumGated(context, premium, const StopwatchScreen()),
                  ),
                  ToolCard(
                    icon: '🎓',
                    title: 'Mentörlük Seansları',
                    desc: 'Sınav stratejileri ve haftalık plan önerileri.',
                    locked: !premium,
                    palette: const SubjectPalette(Color(0xFF8B5CF6), Color(0xFF4338CA)),
                    onTap: () => _goPremiumGated(context, premium, const MentorScreen()),
                  ),
                  ToolCard(
                    icon: '🧮',
                    title: 'Puan Hesaplama',
                    desc: 'Doğru/yanlış sayılarını gir, net ve tahmini KPSS puanını gör.',
                    palette: const SubjectPalette(Color(0xFF22C55E), Color(0xFF0D9488)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const ScoreCalculatorScreen())),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800));
}

const SubjectPalette _kToolCardFallbackPalette = SubjectPalette(Color(0xFF8B5CF6), Color(0xFFF472B6));

/// Oyunlar/Araçlar hub'ındaki tek bir kart — her oyun/araç kendi renk kimliğini
/// taşır (bkz. görev talimatı: "Oyunlar" hub'ındaki her kart renkli/ayırt
/// edici olsun). Ders ekranlarındaki AYNI desen kullanılır (bkz.
/// lib/theme/subject_colors.dart `subjectCardDecoration` — home_screen.dart
/// _SubjectCard ile birebir aynı Container/Material/InkWell iskeleti).
class ToolCard extends StatelessWidget {
  final String icon, title, desc;
  final bool locked;
  final SubjectPalette? palette;
  final VoidCallback onTap;
  const ToolCard({
    super.key,
    required this.icon,
    required this.title,
    required this.desc,
    this.locked = false,
    this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final p = palette ?? _kToolCardFallbackPalette;
    return Container(
      decoration: subjectCardDecoration(palette: p, isLight: c.isLight),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            context.read<SoundService>().click();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(locked ? '🔒' : icon, style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    desc,
                    style: TextStyle(fontSize: 11.5, color: c.textFaint),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Premium kilitli özellik ekranı — JS: renderLockedFeature.
class LockedFeatureCard extends StatelessWidget {
  final String title;
  final String desc;
  const LockedFeatureCard({super.key, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('🔒 $title')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(desc, style: TextStyle(color: context.watch<ThemeProvider>().colors.textFaint, height: 1.6)),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () {
                    context.read<SoundService>().click();
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                  },
                  child: const Text("Premium'a Geç"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
