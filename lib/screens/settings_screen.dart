import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/account_deletion_service.dart';
import '../services/auth_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../services/data_service.dart';
import '../services/remote_question_service.dart';
import '../theme/app_theme.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';
import 'premium_screen.dart';
import 'privacy_policy_screen.dart';
import 'splash_screen.dart';

const List<String> _kCharacterOpts = ['🦉', '🦁', '🐯', '🦄', '🐼', '🚀', '🏆', '📚'];
const List<int> _kSecsOpts = [30, 45, 60, 90, 120];

/// JS karşılığı: renderSettings() (src/js/app.js).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _downloading = false;
  int _downloadDone = 0;
  int _downloadTotal = 0;
  int? _cachedCount;

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

  List<String> _allTopicIds(BuildContext context) {
    final subjects = context.read<DataService>().cachedSubjects;
    return [for (final s in subjects) for (final t in s.konular) t.id];
  }

  Future<void> _refreshCachedCount() async {
    final ids = _allTopicIds(context);
    final remote = context.read<RemoteQuestionService>();
    final n = await remote.countCached(ids);
    if (!mounted) return;
    setState(() => _cachedCount = n);
  }

  Future<void> _downloadAll() async {
    final ids = _allTopicIds(context);
    final remote = context.read<RemoteQuestionService>();
    setState(() {
      _downloading = true;
      _downloadDone = 0;
      _downloadTotal = ids.length;
    });
    final succeeded = await remote.downloadAll(ids, onProgress: (done, total) {
      if (!mounted) return;
      setState(() {
        _downloadDone = done;
        _downloadTotal = total;
      });
    });
    if (!mounted) return;
    final n = await remote.countCached(ids);
    if (!mounted) return;
    // Başarılıysa "Yeni sorular eklendi" bildirimini de temizle — kullanıcı
    // artık en güncel içeriği indirmiş oldu.
    if (succeeded >= ids.length) {
      final serverUpdatedAt = await remote.getServerContentUpdatedAt();
      if (serverUpdatedAt != null) {
        await context.read<StorageService>().setLastSeenContentVersionMs(serverUpdatedAt.millisecondsSinceEpoch);
      }
    }
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _cachedCount = n;
    });
    // DÜRÜST sonuç: her konu gerçekten indirilebildiyse başarı mesajı,
    // aksi halde (internet yok / sunucuya erişilemedi) bunu AÇIKÇA söyle —
    // "tamamlandı" diye yanlış bir izlenim verme.
    final allOk = succeeded >= ids.length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(allOk
          ? 'Tüm sorular indirildi — artık internetsiz de çalışır.'
          : '$succeeded / ${ids.length} konu indirilebildi. İnternet bağlantını kontrol edip tekrar dene.'),
    ));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCachedCount());
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
    final notif = storage.getNotificationSettings();
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
            const DsSectionHeader(title: '⏱️ Test Süresi'),
            const SizedBox(height: 8),
            DsCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Süre hesaplama modu', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _ChoiceButton(
                          label: '🤖 Otomatik (KPSS oranı — 65sn/soru)',
                          selected: timerMode == 'auto',
                          onTap: () {
                            context.read<SoundService>().click();
                            storage.saveSettings({'timerMode': 'auto'});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Otomatik süre modu seçildi.')),
                            );
                          },
                        ),
                        _ChoiceButton(
                          label: '✏️ Soru başına süre — Sen belirle',
                          selected: timerMode == 'perq',
                          onTap: () {
                            context.read<SoundService>().click();
                            storage.saveSettings({'timerMode': 'perq'});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Soru başına süre modu seçildi.')),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Opacity(
                      opacity: timerMode == 'perq' ? 1 : 0.4,
                      child: IgnorePointer(
                        ignoring: timerMode != 'perq',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Her soru için süre:', style: TextStyle(fontSize: 12.5, color: c.textFaint)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final n in _kSecsOpts)
                                  _ChoiceButton(
                                    label: '${n}s',
                                    selected: secsPerQ == n,
                                    onTap: () {
                                      context.read<SoundService>().click();
                                      storage.saveSettings({'secsPerQ': n});
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Soru başına $n saniye seçildi.')),
                                      );
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Örnek: 10 soru × ${secsPerQ}sn = ${(10 * secsPerQ / 60).round()} dakika',
                              style: TextStyle(fontSize: 12, color: c.textFaint),
                            ),
                          ],
                        ),
                      ),
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
                  SwitchListTile(
                    secondary: DsIconBadge(
                        icon: Icons.notifications_active_outlined,
                        color: c.roseL,
                        size: 42,
                        circle: false,
                        glow: false),
                    title: Text('Hatırlatma bildirimleri',
                        style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                    subtitle: Text('Günlük soru hatırlatıcısı ve KPSS güncellemeleri al.',
                        style: TextStyle(fontSize: 12, color: c.textFaint)),
                    value: notif['reminders'] == true,
                    onChanged: (v) => storage.saveNotificationSettings({'reminders': v}),
                  ),
                  Divider(height: 1, color: c.border),
                  SwitchListTile(
                    secondary: DsIconBadge(
                        icon: Icons.campaign_outlined,
                        color: c.violetL,
                        size: 42,
                        circle: false,
                        glow: false),
                    title: Text('Güncelleme bildirimleri',
                        style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                    subtitle: Text('Yeni içerik ve duyuruları uygulama içinde gör.',
                        style: TextStyle(fontSize: 12, color: c.textFaint)),
                    value: notif['updates'] == true,
                    onChanged: (v) => storage.saveNotificationSettings({'updates': v}),
                  ),
                  Divider(height: 1, color: c.border),
                  SwitchListTile(
                    secondary: DsIconBadge(
                        icon: Icons.cloud_upload_outlined,
                        color: c.mint,
                        size: 42,
                        circle: false,
                        glow: false),
                    title: Text('Bulut yedekleme',
                        style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                    subtitle: Text('Profilini ve ilerlemeni çevrimiçi yedeklemeye hazırlık.',
                        style: TextStyle(fontSize: 12, color: c.textFaint)),
                    value: cloudBackup,
                    onChanged: (v) {
                      // TODO: Gerçek bulut senkronizasyonu (Firestore) henüz yok.
                      // Bu switch şimdilik sadece tercihi yerelde saklıyor; asıl
                      // yedekleme mantığı PORT_NOTES.md'deki Firebase entegrasyonu
                      // tamamlanınca buraya bağlanacak.
                      storage.setCloudBackupEnabled(v);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(v ? 'Bulut yedekleme hazırlandı.' : 'Bulut yedekleme kapatıldı.')),
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

            // ── VERİ VE İNDİRME ─────────────────────────────────────────
            const SizedBox(height: 20),
            const DsSectionHeader(title: '📥 Veri ve İndirme'),
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
                          icon: Icons.download_rounded,
                          color: c.violetL,
                          size: 42,
                          circle: false,
                          glow: false),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Tüm Soruları İndir',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 14, color: c.text)),
                            const SizedBox(height: 2),
                            Text(
                              'Yaklaşık ${formatEstimatedSize(kQuestionBankEstimatedBytes)}',
                              style: TextStyle(fontSize: 11.5, color: c.textFaint),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Her konunun tüm soru havuzunu cihazına indirir; internetin olmadığı '
                    'yerlerde bile testlere sınırsız girebilirsin.',
                    style: TextStyle(fontSize: 12, height: 1.35, color: c.textFaint),
                  ),
                  const SizedBox(height: 12),
                  if (_downloading) ...[
                    DsProgressBar(
                      value: _downloadTotal == 0 ? 0 : _downloadDone / _downloadTotal,
                      color: c.violetL,
                      height: 8,
                    ),
                    const SizedBox(height: 8),
                    Text('$_downloadDone / $_downloadTotal konu indirildi...',
                        style: TextStyle(fontSize: 12, color: c.textFaint)),
                  ] else ...[
                    if (_cachedCount != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          '$_cachedCount konu şu an cihazda hazır (internetsiz kullanılabilir).',
                          style: TextStyle(fontSize: 12, color: c.textFaint),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DsPillButton(
                        label: 'Tüm Soruları İndir',
                        color: c.violetL,
                        leadingIcon: Icons.download,
                        onPressed: () {
                          context.read<SoundService>().click();
                          _downloadAll();
                        },
                      ),
                    ),
                  ],
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
