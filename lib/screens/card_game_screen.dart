import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subject.dart';
import '../games/card_game_engine.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';
import 'tools_hub_screen.dart';

/// JS: FREE_CARDGAME_DAILY
const int kFreeCardGameDaily = 10;

/// Kart Eşleştirme Oyunu (v1) — JS: renderCardGame / renderCardGameBoard.
/// Kapalı kartlar, hafıza oyunu — tüm derslerin karışık kart havuzundan oynanır.
class CardGameScreen extends StatefulWidget {
  final List<Subject> subjects;
  const CardGameScreen({super.key, required this.subjects});

  @override
  State<CardGameScreen> createState() => _CardGameScreenState();
}

class _CardGameScreenState extends State<CardGameScreen> {
  final _engine = CardGameEngine();
  bool _started = false;
  bool _locked = false;

  /// Yanlış eşleşmede KIRMIZI gösterilecek iki kartın indisleri; ~600 ms sonra
  /// boşaltılır ve kartlar eski rengine (animasyonlu) döner.
  Set<int> _yanlisKartlar = {};

  /// Yanlış gösterim süresi — kart kapanma gecikmesiyle aynı tutulur.
  static const Duration _yanlisSuresi = Duration(milliseconds: 600);

  // Toplam oynama süresi takibi: bu ekran ekranda kaldığı sürece (ilk başarılı
  // başlangıçtan dispose'a kadar, "Yeni Oyun" ile yeniden başlatmalar dahil)
  // TEK bir oturum sayılır; erken çıkışta da (dispose her zaman çağrılır) kısmi
  // süre kaydedilir.
  DateTime? _sessionStart;
  late final StorageService _storage;

  @override
  void initState() {
    super.initState();
    _storage = context.read<StorageService>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _flushPlayTime();
    super.dispose();
  }

  void _flushPlayTime() {
    final start = _sessionStart;
    if (start == null) return;
    _sessionStart = null;
    _storage.addGameTimeSpent(kKartOyunuGameId, DateTime.now().difference(start));
  }

  Future<void> _boot() async {
    final storage = context.read<StorageService>();
    final premium = storage.isPremiumUser();
    if (!premium) {
      final cg = storage.getCardGameState();
      if ((cg['plays'] as int) >= kFreeCardGameDaily) {
        if (!mounted) return;
        setState(() => _locked = true);
        return;
      }
      await storage.useCardGamePlay();
    }
    _engine.start(widget.subjects, pairCount: 6);
    if (!mounted) return;
    setState(() {
      _started = true;
      _locked = false;
    });
    _sessionStart ??= DateTime.now();
  }

