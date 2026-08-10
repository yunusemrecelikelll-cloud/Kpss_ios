import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show anasayfaKokunde;
import '../models/subject.dart';
import '../services/league_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'wrong_bank_screen.dart';
import 'settings_screen.dart';
import 'tools_hub_screen.dart';

/// Alt navigasyon çubuğu — Anasayfa / Sohbet / Oyunlar / (Premium'da:
/// Yanlışlarım) / Ayarlar. Oyunlar sekmesi hem ücretsiz hem premium
/// kullanıcıda gösterilir. Premium ekranına Anasayfa'daki çekmeceden
/// (Drawer) erişiliyor. Rozetler artık ayrı bir alt sekme DEĞİL — Profil
/// ekranının (bkz. profile_screen.dart AppBar'ındaki 🏆 butonu) içinden
/// erişilir.
///
/// Her sekme kendi iç Navigator'ına sahiptir (nested Navigator deseni) —
/// böylece bu sekmelerden açılan HERHANGİ bir ekran (Premium, Oyunlar, Konu
/// Anlatımı, Profil vb.) alt navigasyon çubuğunun ÜSTÜNDE açılır ve bar
/// görünür kalır. Sadece Soru/Test ekranı (QuizScreen), tam ekran kaplaması
/// gerektiği için kasıtlı olarak KÖK Navigator'a
/// (`Navigator.of(context, rootNavigator: true)`) push edilir — bu yüzden
/// quiz sırasında alt bar görünmez.
class MainShell extends StatefulWidget {
  final List<Subject> subjects;
  const MainShell({super.key, required this.subjects});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  // Tüm olası sekmeler için sabit anahtarlar — premium durumu değişse bile
  // (ör. abonelik satın alındığında ya da geri yüklendiğinde) her sekmenin
  // iç gezinme geçmişi korunur.
  final Map<String, GlobalKey<NavigatorState>> _navKeys = {
    'home': GlobalKey<NavigatorState>(),
    'chat': GlobalKey<NavigatorState>(),
    'games': GlobalKey<NavigatorState>(),
    'wrong': GlobalKey<NavigatorState>(),
    'settings': GlobalKey<NavigatorState>(),
  };

  static const _labels = {
    'home': ('Anasayfa', Icons.home_outlined, Icons.home),
    'chat': ('Sohbet', Icons.chat_bubble_outline, Icons.chat_bubble),
    'games': ('Oyunlar', Icons.sports_esports_outlined, Icons.sports_esports),
    'wrong': ('Yanlışlarım', Icons.close_outlined, Icons.close),
    'settings': ('Ayarlar', Icons.settings_outlined, Icons.settings),
  };

  @override
  void initState() {
    super.initState();
    // Uygulama ana ekranı (bottom nav) her açıldığında BİR KEZ kendi güncel
    // stat/rozet özetini Firestore'a yayınla (bkz. LeagueService.publishMyScore)
    // — ÖNCEDEN bu yalnızca kullanıcı kendi Profil ekranını elle açtığında
    // tetikleniyordu (bkz. profile_screen.dart), bu yüzden hiç Profil'e
    // uğramamış bir kullanıcının 'league_scores/{uid}' dokümanı hiç
    // oluşmuyor, sohbetten "Profili Görüntüle" diyen başka kullanıcılar
    // hiçbir stat/rozet göremiyordu. Burada, kullanıcının GÖRÜLME olasılığı
    // (sohbete girmesi) ile aynı ana ekranda, daha erken ve güvenilir bir
    // noktada tetikleniyor. Sessizce başarısız olur (offline/giriş yok/Firebase
    // yapılandırılmamış) — bu ekranın kendi görünümünü ETKİLEMEZ.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // ignore: unawaited_futures
      LeagueService().publishMyScore(context.read<StorageService>());
    });
    // Açılışta anasayfa kökündeyiz — global hak pilini gizli başlat.
    _hakPiliniTazele();
  }

  // Anasayfa sekmesinin iç Navigator'ındaki push/pop olaylarını dinleyip
  // global hak pilinin görünürlüğünü tazeler (anasayfa KÖKÜNDE gizli, alt
  // ekran açılınca görünür).
  late final NavigatorObserver _anasayfaGozlemcisi =
      _RotaGozlemcisi(_hakPiliniTazele);

  void _hakPiliniTazele() {
    // Frame sonunda: aktif sekme "home" VE o sekmede açık alt ekran yoksa gizle.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Anasayfa her zaman ilk sekmedir (_index == 0); premium'a göre değişen
      // sekme sırasından etkilenmesin diye doğrudan indeksi kontrol ediyoruz.
      final homeKokte = !(_navKeys['home']?.currentState?.canPop() ?? false);
      anasayfaKokunde.value = (_index == 0) && homeKokte;
    });
  }

  Widget _tabNavigator(String id, Widget root) {
    return Navigator(
      key: _navKeys[id],
      observers: id == 'home' ? [_anasayfaGozlemcisi] : const [],
      onGenerateRoute: (settings) => MaterialPageRoute(builder: (_) => root),
    );
  }

  void _onDestinationSelected(int i, List<String> ids) {
    context.read<SoundService>().click();
    if (i == _index) {
      _navKeys[ids[i]]?.currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _index = i);
    }
    _hakPiliniTazele();
  }

  @override
  Widget build(BuildContext context) {
    final premium = context.watch<StorageService>().isPremiumUser();

    final tabWidgets = <String, Widget>{
      'home': HomeScreen(subjects: widget.subjects),
      'chat': const ChatScreen(),
      'games': const ToolsHubScreen(),
      if (premium) 'wrong': const WrongBankScreen(),
      'settings': const SettingsScreen(),
    };
    final ids = tabWidgets.keys.toList();
    if (_index >= ids.length) _index = 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final nav = _navKeys[ids[_index]]?.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (_index != 0) {
          setState(() => _index = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [for (final id in ids) _tabNavigator(id, tabWidgets[id]!)],
        ),
        bottomNavigationBar: _AltMenu(
          ids: ids,
          labels: _labels,
          index: _index,
          onSelect: (i) => _onDestinationSelected(i, ids),
        ),
      ),
    );
  }
}

