import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subject.dart';
import '../services/data_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';
import '../widgets/hak_kazan_sheet.dart';
import 'card_game_screen.dart';
import 'card_game_v2_screen.dart';
import 'map_game/map_game_screen.dart';
import 'map_game/map_shared.dart';
import 'solitaire_screen.dart';
import 'premium_screen.dart';
import 'quick_modes/hizli_karar_screen.dart';
import 'quick_modes/bilgi_maratonu_screen.dart';
import 'quick_modes/gunun_patronu_screen.dart';
import 'quick_modes/hiz_60_screen.dart';
import 'quick_modes/zincirleme_bilgi_screen.dart';
import 'quick_modes/kimim_ben_screen.dart';
import 'quick_modes/yazim_yanlislari_screen.dart';
import 'quick_modes/tarihleri_bil_screen.dart';
import 'quick_modes/dogru_yanlis_screen.dart';
import 'quick_modes/alfabe_oyunu_screen.dart';
import 'duel/duel_lobby_screen.dart';
import '../theme/subject_colors.dart';

/// JS: FREE_CARDGAME_DAILY / FREE_GAME_DAILY — tüm oyunların günlük ücretsiz hakkı 5'tir
/// (JS'te her oyunun kendi ayrı sayacı vardır, bkz. StorageService.getGamePlayState).
const int kFreeGameDailyLimit = 5;

/// Kart Oyunu (v1 "Kart Eşleştirme Oyunu" + v2 "Kart Oyunu V2") ikisi birden
/// TEK bir toplam oynama süresi altında toplansın diye kullanılan ortak oyun
/// kimliği — StorageService.getGameTimeSpent/addGameTimeSpent içindir; günlük
/// hak sayaçları (getCardGameState / getGamePlayState('cardgame2')) bundan
/// AYRIDIR ve değişmeden kalır.
const String kKartOyunuGameId = 'kart_oyunu';

/// Saniye cinsinden bir süreyi "1 sa 12 dk" / "8 dk" / "45 sn" gibi kısa,
/// kullanıcı dostu bir Türkçe metne çevirir — Kart Oyunu / Hız 60 /
/// Düello ekranlarındaki "Toplam ... oynadın" etiketlerinde kullanılır.
String formatPlayDuration(int totalSeconds) {
  if (totalSeconds < 60) return '$totalSeconds sn';
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  if (h > 0) return '$h sa $m dk';
  return '$m dk';
}

