import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/account_deletion_service.dart';
import '../services/auth_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../services/remote_question_service.dart';
import '../theme/app_theme.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';
import 'premium_screen.dart';
import 'quiz_screen.dart'
    show
        kAutoSecsPerQ,
        kSureOnayarlariSn,
        kMinTestDakika,
        kMaxTestDakika,
        kVarsayilanSoruCevapModu;
import 'privacy_policy_screen.dart';
import 'splash_screen.dart';

const List<String> _kCharacterOpts = ['🦉', '🦁', '🐯', '🦄', '🐼', '🚀', '🏆', '📚'];

// ── Test süresi ──
// Süre artık test öncesi sorulmuyor; buradaki tercih doğrudan uygulanıyor
// (bkz. quiz_screen.dart → testSuresiHesapla).
/// Kullanıcının elle girebileceği "soru başına saniye" alt/üst sınırı.
/// Üst sınır, 120 soruluk denemede toplam sürenin [kMaxTestDakika] içinde
/// kalmasını garanti eder (toplam süre ayrıca orada da kırpılır).
const int _kMinSnPerQ = 5;
const int _kMaxSnPerQ = 150;

/// Örnek süre metinlerinin hesaplandığı deneme sınavı uzunluğu.
const int _kOrnekSoruSayisi = 120;

// ── Soru cevap modu ──
// Konu testlerinde bir şık işaretlendikten sonraki davranışı belirler.
// Ayar anahtarı: 'soruCevapModu'. Varsayılan (ilk kurulumda) 'herZamanDur' —
// tek kaynak quiz_screen.dart'taki kVarsayilanSoruCevapModu sabitidir.
class _SoruCevapSecenegi {
  final String deger;
  final String baslik;
  final String aciklama;
  const _SoruCevapSecenegi(this.deger, this.baslik, this.aciklama);
}

const List<_SoruCevapSecenegi> _kSoruCevapSecenekleri = [
  _SoruCevapSecenegi(
    'testSonunda',
    'Soru cevapladıktan sonra geç',
    'Soru ve cevap açıklaması test sonunda görünür.',
  ),
  _SoruCevapSecenegi(
    'yanlistaDur',
    'Sadece doğruysa geç',
    'Doğruysa açıklama yapmaz. Yanlışsa açıklamayı ve muhtemelen neden o '
        'şıkkı seçtiğini gösterir.',
  ),
  _SoruCevapSecenegi(
    'herZamanDur',
    'Soruyu geç butonuyla geç',
    'Doğru ve yanlış için açıklama yapar, Sonraki butonuyla geçilir.',
  ),
];

/// 400 → "6 dk 40 sn" gibi kısa Türkçe süre metni.
String _sureMetni(int sn) {
  final dk = sn ~/ 60;
  final kalan = sn % 60;
  if (dk == 0) return '$kalan sn';
  if (kalan == 0) return '$dk dk';
  return '$dk dk $kalan sn';
}