/// Anasayfa sekmesinin iç Navigator'ında rota değişimlerini (push/pop/replace)
/// dinleyip verilen geri çağrıyı tetikleyen basit gözlemci. Global hak pilinin
/// "anasayfa kökünde miyiz?" durumunu tazelemek için kullanılır.
class _RotaGozlemcisi extends NavigatorObserver {
  final VoidCallback onDegisim;
  _RotaGozlemcisi(this.onDegisim);

  @override
  void didPush(Route route, Route? previousRoute) => onDegisim();
  @override
  void didPop(Route route, Route? previousRoute) => onDegisim();
  @override
  void didRemove(Route route, Route? previousRoute) => onDegisim();
  @override
  void didReplace({Route? newRoute, Route? oldRoute}) => onDegisim();
}

/// Alt navigasyon çubuğu — referans görsele göre (kullanıcı isteği).
///
/// Tasarım: ikon ÜSTTE, etiket ALTTA (dikey). Seçili sekme ALTIN renkli,
/// yuvarlak-kare (squircle) IŞILTILI bir çerçeve içinde; altında altın bir
/// çizgi. Seçili olmayanlar MOR ışıltılı (neon) ikon/yazı. Animasyonlar
/// korunur: çerçeve/ışıltı yumuşak belirir, seçili ikon elasticOut ile zıplar,
/// alt çizgi genişleyip açılır.
class _AltMenu extends StatelessWidget {
  final List<String> ids;
  final Map<String, (String, IconData, IconData)> labels;
  final int index;
  final ValueChanged<int> onSelect;

  const _AltMenu({
    required this.ids,
    required this.labels,
    required this.index,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final n = ids.length;

    return Container(
      decoration: BoxDecoration(
        color: c.headerBg,
        border: Border(top: BorderSide(color: c.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: c.isLight ? 0.06 : 0.35),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 76,
          child: Row(
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: _AltMenuOgesi(
                    label: labels[ids[i]]!.$1,
                    icon: labels[ids[i]]!.$2,
                    selectedIcon: labels[ids[i]]!.$3,
                    secili: i == index,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AltMenuOgesi extends StatelessWidget {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool secili;
  final VoidCallback onTap;

  const _AltMenuOgesi({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.secili,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    // Referans görsel: seçili = ALTIN, diğerleri = MOR (neon ışıltılı).
    final renk = secili ? c.gold : c.violetL;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Squircle çerçeve + ikon ──
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: secili ? c.gold.withValues(alpha: 0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: secili ? c.gold.withValues(alpha: 0.75) : Colors.transparent,
                  width: 1.6,
                ),
                boxShadow: secili
                    ? [
                        BoxShadow(
                          color: c.gold.withValues(alpha: 0.35),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              // İkon: seçilince elasticOut ile hafifçe büyüyüp "zıplar" ve
              // dolgulu (filled) hâline geçer. Renkli gölge (glow) ile referans
              // görseldeki neon/3B parıltı taklit edilir.
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 1.0, end: secili ? 1.14 : 1.0),
                duration: const Duration(milliseconds: 420),
                curve: Curves.elasticOut,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Icon(
                  secili ? selectedIcon : icon,
                  size: 25,
                  color: renk,
                  shadows: [
                    Shadow(color: renk.withValues(alpha: 0.55), blurRadius: 12),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            // ── Etiket ──
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              style: TextStyle(
                fontSize: secili ? 11.5 : 11,
                fontWeight: secili ? FontWeight.w900 : FontWeight.w600,
                color: renk,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 3),
            // ── Seçili altın alt çizgi (genişleyerek açılır) ──
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              height: 3,
              width: secili ? 20 : 0,
              decoration: BoxDecoration(
                color: c.gold,
                borderRadius: BorderRadius.circular(999),
                boxShadow: secili
                    ? [BoxShadow(color: c.gold.withValues(alpha: 0.6), blurRadius: 6)]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
