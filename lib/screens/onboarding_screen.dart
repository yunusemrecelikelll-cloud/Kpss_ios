import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/subject.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';
import '../widgets/resmi_kurum_feragati.dart';
import 'main_shell.dart';

/// İLK KURULUMDA bir kez gösterilen kaydırmalı tanıtım ekranı.
///
/// Kullanıcı isteği: ilk açılışta 3 sayfalık kaydırılabilir tanıtım + son
/// sayfada "Başla" butonu. Sonraki açılışlarda bu ekran HİÇ görünmez (splash
/// yalnızca logo/slogan gösterip otomatik girer) — bunu [StorageService.
/// onboardingGorulduMu] bayrağı sağlar; "Başla" ya da "Geç" ile işaretlenir.
class OnboardingScreen extends StatefulWidget {
  final List<Subject> subjects;
  const OnboardingScreen({super.key, required this.subjects});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Sayfa {
  final String emoji;
  final String baslik;
  final String metin;
  const _Sayfa(this.emoji, this.baslik, this.metin);
}

const List<_Sayfa> _kSayfalar = [
  _Sayfa('📚', 'Sıkılmadan KPSS çalış',
      '16.000+ soru, 69 konu anlatımı ve gerçek KPSS formatında deneme sınavı — hepsi cebinde, internetsiz.'),
  _Sayfa('🎮', 'Oyunlarla tekrar et',
      'KPSS Düello, Türkiye haritası, Doğru mu Yanlış mı ve daha fazlası. Ezber yerine oynayarak öğren.'),
  _Sayfa('📈', 'Planla, ilerle, kazan',
      'Günlük çalışma planı, konu bazlı istatistikler, rozetler ve seviyene göre sorular. Yolun net.'),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _sayfa = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Tanıtımın SON sayfası (kullanıcı isteği): Ayarlardaki güçlü özellikleri
  /// kısaca tanıtır — böylece yeni kullanıcı bunları kaçırmaz.
  Widget _ozellikSayfasi(KpssColors c) {
    const ozellikler = [
      ('⏱️', 'Soru başına süre',
          'Her soru için süreyi kendin belirle ya da otomatik bırak.'),
      ('🔉', 'Adaptasyon sesi',
          'Cevaplarında yönlendiren sesler; istersen kapatabilirsin.'),
      ('➡️', 'Soruyu nasıl geçersin',
          'Cevaplayınca otomatik mi, "Sonraki" ile mi ilerlesin — sen seç.'),
      ('🎨', 'Tema seçimi',
          '9 renkli tema ile uygulamanın görünümünü değiştir.'),
      ('📋', 'KPSS sınavı seçimi',
          'Lisans / Önlisans / Ortaöğretim — sorular sınavına göre gelir.'),
      ('🔄', 'Soruları güncelle',
          'Yeni eklenen soruları tek dokunuşla indir.'),
      // NOT: "Saatli konu/ders bildirimi" maddesi buradan kaldırıldı — bu
      // özellik AYARLAR'da değil ANASAYFA'da olduğu için (kullanıcı isteği),
      // "Ayarlardaki özellikler" listesinde yer alması yanıltıcıydı.
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text('⚙️', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 10),
            Text('Ayarlardaki güçlü özellikler',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, color: c.text)),
            const SizedBox(height: 6),
            Text('Deneyimini kişiselleştirmek için Ayarlar\'a göz at:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: c.textDim)),
            const SizedBox(height: 16),
            for (final (emoji, baslik, aciklama) in ozellikler)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(baslik,
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: c.text)),
                          const SizedBox(height: 1),
                          Text(aciklama,
                              style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: c.textFaint)),
                        ],
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

  /// İlk açılışta bir kez gösterilen resmî kurum feragatı sayfası.
  Widget _feragatSayfasi(KpssColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DsIllustration(emoji: 'ℹ️', glowColor: c.violetL),
            const SizedBox(height: 22),
            Text('Başlamadan önce',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, color: c.text)),
            const SizedBox(height: 16),
            const ResmiKurumFeragati(kompakt: true),
          ],
        ),
      ),
    );
  }

  Future<void> _basla() async {
    context.read<SoundService>().click();
    await context.read<StorageService>().onboardingGoruldu();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MainShell(subjects: widget.subjects)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    // Sayfa düzeni: [3 tanıtım] → [feragat] → [ayarlar özellikleri (SON)].
    // Toplam = _kSayfalar.length + 2. Son sayfa artık özellikler sayfasıdır.
    final sonSayfa = _sayfa == _kSayfalar.length + 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Geç.
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _basla,
                child: Text('Geç', style: TextStyle(color: c.textFaint)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _kSayfalar.length + 2,
                onPageChanged: (i) => setState(() => _sayfa = i),
                itemBuilder: (_, i) {
                  // Resmî kurum feragatı + ÖSYM bağlantısı.
                  if (i == _kSayfalar.length) return _feragatSayfasi(c);
                  // SON sayfa: Ayarlardaki özellikler tanıtımı.
                  if (i == _kSayfalar.length + 1) return _ozellikSayfasi(c);
                  final s = _kSayfalar[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        DsIllustration(emoji: s.emoji, glowColor: c.violetL),
                        const SizedBox(height: 28),
                        Text(s.baslik,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: c.text)),
                        const SizedBox(height: 12),
                        Text(s.metin,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14, height: 1.5, color: c.textDim)),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Sayfa noktaları.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _kSayfalar.length + 2; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _sayfa ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _sayfa ? c.violet : c.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
              child: DsPillButton(
                label: sonSayfa ? 'Başla' : 'Devam',
                color: c.violet,
                trailingIcon:
                    sonSayfa ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                onPressed: () {
                  context.read<SoundService>().click();
                  if (sonSayfa) {
                    _basla();
                  } else {
                    _controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