/// JS karşılığı: renderSettings() (src/js/app.js).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// "Soruları Güncelle" o an kontrol/indirme yapıyor mu.
  bool _checkingUpdate = false;

  /// "Hesabımı Sil" akışı.
  ///
  /// İki aşamalı onay: önce ne silineceğini açıkça anlatan bir uyarı, sonra
  /// kullanıcının "SİL" yazarak teyit etmesi. Kazara silme riskini düşürmek
  /// için yazarak teyit tercih edildi — geri alınamaz bir işlem.
  // NOT: Buraya `BuildContext` parametresi ALMIYORUZ. Parametre olarak
  // alınsaydı State'in kendi `context`'ini gölgeler ve `mounted` kontrolü
  // analizör tarafından "ilgisiz" sayılırdı (use_build_context_synchronously).
  Future<void> _hesabiSil(StorageService storage) async {
    // Tüm context bağımlılıklarını await'lerden ÖNCE yakala — async boşluk
    // sonrasında context'e dokunmak güvenli değil (ekran bu sırada kapanmış
    // olabilir).
    context.read<SoundService>().click();
    final auth = context.read<AuthService>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);

    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _DeleteAccountDialog(),
    );
    if (onay != true || !mounted) return;

    // Silme sürerken kapatılamayan bir ilerleme penceresi göster.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
              SizedBox(width: 16),
              Expanded(child: Text('Hesabın siliniyor…')),
            ],
          ),
        ),
      ),
    );

    final servis = AccountDeletionService();
    String? hataMesaji;

    try {
      await servis.deleteAccount(storage);
    } on ReauthRequiredException {
      // Oturum eski: aynı sağlayıcıyla yeniden doğrula, sonra TEK sefer daha
      // dene. Bulut verisi ilk denemede zaten silindi; kalan yalnızca Auth
      // kaydı.
      final sonuc = await auth.reauthenticate();
      if (sonuc.success) {
        try {
          await servis.deleteAccount(storage);
        } catch (e) {
          hataMesaji = e.toString();
        }
      } else {
        hataMesaji = sonuc.errorMessage ?? 'Yeniden giriş yapılamadı.';
      }
    } catch (e) {
      hataMesaji = e.toString();
    }

    navigator.pop(); // ilerleme penceresini kapat

    if (hataMesaji != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(hataMesaji), duration: const Duration(seconds: 5)),
      );
      return;
    }

    // Başarılı: uygulamayı sıfırdan başlat — geride bu kullanıcıya ait hiçbir
    // ekran/durum kalmasın.
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (route) => false,
    );
  }

  // ── Soruları Güncelle ────────────────────────────────────────────────
  // Sorular artık uygulamayla birlikte geliyor (assets/data/*.json), açılışta
  // hiçbir indirme yapılmıyor. Bu bölüm SADECE kullanıcı isterse GitHub'daki
  // sürüm dosyasına bakıp yeni soru olup olmadığını kontrol eder.

  /// Son kontrol tarihinin saklandığı ayar anahtarı (ISO 8601 metin).
  static const String _kSonKontrolKey = 'sonSoruGuncellemeKontrolu';

  static const List<String> _kAyKisa = [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ];

  /// 2026-07-21 → "21 Tem 2026"
  String _tarihMetni(DateTime d) => '${d.day} ${_kAyKisa[d.month - 1]} ${d.year}';

  /// Ayarlardan son kontrol tarihini okur (yoksa null).
  DateTime? _sonKontrol(StorageService storage) {
    final raw = storage.getSettings()[_kSonKontrolKey];
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> _soruGuncelle() async {
    // Tüm context bağımlılıklarını await'lerden ÖNCE yakala.
    final remote = context.read<RemoteQuestionService>();
    final storage = context.read<StorageService>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _checkingUpdate = true);
    final sonuc = await remote.checkAndUpdate();

    // Kontrol tarihi: sonuç ne olursa olsun DEĞİL, sadece sunucuya gerçekten
    // ulaşılabildiyse anlamlıdır — hata durumunda eski tarih korunur.
    if (sonuc.sonuc != UpdateOutcome.hata) {
      await storage.saveSettings({_kSonKontrolKey: DateTime.now().toIso8601String()});
    }

    // Güncelleme uygulandıysa anasayfadaki "Yeni sorular eklendi" banner'ını
    // da temizle — kullanıcı artık en güncel içeriğe sahip.
    if (sonuc.sonuc == UpdateOutcome.guncellendi) {
      final tarih = sonuc.guncellemeTarihi ?? DateTime.now();
      await storage.setLastSeenContentVersionMs(tarih.millisecondsSinceEpoch);
    }

    if (!mounted) return;
    setState(() => _checkingUpdate = false);

    final String mesaj;
    switch (sonuc.sonuc) {
      case UpdateOutcome.guncellendi:
        mesaj = sonuc.yeniSoruSayisi > 0
            ? '${sonuc.yeniSoruSayisi} yeni soru eklendi.'
            : 'Sorular güncellendi.';
      case UpdateOutcome.zatenGuncel:
        mesaj = 'Sorular zaten güncel.';
      case UpdateOutcome.hata:
        mesaj = 'Güncelleme kontrol edilemedi, internetini kontrol et.';
    }
    messenger.showSnackBar(SnackBar(content: Text(mesaj)));
  }

  // ── Test süresi tercihi ──────────────────────────────────────────────

  /// Süre modunu kaydeder (`auto` | `perq` | `off`).
  void _setTimerMode(StorageService storage, String mod, String mesaj) {
    context.read<SoundService>().click();
    storage.saveSettings({'timerMode': mod});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mesaj)));
  }

  /// Soru başına saniyeyi kaydeder.
  void _setSecsPerQ(StorageService storage, int sn) {
    context.read<SoundService>().click();
    storage.saveSettings({'secsPerQ': sn});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Soru başına $sn saniye seçildi.')),
    );
  }

  /// Preset'ler yetmezse kullanıcı kendi "soru başına saniye" değerini yazar.
  Future<void> _ozelSureGir(StorageService storage, int mevcut) async {
    context.read<SoundService>().click();
    final sn = await showDialog<int>(
      context: context,
      builder: (_) => _OzelSureDialog(mevcut: mevcut),
    );
    if (sn == null || !mounted) return;
    storage.saveSettings({'secsPerQ': sn});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Soru başına $sn saniye ayarlandı.')),
    );
  }

  /// Seçili ayarın pratikte ne anlama geldiğini anlatan açıklama metni.
  String _sureAciklamasi(String mod, int secsPerQ) {
    if (mod == 'off') {
      return '♾️ Süresiz: denemede de geri sayım olmaz, istediğin kadar '
          'düşünebilirsin.';
    }
    final soruBasina = mod == 'perq' ? secsPerQ : kAutoSecsPerQ;
    final toplam = _sureMetni(_kOrnekSoruSayisi * soruBasina);
    final yirmi = _sureMetni(20 * soruBasina);
    final bas = mod == 'auto'
        ? '🤖 Otomatik: KPSS oranına göre soru başına $kAutoSecsPerQ sn.'
        : '✏️ Soru başına $soruBasina sn.';
    return '$bas\n'
        '• $_kOrnekSoruSayisi soruluk denemede ≈ $toplam\n'
        '• 20 soruluk denemede ≈ $yirmi';
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final themeProvider = context.watch<ThemeProvider>();
    final c = themeProvider.colors;
    final settings = storage.getSettings();
    final soundOn = settings['soundEnabled'] != false;
    final timerMode = (settings['timerMode'] as String?) ?? 'auto';
    final secsPerQ = (settings['secsPerQ'] as int?) ?? 65;
    final soruCevapModu = (settings['soruCevapModu'] as String?) ?? kVarsayilanSoruCevapModu;
    final premium = storage.isPremiumUser();
    final cloudBackup = storage.getCloudBackupEnabled();
    final adaptationSounds = storage.getAdaptationSoundsEnabled();

    return Scaffold(
      appBar: AppBar(title: const Text('⚙️ Ayarlar')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── GÖRÜNÜM ─────────────────────────────────────────────────
            DsSectionHeader(
                title: premium ? '🎨 Görünüm (9/9 tema açık)' : '🎨 Görünüm (3/9 tema açık)'),
            const SizedBox(height: 8),
            DsCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final entry in kThemes.entries)
                        _ThemeSwatch(
                          colors: entry.value,
                          active: themeProvider.themeId == entry.key,
                          locked: !premium && !kFreeThemeIds.contains(entry.key),
                          onTap: () async {
                            context.read<SoundService>().click();
                            final ok = await themeProvider.setTheme(entry.key);
                            if (!mounted) return;
                            if (!ok) {
                              Navigator.of(context)
                                  .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Tema değiştirildi!')),
                            );
                          },
                        ),
                    ],
                  ),
                  if (!premium) ...[
                    const SizedBox(height: 12),
                    Text(
                      '🔒 6 tema daha Premium\'da açılıyor.',
                      style: TextStyle(fontSize: 12, color: c.textFaint),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: kDsGap),
            // Premium karakter de bir "görünüm" tercihi olduğu için bu grupta.
            DsCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      DsIconBadge(
                          emoji: '🦉', color: c.violetL, size: 42, circle: false, glow: false),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Premium Karakter',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14, color: c.text)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (premium) ...[
                    Text('Profilinde ve üst menüde görünecek karakteri seç.',
                        style: TextStyle(fontSize: 12.5, color: c.textFaint)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final char in _kCharacterOpts)
                          _ChoiceButton(
                            label: char,
                            fontSize: 20,
                            selected: storage.getUserCharacter() == char,
                            onTap: () async {
                              context.read<SoundService>().click();
                              await storage.setUserCharacter(char);
                              if (!mounted) return;
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Karakter güncellendi!')),
                              );
                            },
                          ),
                      ],
                    ),
                  ] else
                    Text(
                      "Premium'a geçerek profilin için özel karakterler açabilirsin.",
                      style: TextStyle(fontSize: 12.5, color: c.textFaint),
                    ),
                ],
              ),
            ),

            // ── SES ─────────────────────────────────────────────────────
            const SizedBox(height: 20),
            const DsSectionHeader(title: '🔊 Ses'),
            const SizedBox(height: 8),
            DsCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: DsIconBadge(
                        icon: Icons.volume_up_rounded,
                        color: c.mint,
                        size: 42,
                        circle: false,
                        glow: false),
                    title: Text('Buton sesleri',
                        style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                    subtitle: Text('Tıklamalarda ses çıkar; son 5 saniye tik-tak sesi gelir',
                        style: TextStyle(fontSize: 12, color: c.textFaint)),
                    value: soundOn,
                    onChanged: (v) => storage.saveSettings({'soundEnabled': v}),
                  ),
                  Divider(height: 1, color: c.border),
                  SwitchListTile(
                    secondary: DsIconBadge(
                        icon: Icons.spatial_audio_off_rounded,
                        color: c.violetL,
                        size: 42,
                        circle: false,
                        glow: false),
                    title: Text('Adaptasyon Sesleri',
                        style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                    subtitle: Text(
                        'Test çözerken gerçekçi kütüphane/sınav salonu ortamı duy — kütüphane uğultusu, kağıt hışırtısı, kalem sesi, öksürük',
                        style: TextStyle(fontSize: 12, color: c.textFaint)),
                    value: adaptationSounds,
                    onChanged: (v) {
                      storage.setAdaptationSoundsEnabled(v);
                      // Kapatılınca o an çalan atmosferi de hemen durdur —
                      // yalnızca test içinde çalmalı, kapatınca susmalı.
                      if (!v) context.read<SoundService>().stopFocusAmbience();
                    },
                  ),
                ],
              ),
            ),

            // ── TEST SÜRESİ ─────────────────────────────────────────────
            const SizedBox(height: 20),
            const DsSectionHeader(title: '⏱️ Deneme Sınavı Süresi'),
            const SizedBox(height: 8),
            DsCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bu ayar 120 soruluk KPSS genel deneme sınavı için geçerlidir. '
                    'Konu testlerinde süre sınırı yoktur — istediğin kadar '
                    'düşünebilirsin. Sınava girerken süre artık sorulmaz.',
                    style: TextStyle(fontSize: 12.5, height: 1.35, color: c.textFaint),
                  ),
                  const SizedBox(height: 12),
                  const Text('Süre hesaplama modu', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _ChoiceButton(
                        label: '🤖 Otomatik',
                        selected: timerMode == 'auto',
                        onTap: () => _setTimerMode(storage, 'auto', 'Otomatik süre modu seçildi.'),
                      ),
                      _ChoiceButton(
                        label: '✏️ Soru başına saniye',
                        selected: timerMode == 'perq',
                        onTap: () => _setTimerMode(storage, 'perq', 'Soru başına süre modu seçildi.'),
                      ),
                      _ChoiceButton(
                        label: '♾️ Süresiz',
                        selected: timerMode == 'off',
                        onTap: () => _setTimerMode(storage, 'off', 'Süresiz mod seçildi.'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // "Soru başına saniye" bölümü — sadece o mod seçiliyken aktif.
                  Opacity(
                    opacity: timerMode == 'perq' ? 1 : 0.4,
                    child: IgnorePointer(
                      ignoring: timerMode != 'perq',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Her soru için süre:',
                              style: TextStyle(fontSize: 12.5, color: c.textFaint)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final n in kSureOnayarlariSn)
                                _ChoiceButton(
                                  label: '$n sn',
                                  selected: secsPerQ == n,
                                  onTap: () => _setSecsPerQ(storage, n),
                                ),
                              _ChoiceButton(
                                label: kSureOnayarlariSn.contains(secsPerQ)
                                    ? '⌨️ Kendim gireyim'
                                    : '⌨️ $secsPerQ sn',
                                selected: !kSureOnayarlariSn.contains(secsPerQ),
                                onTap: () => _ozelSureGir(storage, secsPerQ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Seçilen ayarın pratikte ne anlama geldiğini açıkla.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.violetL.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: Text(
                      _sureAciklamasi(timerMode, secsPerQ),
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textDim),
                    ),
                  ),
                ],
              ),
            ),

            // ── SORU CEVAP ──────────────────────────────────────────────
            const SizedBox(height: 20),
            const DsSectionHeader(title: '❓ Soru Cevap'),
            const SizedBox(height: 8),
            DsCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Konu testlerinde bir şıkkı işaretledikten sonra ne olsun?',
                    style: TextStyle(fontSize: 12.5, height: 1.35, color: c.textFaint),
                  ),
                  const SizedBox(height: 12),
                  for (final secenek in _kSoruCevapSecenekleri) ...[
                    _RadioSecenek(
                      baslik: secenek.baslik,
                      aciklama: secenek.aciklama,
                      selected: soruCevapModu == secenek.deger,
                      onTap: () {
                        context.read<SoundService>().click();
                        storage.saveSettings({'soruCevapModu': secenek.deger});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${secenek.baslik} seçildi.')),
                        );
                      },
                    ),
                    if (secenek != _kSoruCevapSecenekleri.last)
                      const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Not: Deneme / tam sınav modunda şıkkı işaretleyince her zaman '
                    'sonraki soruya geçilir; açıklamalar sınav sonunda görünür.',
                    style: TextStyle(fontSize: 11.5, height: 1.35, color: c.textFaint),
                  ),
                ],
              ),
            ),

            // ── HESAP ───────────────────────────────────────────────────
            const SizedBox(height: 20),
            const DsSectionHeader(title: '👤 Hesap'),
            const SizedBox(height: 8),
            DsCard(
              accent: premium ? c.gold : null,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  DsIconBadge(
                      emoji: '💎', color: c.gold, size: 42, circle: false, glow: false),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text('Planın:',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 14, color: c.text)),
                            const SizedBox(width: 8),
                            DsChip(
                              label: premium ? 'PREMIUM' : 'ÜCRETSİZ',
                              color: premium ? c.gold : c.textDim,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Premium paketinde detaylı grafikler, özel testler ve VIP ayrıcalıklar yer alır.',
                          style: TextStyle(fontSize: 12, height: 1.35, color: c.textFaint),
                        ),
                        const SizedBox(height: 12),
                        DsPillButton(
                          label: 'Ayrıntıları Gör',
                          color: c.gold,
                          trailingIcon: Icons.arrow_forward,
                          onPressed: () {
                            context.read<SoundService>().click();
                            Navigator.of(context)
                                .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: kDsGap),
            DsCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  // NOT: Buradaki "Hatırlatma bildirimleri" ve "Güncelleme
                  // bildirimleri" anahtarları KALDIRILDI. Sebebi: projede
                  // hiçbir bildirim paketi yok (flutter_local_notifications /
                  // firebase_messaging kurulu değil) ve kaydedilen tercihler
                  // ('reminders' / 'updates') kod tabanında hiçbir yerden
                  // okunmuyordu — yani kullanıcı "günlük hatırlatıcı al" diyor,
                  // hiçbir bildirim asla gelmiyordu. Çalışmayan görünür özellik
                  // App Store Guideline 2.1 reddi sebebidir.
                  // Gerçek bildirim desteği eklendiğinde buraya geri konabilir.
                  SwitchListTile(
                    secondary: DsIconBadge(
                        icon: Icons.cloud_upload_outlined,
                        color: c.mint,
                        size: 42,
                        circle: false,
                        glow: false),
                    title: Text('Bulut yedekleme',
                        style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                    subtitle: Text(
                        'Açıkken test sonuçların, rozetlerin ve çalışma sürelerin '
                        'hesabına yedeklenir; yeni cihazda giriş yapınca geri gelir. '
                        'Kapalıyken hiçbir veri yüklenmez.',
                        style: TextStyle(fontSize: 12, color: c.textFaint)),
                    value: cloudBackup,
                    onChanged: (v) {
                      // Bu anahtar GERÇEKTEN yedeklemeyi denetler:
                      // CloudSyncService.syncUp kapalıyken hiçbir şey yüklemez.
                      // (Eskiden bu kontrol yoktu ve ayar kapalı olsa bile veri
                      // buluta gidiyordu.)
                      storage.setCloudBackupEnabled(v);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(v
                              ? 'Bulut yedekleme açıldı — ilerlemen bundan sonra hesabına yedeklenecek.'
                              : 'Bulut yedekleme kapatıldı — yeni veri yüklenmeyecek.'),
                        ),
                      );
                    },
                  ),
                  Divider(height: 1, color: c.border),
                  // App Store İnceleme Kuralı 5.1.1(v): hesap oluşturmayı
                  // destekleyen uygulamalar hesabın UYGULAMA İÇİNDEN
                  // silinmesini de sunmak zorundadır.
                  ListTile(
                    leading: DsIconBadge(
                        icon: Icons.person_remove_outlined,
                        color: c.danger,
                        size: 42,
                        circle: false,
                        glow: false),
                    title: Text('Hesabımı Sil',
                        style: TextStyle(fontWeight: FontWeight.w700, color: c.danger)),
                    subtitle: Text(
                        'Hesabını ve tüm verilerini kalıcı olarak siler. Geri alınamaz.',
                        style: TextStyle(fontSize: 12, color: c.textFaint)),
                    trailing: Icon(Icons.chevron_right, size: 18, color: c.textFaint),
                    onTap: () => _hesabiSil(storage),
                  ),
                ],
              ),
            ),

            // ── SORULAR ─────────────────────────────────────────────────
            // Sorular uygulamanın içinde gelir; burada sadece "yeni soru var
            // mı" kontrolü yapılır (bkz. RemoteQuestionService.checkAndUpdate).
            const SizedBox(height: 20),
            const DsSectionHeader(title: '📚 Sorular'),
            const SizedBox(height: 8),
            DsCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DsIconBadge(
                          icon: Icons.refresh_rounded,
                          color: c.violetL,
                          size: 42,
                          circle: false,
                          glow: false),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Soruları Güncelle',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 14, color: c.text)),
                            const SizedBox(height: 2),
                            Builder(builder: (_) {
                              final son = _sonKontrol(storage);
                              return Text(
                                son == null
                                    ? 'Henüz kontrol edilmedi'
                                    : 'Son kontrol: ${_tarihMetni(son)}',
                                style: TextStyle(fontSize: 11.5, color: c.textFaint),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sorular uygulamayla birlikte geliyor, internet olmadan da çalışır. '
                    'Zaman zaman yeni sorular ekliyoruz — kontrol etmek için dokun.',
                    style: TextStyle(fontSize: 12, height: 1.35, color: c.textFaint),
                  ),
                  const SizedBox(height: 12),
                  if (_checkingUpdate)
                    Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: c.violetL),
                        ),
                        const SizedBox(width: 10),
                        Text('Kontrol ediliyor…',
                            style: TextStyle(fontSize: 12, color: c.textFaint)),
                      ],
                    )
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DsPillButton(
                        label: 'Soruları Güncelle',
                        color: c.violetL,
                        leadingIcon: Icons.refresh,
                        onPressed: () {
                          context.read<SoundService>().click();
                          _soruGuncelle();
                        },
                      ),
                    ),
                ],
              ),
            ),

            // ── HAKKINDA ────────────────────────────────────────────────
            const SizedBox(height: 20),
            const DsSectionHeader(title: 'ℹ️ Hakkında'),
            const SizedBox(height: 8),
            DsListRow(
              emoji: '🔒',
              accent: c.mint,
              title: 'Gizlilik Politikası',
              status: 'Verilerinin nasıl saklandığını oku.',
              onTap: () {
                context.read<SoundService>().click();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  final KpssColors colors;
  final bool active;
  final bool locked;
  final VoidCallback onTap;
  const _ThemeSwatch({
    required this.colors,
    required this.active,
    required this.onTap,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    // Her tema kendi renkleriyle önizlenir: zemin degradesi temanın bg/bg2'si,
    // altındaki üç nokta ise o temanın vurgu renkleri (mor / gül / altın).
    final onizlemeRenkleri = [colors.violet, colors.rose, colors.gold, colors.mint];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kDsRadiusSm),
      child: Container(
        width: 108,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kDsRadiusSm),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.bg, colors.bg2],
          ),
          border: Border.all(
            color: active ? colors.violetL : colors.border,
            width: active ? 2.5 : 1,
          ),
          boxShadow: active
              ? [BoxShadow(color: colors.violet.withValues(alpha: 0.35), blurRadius: 14)]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(colors.icon,
                    style: TextStyle(fontSize: 18, color: locked ? colors.textFaint : null)),
                const Spacer(),
                if (locked)
                  Icon(Icons.lock, size: 14, color: colors.textFaint)
                else if (active)
                  Icon(Icons.check_circle, size: 15, color: colors.violetL),
              ],
            ),
            const SizedBox(height: 10),
            // Temanın renk kimliğini gösteren küçük şerit.
            Row(
              children: [
                for (final renk in onizlemeRenkleri)
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: renk.withValues(alpha: locked ? 0.35 : 1),
                      border: Border.all(color: colors.border),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              colors.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                color: locked ? colors.textFaint : colors.text,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double? fontSize;
  const _ChoiceButton({required this.label, required this.selected, required this.onTap, this.fontSize});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Bazı temalarda (ör. Kraliyet Altını) `primary` parlak/açık bir renk
    // olabiliyor; sabit beyaz metin böyle durumlarda okunaksız kalıyordu.
    // Arka planın parlaklığına göre kontrast rengi hesaplanır.
    final onPrimary = ThemeData.estimateBrightnessForColor(scheme.primary) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return selected
        ? ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(backgroundColor: scheme.primary, foregroundColor: onPrimary),
            child: Text(label, style: TextStyle(fontSize: fontSize)),
          )
        : OutlinedButton(
            onPressed: onTap,
            child: Text(label, style: TextStyle(fontSize: fontSize)),
          );
  }
}

