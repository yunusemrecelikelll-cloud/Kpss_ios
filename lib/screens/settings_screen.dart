import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../services/data_service.dart';
import '../services/remote_question_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import 'premium_screen.dart';
import 'privacy_policy_screen.dart';

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
            // ── Tema ──
            _SectionTitle(premium ? '🎨 Uygulama Teması (9/9 açık)' : '🎨 Uygulama Teması (3/9 açık)'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(
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
              ),
            ),
            if (!premium)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '🔒 6 tema daha Premium\'da açılıyor.',
                  style: TextStyle(fontSize: 12, color: c.textFaint),
                ),
              ),

            // ── Ses ──
            const _SectionTitle('🔊 Ses Efektleri'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Buton sesleri', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Tıklamalarda ses çıkar; son 5 saniye tik-tak sesi gelir',
                        style: TextStyle(fontSize: 12)),
                    value: soundOn,
                    onChanged: (v) => storage.saveSettings({'soundEnabled': v}),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Adaptasyon Sesleri', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text(
                        'Test çözerken gerçekçi sınav salonu sesleri duy — öksürük, kağıt hışırtısı, kalem sesi',
                        style: TextStyle(fontSize: 12)),
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

            // ── Süre Modu ──
            const _SectionTitle('⏱️ Test Süresi'),
            Card(
              child: Padding(
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
            ),

            // ── Abonelik ──
            const _SectionTitle('💎 Abonelik'),
            Card(
              child: ListTile(
                title: Row(
                  children: [
                    const Text('Planın: ', style: TextStyle(fontWeight: FontWeight.w700)),
                    Chip(
                      label: Text(premium ? 'Premium' : 'Ücretsiz'),
                      backgroundColor: premium ? c.gold.withValues(alpha: 0.2) : null,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Premium paketinde detaylı grafikler, özel testler ve VIP ayrıcalıklar yer alır.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                isThreeLine: true,
                trailing: ElevatedButton(
                  onPressed: () {
                    context.read<SoundService>().click();
                    Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                  },
                  child: const Text('Ayrıntıları Gör'),
                ),
              ),
            ),

            // ── Premium Karakter ──
            const _SectionTitle('🦉 Premium Karakter'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: premium
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                        ],
                      )
                    : Text(
                        "Premium'a geçerek profilin için özel karakterler açabilirsin.",
                        style: TextStyle(fontSize: 12.5, color: c.textFaint),
                      ),
              ),
            ),

            // ── Bildirimler ──
            const _SectionTitle('🔔 Bildirimler'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Hatırlatma bildirimleri', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Günlük soru hatırlatıcısı ve KPSS güncellemeleri al.',
                        style: TextStyle(fontSize: 12)),
                    value: notif['reminders'] == true,
                    onChanged: (v) => storage.saveNotificationSettings({'reminders': v}),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Güncelleme bildirimleri', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Yeni içerik ve duyuruları uygulama içinde gör.',
                        style: TextStyle(fontSize: 12)),
                    value: notif['updates'] == true,
                    onChanged: (v) => storage.saveNotificationSettings({'updates': v}),
                  ),
                ],
              ),
            ),

            // ── Bulut Yedekleme ──
            const _SectionTitle('☁️ Bulut Yedekleme'),
            Card(
              child: SwitchListTile(
                title: const Text('Bulut yedekleme', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Profilini ve ilerlemeni çevrimiçi yedeklemeye hazırlık.',
                    style: TextStyle(fontSize: 12)),
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
            ),
            // ── Çevrimdışı Kullanım ──
            const _SectionTitle('📥 Çevrimdışı Kullanım'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Tüm Soruları İndir', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 6),
                        Text('(${formatEstimatedSize(kQuestionBankEstimatedBytes)})',
                            style: TextStyle(fontSize: 12, color: c.textFaint)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Her konunun tüm soru havuzunu cihazına indirir; internetin olmadığı '
                      'yerlerde bile testlere sınırsız girebilirsin.',
                      style: TextStyle(fontSize: 12, color: c.textFaint),
                    ),
                    const SizedBox(height: 10),
                    if (_downloading) ...[
                      LinearProgressIndicator(
                        value: _downloadTotal == 0 ? null : _downloadDone / _downloadTotal,
                      ),
                      const SizedBox(height: 6),
                      Text('$_downloadDone / $_downloadTotal konu indirildi...',
                          style: TextStyle(fontSize: 12, color: c.textFaint)),
                    ] else ...[
                      if (_cachedCount != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '$_cachedCount konu şu an cihazda hazır (internetsiz kullanılabilir).',
                            style: TextStyle(fontSize: 12, color: c.textFaint),
                          ),
                        ),
                      ElevatedButton.icon(
                        onPressed: () {
                          context.read<SoundService>().click();
                          _downloadAll();
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('Tüm Soruları İndir'),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Yasal ──
            const _SectionTitle('📄 Yasal'),
            Card(
              child: ListTile(
                leading: const Text('🔒'),
                title: const Text('Gizlilik Politikası'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  context.read<SoundService>().click();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 104,
        height: 76,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.bg, colors.bg2],
          ),
          border: Border.all(
            color: active ? colors.violet : colors.border,
            width: active ? 2.5 : 1,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(colors.icon, style: TextStyle(fontSize: 18, color: locked ? colors.textFaint : null)),
                const Spacer(),
                Text(
                  colors.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: locked ? colors.textFaint : colors.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            if (locked)
              Positioned(
                top: 0,
                right: 0,
                child: Icon(Icons.lock, size: 14, color: colors.textFaint),
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