  void _newGame() {
    setState(() {
      _started = false;
      _locked = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  void _onFlip(int i) {
    context.read<SoundService>().click();
    final res = _engine.flip(i);
    if (res.status == 'ignored') return;
    setState(() {});
    if (res.status == 'pending-nomatch') {
      // Yanlış eşleşme: iki kart kısa süre KIRMIZI yanar, sonra eski rengine döner.
      setState(() => _yanlisKartlar = _engine.flipped.toSet());
      Future.delayed(_yanlisSuresi, () {
        if (!mounted) return;
        _engine.clearPending();
        setState(() => _yanlisKartlar = {});
      });
    }
    if (_engine.isComplete) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🎉 Tebrikler, tüm kartları eşleştirdin!')),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return const LockedFeatureCard(
        title: 'Kart Eşleştirme Oyunu',
        desc: "Bugünkü $kFreeCardGameDaily ücretsiz hakkını kullandın. Yarın tekrar oynayabilir ya da Premium'a geçip "
            'sınırsız oynayabilirsin.',
      );
    }
    if (!_started) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final storage = context.watch<StorageService>();
    final colors = context.watch<ThemeProvider>().colors;
    final premium = storage.isPremiumUser();
    final remaining =
        (kFreeCardGameDaily - (storage.getCardGameState()['plays'] as int)).clamp(0, kFreeCardGameDaily);

    if (_engine.cards.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('🃏 Kart Eşleştirme Oyunu')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('🃏  Kart havuzu için önce ders içeriklerinin yüklenmesini bekle.',
                textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final totalSeconds = storage.getGameTimeSpent(kKartOyunuGameId);
    return Scaffold(
      appBar: AppBar(
        title: const Text('🃏 Kart Eşleştirme Oyunu'),
        actions: const [
          HowToPlayButton(
            title: '🃏 Nasıl Oynanır?',
            body: 'Kapalı kartlardan ikisini açarak aynı terim-tanım çiftini bulmaya '
                'çalış. Eşleşirse kartlar açık kalır, eşleşmezse kısa süre sonra tekrar '
                'kapanır. Tüm çiftleri en az hamlede bulmaya çalış; istersen "🔄 Yeni '
                'Oyun" ile istediğin zaman baştan başlayabilirsin.',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Terimi tanımıyla eşleştir. Hamle: ${_engine.moves}'
              '${premium ? '' : ' • Kalan günlük hakkın: $remaining'}',
              style: TextStyle(fontSize: 13, color: colors.textFaint),
            ),
            const SizedBox(height: 4),
            Text(
              'Toplam: ${formatPlayDuration(totalSeconds)} oynadın',
              style: TextStyle(fontSize: 11.5, color: colors.textFaint),
            ),
            const SizedBox(height: 12),
            // Kartlar ekrana TAM SIĞAR: kalan yükseklik LayoutBuilder ile ölçülüp
            // hücre oranı ve yazı boyutu ona göre hesaplanır, scroll kapalıdır.
            Expanded(
              child: LayoutBuilder(
                builder: (context, kisit) {
                  const sutun = 3;
                  const bosluk = 8.0;
                  final satir = (_engine.cards.length / sutun).ceil();
                  final hucreGenislik = (kisit.maxWidth - bosluk * (sutun - 1)) / sutun;
                  final hucreYukseklik =
                      (kisit.maxHeight - bosluk * (satir - 1)) / (satir == 0 ? 1 : satir);
                  final oran = hucreYukseklik <= 0 ? 0.85 : hucreGenislik / hucreYukseklik;
                  final yaziBoyu = (hucreYukseklik * 0.15).clamp(9.0, 14.0);
                  final soruBoyu = (hucreYukseklik * 0.32).clamp(16.0, 30.0);

                  return GridView.builder(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: sutun,
                      mainAxisSpacing: bosluk,
                      crossAxisSpacing: bosluk,
                      childAspectRatio: oran <= 0 ? 0.85 : oran,
                    ),
                    itemCount: _engine.cards.length,
                    itemBuilder: (context, i) {
                      final c = _engine.cards[i];
                      final acik = _engine.flipped.contains(i) || c.matched;
                      final yanlis = _yanlisKartlar.contains(i);
                      // Her doğru çift paletten KENDİ rengini alır (çift1 yeşil,
                      // çift2 mor, çift3 turuncu ...), yanlışta kırmızı yanar.
                      final vurgu = yanlis
                          ? kYanlisRengi
                          : c.matched
                              ? ciftRengi(c.pairId)
                              : null;

                      return InkWell(
                        onTap: () => _onFlip(i),
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOut,
                          decoration: BoxDecoration(
                            color: vurgu != null
                                ? vurgu.withValues(alpha: 0.22)
                                : acik
                                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                                    : Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: vurgu ?? colors.border,
                              width: vurgu != null ? 2 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(6),
                          // Metin önce hücre genişliğinde satırlara bölünür,
                          // taşarsa FittedBox küçülterek kartın içinde tutar.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: (hucreGenislik - 12).clamp(24.0, 400.0),
                              child: Text(
                                acik ? c.text : '❓',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: acik ? yaziBoyu : soruBoyu,
                                  fontWeight: FontWeight.w600,
                                  color: colors.text,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                context.read<SoundService>().click();
                _newGame();
              },
              child: const Text('🔄 Yeni Oyun'),
            ),
          ],
        ),
      ),
    );
  }
}
