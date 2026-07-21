import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  }

  Widget _tabNavigator(String id, Widget root) {
    return Navigator(
      key: _navKeys[id],
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

/// Alt navigasyon çubuğu — Material `NavigationBar` yerine elle çizilmiş
/// sürüm.
///
/// Neden özel: `NavigationBar`, seçili sekmenin ikonunun arkasına kendi
/// "indicator" hapını koyar, ikon boyutunu ve seçili rengi tema üzerinden
/// dolaylı belirler. İstenen davranış ise net:
///   • ikonlar SABİT dursun (seçilince yer değiştirmesin/zıplamasın)
///   • ikonlar biraz daha BÜYÜK olsun
///   • seçili sekme ALTIN renkte olsun
/// Bunları elle çizmek, tema hilelerine boğulmaktan daha okunur.
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
          height: 68,
          child: Row(
            children: [
              for (var i = 0; i < ids.length; i++)
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
    // Seçili sekme altın; seçili olmayanlar soluk. Altın her iki temada da
    // KpssColors.gold üzerinden geldiği için açık temada da okunur kalıyor.
    final renk = secili ? c.gold : c.textFaint;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // İkon boyutu seçili/seçili değil fark etmeksizin AYNI (28) —
            // böylece sekmeler arası geçişte ikonlar yerinde sabit kalıyor.
            Icon(secili ? selectedIcon : icon, size: 28, color: renk),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: secili ? FontWeight.w800 : FontWeight.w600,
                color: renk,
              ),
            ),
            // Seçili sekmenin altındaki ince altın çizgi. Yüksekliği her
            // durumda 3 px yer kaplar (seçili değilken şeffaf) ki metin
            // aşağı yukarı oynamasın.
            const SizedBox(height: 3),
            Container(
              height: 3,
              width: 22,
              decoration: BoxDecoration(
                color: secili ? c.gold : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