/// Başlık + altında soluk açıklama içeren, seçili durumu belirgin radyo satırı.
/// Uzun açıklamalar satır satır sarar; taşma olmaz.
class _RadioSecenek extends StatelessWidget {
  final String baslik;
  final String aciklama;
  final bool selected;
  final VoidCallback onTap;

  const _RadioSecenek({
    required this.baslik,
    required this.aciklama,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final vurgu = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? vurgu.withValues(alpha: 0.12) : null,
          border: Border.all(
            color: selected ? vurgu : c.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? vurgu : c.textFaint,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    baslik,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '($aciklama)',
                    style: TextStyle(fontSize: 11.5, height: 1.35, color: c.textFaint),
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

/// Kullanıcının kendi "soru başına saniye" değerini yazdığı küçük pencere.
///
/// Preset'ler ([kSureOnayarlariSn]) çoğu kullanıcıya yeter; daha uzun/kısa
/// süre isteyenler buradan [_kMinSnPerQ]–[_kMaxSnPerQ] aralığında değer girer.
class _OzelSureDialog extends StatefulWidget {
  final int mevcut;
  const _OzelSureDialog({required this.mevcut});

  @override
  State<_OzelSureDialog> createState() => _OzelSureDialogState();
}

class _OzelSureDialogState extends State<_OzelSureDialog> {
  late final TextEditingController _ctrl;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.mevcut}');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Girilen değeri doğrular; geçersizse `null` döner ve hatayı gösterir.
  int? _dogrula() {
    final ham = _ctrl.text.trim();
    if (ham.isEmpty) {
      setState(() => _hata = 'Lütfen bir süre gir.');
      return null;
    }
    final sn = int.tryParse(ham);
    if (sn == null) {
      setState(() => _hata = 'Sadece rakam gir.');
      return null;
    }
    if (sn < _kMinSnPerQ) {
      setState(() => _hata = 'En az $_kMinSnPerQ saniye olmalı.');
      return null;
    }
    if (sn > _kMaxSnPerQ) {
      setState(() => _hata = 'En fazla $_kMaxSnPerQ saniye girebilirsin.');
      return null;
    }
    return sn;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final sn = int.tryParse(_ctrl.text.trim());
    return AlertDialog(
      title: const Text('⌨️ Soru başına süre'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Her soru için kaç saniye ayrılsın? ($_kMinSnPerQ–$_kMaxSnPerQ sn)',
              style: TextStyle(fontSize: 12.5, color: c.textDim),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Soru başına süre',
                border: const OutlineInputBorder(),
                errorText: _hata,
                suffixText: 'sn',
              ),
              onChanged: (_) => setState(() => _hata = null),
            ),
            if (sn != null && sn >= _kMinSnPerQ && sn <= _kMaxSnPerQ) ...[
              const SizedBox(height: 10),
              Text(
                '$_kOrnekSoruSayisi soruluk denemede ≈ ${_sureMetni(_kOrnekSoruSayisi * sn)}\n'
                'Toplam süre $kMinTestDakika–$kMaxTestDakika dk aralığında tutulur.',
                style: TextStyle(fontSize: 12, height: 1.35, color: c.textFaint),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          onPressed: () {
            final d = _dogrula();
            if (d == null) return;
            Navigator.pop(context, d);
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

/// "Hesabımı Sil" onay penceresi.
///
/// Geri alınamaz bir işlem olduğu için tek dokunuşluk bir "Evet" yeterli
/// değil: kullanıcı ne kaybedeceğini okuduktan sonra kutuya "SİL" yazmak
/// zorunda. Yanlışlıkla silmeyi ciddi şekilde zorlaştırır.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();
  bool _onaylandi = false;

  static const String _kOnayKelimesi = 'SİL';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final yeni = _controller.text.trim().toUpperCase() == _kOnayKelimesi;
      if (yeni != _onaylandi) setState(() => _onaylandi = yeni);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: c.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Hesabını sil',
                style: TextStyle(fontWeight: FontWeight.w900, color: c.danger)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bu işlem GERİ ALINAMAZ. Silinecekler:',
              style: TextStyle(fontWeight: FontWeight.w800, color: c.text),
            ),
            const SizedBox(height: 10),
            _madde(c, 'Tüm test sonuçların, istatistiklerin ve yanlış bankan'),
            _madde(c, 'Rozetlerin, XP\'in ve lig sıralaman'),
            _madde(c, 'Sohbet mesajların ve özel konuşmaların'),
            _madde(c, 'Bulut yedeğin ve giriş hesabın'),
            const SizedBox(height: 12),
            Text(
              'Satın aldığın bir abonelik varsa App Store üzerinden ayrıca '
              'iptal etmen gerekir — hesap silmek aboneliği durdurmaz.',
              style: TextStyle(fontSize: 12, color: c.textFaint, height: 1.4),
            ),
            const SizedBox(height: 16),
            Text('Onaylamak için "$_kOnayKelimesi" yaz:',
                style: TextStyle(fontSize: 12.5, color: c.textDim)),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: _kOnayKelimesi,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: c.danger),
          onPressed: _onaylandi ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Hesabımı Sil'),
        ),
      ],
    );
  }

  Widget _madde(KpssColors c, String metin) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•  ', style: TextStyle(color: c.danger)),
            Expanded(
              child: Text(metin,
                  style: TextStyle(fontSize: 12.5, color: c.textDim, height: 1.35)),
            ),
          ],
        ),
      );
}