/// Oyun ekranlarının AppBar'ına eklenen "ℹ️" bilgi butonu — kısa bir "nasıl
/// oynanır" açıklamasını AlertDialog içinde gösterir. Kart Oyunu / Hız 60 /
/// Düello ekranlarının HEPSİNDE AYNI keşfedilebilir mekanizma
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

          final zb = storage.getGamePlayState(kZincirlemeBilgiGameId);
          final zbLeft = (kFreeGameDailyLimit - (zb['plays'] as int)).clamp(0, kFreeGameDailyLimit);
          final kb = storage.getGamePlayState(kKimimBenGameId);
          final kbLeft = (kFreeGameDailyLimit - (kb['plays'] as int)).clamp(0, kFreeGameDailyLimit);

          final yy = storage.getGamePlayState(kYazimYanlislariGameId);
          final yyLeft = (kFreeGameDailyLimit - (yy['plays'] as int)).clamp(0, kFreeGameDailyLimit);
          final tb = storage.getGamePlayState(kTarihleriBilGameId);
          final tbLeft = (kFreeGameDailyLimit - (tb['plays'] as int)).clamp(0, kFreeGameDailyLimit);
          final dy = storage.getGamePlayState(kDogruYanlisGameId);
          final dyLeft = (kFreeGameDailyLimit - (dy['plays'] as int)).clamp(0, kFreeGameDailyLimit);
          final ao = storage.getGamePlayState(kAlfabeOyunuGameId);
          final aoLeft = (kFreeGameDailyLimit - (ao['plays'] as int)).clamp(0, kFreeGameDailyLimit);
          final alfabeRekor = storage.getBestTimeSeconds(kAlfabeOyunuGameId);

          final c = context.watch<ThemeProvider>().colors;

          // Kartın sağ üstündeki hak çipinin metni — premium'da "Sınırsız",
          // ücretsiz hesapta o oyunun BUGÜN kalan hakkı. Sayaçların kendisi
          // yukarıda, eskisiyle birebir aynı şekilde hesaplanıyor.
          String hakEtiketi(int kalan) => premium ? 'Sınırsız' : 'Bugün $kalan hak';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Sayfanın kahraman kartı ───────────────────────────────
              // Öne çıkan oyun KPSS Düello: hem en popüler mod hem de tek
              // canlı/çok oyunculu deneyim olduğu için buradan kısayol verilir.
              DsHeroCard(
                emoji: '🎮',
                title: 'Oyunlarla Öğren',
                subtitle: 'Test çözmekten sıkıldığında oyunlarla tekrar et: rakiplerinle '
                    'düello yap, kart eşleştir, haritada il fethet. Her oyun bildiklerini '
                    'pekiştirir, XP ve rozet kazandırır.',
                accent: c.violet,
                accent2: c.rose,
                actionLabel: 'Düelloya Başla',
                overline: 'Oyunlar',
                badge: 'POPÜLER',
                illustrationEmoji: '🕹️',
                onAction: () {
                  context.read<SoundService>().click();
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const DuelLobbyScreen()));
                },
              ),
              const SizedBox(height: 22),
              const DsSectionHeader(title: '🎮 Oyunlar'),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: kDsGap,
                crossAxisSpacing: kDsGap,
                childAspectRatio: 0.86,
                children: [
                  ToolCard(
                    icon: '⚔️',
                    title: 'KPSS Düello',
                    desc: 'Rakiplerinle canlı 1v1 düello ya da çok kişilik Royale.',
                    chipLabel: premium ? 'Sınırsız' : 'Günde $kFreeGameDailyLimit maç',
                    palette: const SubjectPalette(Color(0xFFEF4444), Color(0xFF7C2D12)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const DuelLobbyScreen())),
                  ),
                  ToolCard(
                    icon: '🃏',
                    title: 'Kart Eşleştirme Oyunu',
                    desc: 'Eşleşen kartları bul, hafızanı ve bilgini birlikte çalıştır.',
                    chipLabel: hakEtiketi(cgLeft),
                    palette: const SubjectPalette(Color(0xFFF472B6), Color(0xFFC026D3)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => CardGameScreen(subjects: subjects))),
                  ),
                  ToolCard(
                    icon: '🃏',
                    title: 'Kart Oyunu V2',
                    desc: 'Ders/konu seç, açık kartları eşleştir.',
                    chipLabel: hakEtiketi(g2Left),
                    palette: const SubjectPalette(Color(0xFFA78BFA), Color(0xFF7C3AED)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => CardGameV2Screen(subjects: subjects))),
                  ),
                  ToolCard(
                    icon: '🂡',
                    title: 'Solitaire',
                    desc: 'Ders/konu seç, kartları sırayla temizle.',
                    chipLabel: hakEtiketi(solLeft),
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
                    desc: 'Türkiye haritasında illeri, bölgeleri fethet ya da puansız öğren.',
                    chipLabel: hakEtiketi(haritaLeft),
                    palette: const SubjectPalette(Color(0xFF60A5FA), Color(0xFF2563EB)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => MapGameScreen(subjects: subjects))),
                  ),
                  ToolCard(
                    icon: '🤔',
                    title: 'Doğru mu Yanlış mı?',
                    desc: 'Karttaki iddia doğru mu? Sağa/sola kaydır ya da butona bas.',
                    chipLabel: hakEtiketi(dyLeft),
                    palette: const SubjectPalette(Color(0xFF22D3EE), Color(0xFF0E7490)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const DogruYanlisScreen())),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const DsSectionHeader(title: '⚡ Hızlı Modlar'),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: kDsGap,
                crossAxisSpacing: kDsGap,
                childAspectRatio: 0.86,
                children: [
                  ToolCard(
                    icon: '⚡',
                    title: 'Hızlı Karar',
                    desc: 'Her soru için sadece birkaç saniyen var, doğru/yanlış hızlı seç.',
                    chipLabel: hakEtiketi(hkLeft),
                    palette: const SubjectPalette(Color(0xFFFBBF24), Color(0xFFD97706)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => HizliKararScreen(subjects: subjects))),
                  ),
                  ToolCard(
                    icon: '🏃',
                    title: 'Bilgi Maratonu',
                    desc: 'Tüm derslerden sonsuz soru akışı, ilk yanlışta seri biter.',
                    chipLabel: hakEtiketi(bmLeft),
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
                    chipLabel: gununPatronuOynandi ? 'Bugün bitti' : 'Günde 1 hak',
                    palette: const SubjectPalette(Color(0xFFFACC15), Color(0xFF7C3AED)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => GununPatronuScreen(subjects: subjects))),
                  ),
                  ToolCard(
                    icon: '⏱️',
                    title: '60 Saniye Challenge',
                    desc: 'Karışık sorularla 60 saniyede kaç doğru yapabilirsin?',
                    chipLabel: hakEtiketi(h60Left),
                    palette: const SubjectPalette(Color(0xFFF87171), Color(0xFFEA580C)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => Hiz60Screen(subjects: subjects))),
                  ),
                  ToolCard(
                    icon: '✍️',
                    title: 'Yazım Yanlışları',
                    desc: 'Doğru yazımı bul, süre dolmadan seç!',
                    chipLabel: hakEtiketi(yyLeft),
                    palette: const SubjectPalette(Color(0xFF2DD4BF), Color(0xFF0891B2)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const YazimYanlislariScreen())),
                  ),
                  ToolCard(
                    icon: '📅',
                    title: 'Tarihleri Bil',
                    desc: 'Önemli olayların doğru yılını bil.',
                    chipLabel: hakEtiketi(tbLeft),
                    palette: const SubjectPalette(Color(0xFFB45309), Color(0xFF78350F)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const TarihleriBilScreen())),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const DsSectionHeader(title: '🧩 Ek Oyunlar'),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: kDsGap,
                crossAxisSpacing: kDsGap,
                childAspectRatio: 0.86,
                children: [
                  ToolCard(
                    icon: '🔗',
                    title: 'Zincirleme Bilgi',
                    desc: 'Tarihi/coğrafi bilgi zincirlerini adım adım çöz.',
                    chipLabel: premium ? 'Sınırsız' : 'Bugün $zbLeft zincir',
                    palette: const SubjectPalette(Color(0xFF6366F1), Color(0xFF3B82F6)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const ZincirlemeBilgiScreen())),
                  ),
                  ToolCard(
                    icon: '🕵️',
                    title: 'Kimim Ben',
                    desc: 'İpuçlarıyla tarihi kişiyi bil, erken bilirsen daha çok puan al.',
                    chipLabel: hakEtiketi(kbLeft),
                    palette: const SubjectPalette(Color(0xFF8B5CF6), Color(0xFFD946EF)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const KimimBenScreen())),
                  ),
                  ToolCard(
                    icon: '🔤',
                    title: 'Alfabe Oyunu',
                    desc: alfabeRekor != null
                        ? "A'dan Z'ye tarih soruları. Rekor süren: ${alfabeSureMetni(alfabeRekor)}."
                        : "A'dan Z'ye her harf için tarih sorusu. Süreyle yarış, rekor kır.",
                    chipLabel: hakEtiketi(aoLeft),
                    palette: const SubjectPalette(Color(0xFF14B8A6), Color(0xFF0D9488)),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const AlfabeOyunuTanitimScreen())),
                  ),
                ],
              ),
              // NOT: Buradaki "🧰 Diğer Araçlar" bölümü kaldırıldı — içindeki
              // araçlar oyun değil çalışma aracı oldukları için ait oldukları
              // yerlere taşındı:
              //   • Bugün Sınava Girsen Kaç Alırsın? → Profil
              //   • Özel Lig                        → Profil
              //   • Puan Hesaplama                  → Profil
              //   • Akılda Kalıcı Kodlama           → Anasayfa çekmecesi (Drawer)
              //   • Mentörlük Seansları             → Anasayfa çekmecesi (Drawer)
              //   • Çalışma Kronometresi            → Anasayfa çekmecesi (Drawer)
              // Böylece "Oyunlar" sekmesi yalnızca gerçekten oyun olanları
              // barındırıyor.
            ],
          );
        },
      ),
    );
  }
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

  /// Sağ üstteki küçük durum çipi — ör. "Bugün 7 hak" / "Sınırsız".
  /// İsteğe bağlıdır: verilmezse çip hiç çizilmez, böylece bu bileşeni
  /// kullanan mevcut çağrılar aynen çalışmaya devam eder.
  final String? chipLabel;
  final VoidCallback onTap;
  const ToolCard({
    super.key,
    required this.icon,
    required this.title,
    required this.desc,
    this.locked = false,
    this.palette,
    this.chipLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final p = palette ?? _kToolCardFallbackPalette;
    // Açık temada paletin koyu tonu, koyu temada parlak tonu daha okunaklı.
    final vurgu = c.isLight ? p.b : p.a;

    final kart = Container(
      decoration: subjectCardDecoration(palette: p, isLight: c.isLight, radius: kDsRadius),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(kDsRadius),
          onTap: () {
            context.read<SoundService>().click();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Üst şerit: solda büyük emoji (kilitliyse kilit), sağda hak çipi.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(locked ? '🔒' : icon, style: const TextStyle(fontSize: 26)),
                    const SizedBox(width: 6),
                    if (chipLabel != null)
                      Expanded(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: DsChip(label: chipLabel!, color: vurgu),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13.5, color: c.text),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    desc,
                    style: TextStyle(fontSize: 11.5, height: 1.3, color: c.textFaint),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Sağ altta daire içinde ok — "buraya dokunulur" işareti.
                Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.glass2,
                      border: Border.all(color: vurgu.withValues(alpha: 0.45)),
                    ),
                    child: Icon(locked ? Icons.lock_outline : Icons.arrow_forward,
                        size: 15, color: vurgu),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Kilitli kartlar soluk görünür (dokunma davranışı çağıranın sorumluluğunda).
    return locked ? Opacity(opacity: 0.55, child: kart) : kart;
  }
}

/// Premium kilitli özellik ekranı — JS: renderLockedFeature.
class LockedFeatureCard extends StatelessWidget {
  final String title;
  final String desc;

  /// Bir oyun ekranıysa, ücretsiz günlük hak dolunca "Reklam İzle / Hak Kullan"
  /// akışını çalıştırabilmek için: oyunun günlük-hak kimliği + görünen adı +
  /// kullanıcı hak kazanınca çağrılacak "kilidi aç" geri çağrımı. Üçü de
  /// verilirse ekstra-hak butonu gösterilir; verilmezse yalnızca Premium yolu.
  final String? gameId;
  final String? oyunAdi;
  final VoidCallback? onUnlocked;

  const LockedFeatureCard({
    super.key,
    required this.title,
    required this.desc,
    this.gameId,
    this.oyunAdi,
    this.onUnlocked,
  });

  bool get _hakSunulabilir =>
      gameId != null && oyunAdi != null && onUnlocked != null;

  Future<void> _hakKazan(BuildContext context) async {
    context.read<SoundService>().click();
    final storage = context.read<StorageService>();
    final oldu = await hakKazanSheet(
      context,
      baslik: 'Ekstra $oyunAdi hakkı',
      aciklama:
          'Bugünkü ücretsiz hakkın doldu. Reklam izleyerek (+2 hak) ya da '
          'hakkından 1 harcayarak bir kez daha oynayabilirsin.',
      maliyet: 1,
    );
    if (!oldu || !context.mounted) return;
    await storage.addExtraPlays(gameId!, 1);
    onUnlocked!();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    // Premium kullanıcıya bu ekran zaten hiç gösterilmez; yine de hak butonu
    // premium'da anlamsız olacağı için gizli tutulur.
    final premium = context.watch<StorageService>().isPremiumUser();
    final hakGoster = _hakSunulabilir && !premium;
    return Scaffold(
      appBar: AppBar(title: Text('🔒 $title')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DsCard(
              accent: c.gold,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      DsIconBadge(emoji: '🔒', color: c.gold),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900, color: c.text),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(desc, style: TextStyle(color: c.textFaint, height: 1.6, fontSize: 13)),
                  const SizedBox(height: 18),
                  if (hakGoster) ...[
                    DsPillButton(
                      label: 'Reklam İzle / Hak Kullan',
                      color: c.violet,
                      leadingIcon: Icons.slideshow_rounded,
                      onPressed: () => _hakKazan(context),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DsPillButton(
                      label: "Premium'a Geç",
                      color: c.gold,
                      filled: !hakGoster,
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
          ],
        ),
      ),
    );
  }
}
