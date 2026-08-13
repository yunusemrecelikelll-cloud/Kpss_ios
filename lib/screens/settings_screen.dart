import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/account_deletion_service.dart';
import '../services/auth_service.dart';
import '../services/in_app_notice_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../services/remote_question_service.dart';
import '../theme/app_theme.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';
import 'account_login_screen.dart';
import 'hak_satin_al_screen.dart';
import 'premium_screen.dart';
import 'quiz_screen.dart' show kVarsayilanSoruCevapModu;
import 'privacy_policy_screen.dart';
import 'splash_screen.dart';
import '../widgets/resmi_kurum_feragati.dart';
import '../utils/ust_bildirim.dart';

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

/// Gireceğin KPSS sınav türü seçenekleri. `deger`, StorageService'in examType
/// anahtarıyla aynı sözlüğü kullanır: 'ortaogretim' | 'onlisans' | 'lisans'.
/// Seçilen sınav türü, sorulara ve oyunlara uygulanan zorluğu da belirler
/// (Ortaöğretim=kolay, Önlisans=normal, Lisans=zor). Bu seçim eskiden Profil'de
/// "Hangi sınava gireceksin?" olarak duruyordu; buraya taşındı.
const List<_SoruCevapSecenegi> _kSinavTuruSecenekleri = [
  _SoruCevapSecenegi(
    'ortaogretim',
    'Ortaöğretim',
    'Temel, herkesin bilmesi beklenen sorular (kolay).',
  ),
  _SoruCevapSecenegi(
    'onlisans',
    'Önlisans',
    'Orta düzey, biraz detay isteyen sorular (normal).',
  ),
  _SoruCevapSecenegi(
    'lisans',
    'Lisans',
    'İleri düzey, ayrıntı ve uzmanlık isteyen sorular (zor).',
  ),
];

/// JS karşılığı: renderSettings() (src/js/app.js).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// "Soruları Güncelle" o an kontrol/indirme yapıyor mu.
  bool _checkingUpdate = false;

  /// "Oyun Kartlarını Güncelle" o an kontrol/indirme yapıyor mu.
  bool _checkingCards = false;

  /// "Çıkış Yap" akışı.
  ///
  /// Tek adımlık bir onay yetiyor: çıkmak GERİ ALINABİLİR bir işlem, kullanıcı
  /// istediği zaman tekrar giriş yapar. Bu yüzden "Hesabımı Sil"deki gibi
  /// yazarak teyit istemiyoruz.
  ///
  /// Onay metninde yerel ilerlemenin SİLİNMEDİĞİNİ açıkça söylüyoruz — asıl
  /// korku bu ve söylenmezse kullanıcı çıkmaya çekinir.
  Future<void> _cikisYap() async {
    // Context'e bağlı her şeyi await'ten ÖNCE al (bkz. _hesabiSil'deki not).
    context.read<SoundService>().click();
    final auth = context.read<AuthService>();
    final storage = context.read<StorageService>();

    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Çıkış yap?'),
        content: const Text(
          'Hesabından çıkacaksın ve uygulama misafir görünümüne dönecek. '
          'İlerlemen, istatistiklerin ve premium durumun HESABINDA saklı '
          'kalır — aynı hesapla tekrar giriş yaptığında olduğu gibi geri gelir.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Çıkış Yap')),
        ],
      ),
    );
    if (onay != true) return;

    await auth.signOut();
    // ÇIKIŞTA TAM SIFIRLAMA (kullanıcı isteği: "çıkış yapınca premium ve
    // yanlışlarım görünmesin, uygulama sıfırlansın"): tertemiz Misafir
    // profiline dönülür. Hesabın verilerine DOKUNULMAZ — kendi profilinde
    // durur, aynı hesapla girişte olduğu gibi geri gelir.
    await storage.misafireDon();
    ustBildirim('Çıkış yapıldı.');
  }

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
    var ilerlemeAcik = true;

    // TAKILMA KORUMASI ("hesabın siliniyor yazısında sürekli kalıyor"):
    // Ağ koptuğunda/yavaşladığında Firestore çağrıları çok uzun bekleyebiliyor
    // ve ilerleme penceresi sonsuza dek açık kalıyordu. Silmenin tamamına
    // 45 saniyelik üst sınır koyuyoruz — süre aşılırsa pencere kapanır ve
    // kullanıcıya net bir mesajla tekrar denemesi söylenir. (Silme adımları
    // best-effort ve tekrarlanabilir: ikinci deneme kaldığı yerden temizler.)
    try {
      await servis
          .deleteAccount(storage)
          .timeout(const Duration(seconds: 45));
    } on TimeoutException {
      hataMesaji =
          'Silme işlemi zaman aşımına uğradı. İnternet bağlantını kontrol '
          'edip tekrar dene — şimdiye kadar silinenler silinmiş kalır, '
          'ikinci deneme kaldığı yerden devam eder.';
    } on ReauthRequiredException {
      // Oturum eski: Auth kaydını silmek için yeniden doğrulama şart.
      //
      // UX DÜZELTMESİ: Eskiden Google/Apple yeniden giriş penceresi, "Hesabın
      // siliniyor…" ilerleme penceresi EKRANDA AÇIKKEN fırlıyordu — kullanıcı
      // "silerken neden giriş istiyor?" diye haklı olarak şaşırıyordu. Artık
      // önce ilerleme penceresi KAPANIR, NEDEN yeniden giriş gerektiği açıkça
      // anlatılır, kullanıcı onaylarsa doğrulama yapılır ve silme ilerleme
      // penceresi yeniden açılarak tamamlanır.
      navigator.pop();
      ilerlemeAcik = false;

      if (!mounted) return;
      final devamEt = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Güvenlik doğrulaması gerekiyor'),
          content: const Text(
              'Hesap silme geri alınamaz bir işlem olduğu için, son adımda '
              'kimliğini bir kez daha doğrulamamız gerekiyor. Devam edersen '
              'giriş ekranı açılacak; doğrulama biter bitmez silme işlemi '
              'kaldığı yerden tamamlanacak.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Doğrula ve Sil')),
          ],
        ),
      );
      if (devamEt != true) {
        ustBildirim('Silme tamamlanmadı. Hesabın duruyor; istersen daha sonra tekrar deneyebilirsin.', tur: UstBildirimTuru.basari);
        return;
      }

      final sonuc = await auth.reauthenticate();
      if (sonuc.success) {
        if (!mounted) return;
        // İlerleme penceresini yeniden aç ve kalan silmeyi bitir.
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const PopScope(
            canPop: false,
            child: AlertDialog(
              content: Row(
                children: [
                  SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5)),
                  SizedBox(width: 16),
                  Expanded(child: Text('Hesabın siliniyor…')),
                ],
              ),
            ),
          ),
        );
        ilerlemeAcik = true;
        try {
          await servis
              .deleteAccount(storage)
              .timeout(const Duration(seconds: 45));
        } on TimeoutException {
          hataMesaji =
              'Silme işlemi zaman aşımına uğradı. İnternet bağlantını '
              'kontrol edip tekrar dene.';
        } catch (e) {
          hataMesaji = e.toString();
        }
      } else {
        hataMesaji = sonuc.errorMessage ?? 'Yeniden giriş yapılamadı.';
      }
    } catch (e) {
      hataMesaji = e.toString();
    }

    if (ilerlemeAcik) navigator.pop(); // ilerleme penceresini kapat

    if (hataMesaji != null) {
      ustBildirim(hataMesaji, tur: UstBildirimTuru.hata);
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

  /// Oyun kartları son güncelleme kontrolü (ISO 8601 metin).
  static const String _kSonKartKontrolKey = 'sonKartGuncellemeKontrolu';

  static const List<String> _kAyKisa = [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ];

  /// 2026-07-21 → "21 Tem 2026"
  String _tarihMetni(DateTime d) => '${d.day} ${_kAyKisa[d.month - 1]} ${d.year}';

  /// 2026-07-21 14:30 → "21 Tem 2026, 14:30" (saat+dakika iki haneli).
  String _tarihSaatMetni(DateTime d) {
    final ss = d.hour.toString().padLeft(2, '0');
    final dd = d.minute.toString().padLeft(2, '0');
    return '${_tarihMetni(d)}, $ss:$dd';
  }

  /// Ayarlardan son kontrol tarihini okur (yoksa null).
  DateTime? _sonKontrol(StorageService storage) {
    final raw = storage.getSettings()[_kSonKontrolKey];
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }

  /// Oyun kartları için son kontrol tarihini okur (yoksa null).
  DateTime? _sonKartKontrol(StorageService storage) {
    final raw = storage.getSettings()[_kSonKartKontrolKey];
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }

  /// "Oyun Kartlarını Güncelle" — kart havuzu, derslerin konu içeriğinden ve
  /// güncel soru bankasından beslendiği için uzak içeriği yeniler (soru
  /// güncellemesiyle AYNI mekanizma: RemoteQuestionService.checkAndUpdate).
  Future<void> _kartGuncelle() async {
    final remote = context.read<RemoteQuestionService>();
    final storage = context.read<StorageService>();
    setState(() => _checkingCards = true);
    final sonuc = await remote.checkAndUpdate();
    if (sonuc.sonuc != UpdateOutcome.hata) {
      await storage.saveSettings(
          {_kSonKartKontrolKey: DateTime.now().toIso8601String()});
    }
    if (!mounted) return;
    setState(() => _checkingCards = false);
    final String mesaj;
    switch (sonuc.sonuc) {
      case UpdateOutcome.guncellendi:
        mesaj = 'Oyun kartları güncellendi.';
      case UpdateOutcome.zatenGuncel:
        mesaj = 'Oyun kartları zaten güncel.';
      case UpdateOutcome.hata:
        mesaj = 'Güncelleme kontrol edilemedi, internetini kontrol et.';
    }
    ustBildirim(mesaj);
  }

  Future<void> _soruGuncelle() async {
    // Tüm context bağımlılıklarını await'lerden ÖNCE yakala.
    final remote = context.read<RemoteQuestionService>();
    final storage = context.read<StorageService>();

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
    ustBildirim(mesaj);
  }

  /// Sosyal medya hesabını açar: kullanıcının UYGULAMASI varsa (Instagram
  /// için özel şema, Threads için app-link) doğrudan uygulamada, yoksa web'de.
  Future<void> _sosyalAc(BuildContext context,
      {String? appUri, required String webUrl}) async {
    context.read<SoundService>().click();
    // 1) Önce uygulama şeması denenir (yüklüyse uygulama açılır).
    if (appUri != null) {
      try {
        final ok = await launchUrl(Uri.parse(appUri),
            mode: LaunchMode.externalApplication);
        if (ok) return;
      } catch (_) {/* uygulama yok — web'e düş */}
    }
    // 2) Web/app-link: Instagram/Threads uygulaması kuruluysa OS bu bağlantıyı
    // yine uygulamada açar (Android App Links / iOS Universal Links); değilse
    // tarayıcıda açılır.
    try {
      await launchUrl(Uri.parse(webUrl), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) ustBildirim('Bağlantı açılamadı.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final themeProvider = context.watch<ThemeProvider>();
    final c = themeProvider.colors;
    final settings = storage.getSettings();
    final soundOn = settings['soundEnabled'] != false;
    final soruCevapModu = (settings['soruCevapModu'] as String?) ?? kVarsayilanSoruCevapModu;
    final premium = storage.isPremiumUser();
    final cloudBackup = storage.getCloudBackupEnabled();
    final adaptationSounds = storage.getAdaptationSoundsEnabled();
    // "Hesabımı Sil" yalnızca gerçekten bir hesap varken gösterilir.
    // watch (read değil) — kullanıcı giriş/çıkış yapınca ekran kendini
    // tazelesin ve seçenek anında görünsün/kaybolsun.
    // isRealSignedIn: anonim oturum (düello/sohbetin sessizce açtığı) "giriş
    // yapılmış" SAYILMAZ — yoksa hesabı olmayan kullanıcıya "Çıkış Yap /
    // Hesabımı Sil" gösterilip "Giriş Yap" gizleniyordu.
    final girisYapildi = context.watch<AuthService>().isRealSignedIn;

    return Scaffold(
      appBar: AppBar(title: const Text('⚙️ Ayarlar')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── HESAP (kullanıcı isteği: en başta) ──────────────────────
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
                  // NOT: Bildirim tercih anahtarları KALDIRILDI (proje henüz
                  // bildirim paketi içermiyor); gerçek destek eklenince geri
                  // konabilir. App Store Guideline 2.1: çalışmayan görünür
                  // özellik reddi sebebidir.
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
                      storage.setCloudBackupEnabled(v);
                      ustBildirim(v
                              ? 'Bulut yedekleme açıldı — ilerlemen bundan sonra hesabına yedeklenecek.'
                              : 'Bulut yedekleme kapatıldı — yeni veri yüklenmeyecek.');
                    },
                  ),
                  // App Store 5.1.1(v): giriş yapılmışsa hesap silme sunulur.
                  // Giriş yapılmamışsa buradan giriş ekranına yönlendirilir.
                  if (!girisYapildi)
                    ListTile(
                      leading: DsIconBadge(
                          icon: Icons.login_rounded,
                          color: c.violet,
                          size: 42,
                          circle: false,
                          glow: false),
                      title: Text('Giriş Yap',
                          style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                      subtitle: Text(
                          'Hesabınla giriş yap; ilerlemeni taşı, sohbet ve düelloya katıl.',
                          style: TextStyle(fontSize: 12, color: c.textFaint)),
                      trailing: Icon(Icons.chevron_right, size: 18, color: c.textFaint),
                      onTap: () {
                        context.read<SoundService>().click();
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const AccountLoginScreen(),
                        ));
                      },
                    ),
                  if (girisYapildi) ...[
                    Divider(height: 1, color: c.border),
                    ListTile(
                      leading: DsIconBadge(
                          icon: Icons.logout_rounded,
                          color: c.violetL,
                          size: 42,
                          circle: false,
                          glow: false),
                      title: Text('Çıkış Yap',
                          style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                      subtitle: Text(
                          'Hesabından çıkarsın. Cihazdaki ilerlemen silinmez.',
                          style: TextStyle(fontSize: 12, color: c.textFaint)),
                      trailing: Icon(Icons.chevron_right, size: 18, color: c.textFaint),
                      onTap: () => _cikisYap(),
                    ),
                    Divider(height: 1, color: c.border),
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
                ],
              ),
            ),

            // ── GÖRÜNÜM ─────────────────────────────────────────────────
            const SizedBox(height: 20),
            DsSectionHeader(
                title: premium ? '🎨 Görünüm (9/9 tema açık)' : '🎨 Görünüm (3/9 tema açık)'),
            const SizedBox(height: 8),
            DsCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // TEK SATIR, YANA KAYDIRMALI (kullanıcı isteği): kart boyutu
                  // eski 3x3 dizilimdekiyle aynı kalır (genişlik/3'e yakın),
                  // 9 tema tek satırda yatay kaydırılır. Sağ kenardaki tema
                  // yarım ve SİLİK görünsün diye sağa doğru solma maskesi
                  // (ShaderMask) uygulanır — böylece kullanıcı sağa
                  // kaydırabileceğini anlar.
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const bosluk = 10.0;
                      // ~3.3 kart görünür: 3 tam + sağda yarım (silik) peek.
                      final kartGenislik =
                          (constraints.maxWidth - bosluk * 3) / 3.3;
                      return SizedBox(
                        height: 108,
                        child: ShaderMask(
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [Colors.white, Colors.white, Colors.transparent],
                            stops: [0.0, 0.80, 1.0],
                          ).createShader(rect),
                          blendMode: BlendMode.dstIn,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.zero,
                            physics: const BouncingScrollPhysics(),
                            itemCount: kThemes.length,
                            itemBuilder: (context, i) {
                              final entry = kThemes.entries.elementAt(i);
                              return Container(
                                width: kartGenislik,
                                margin: const EdgeInsets.only(right: bosluk),
                                child: _ThemeSwatch(
                                  colors: entry.value,
                                  active: themeProvider.themeId == entry.key,
                                  locked: !premium && !kFreeThemeIds.contains(entry.key),
                                  onTap: () async {
                            context.read<SoundService>().click();
                            final ok = await themeProvider.setTheme(entry.key);
                            if (!context.mounted) return;
                            if (!ok) {
                              Navigator.of(context)
                                  .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                              return;
                            }
                            // Üstten kayan temalı afiş (SnackBar yerine —
                            // kullanıcı isteği: bildirimler üstten gelsin).
                            InAppNoticeService.instance.goster(
                              const InAppNotice(
                                baslik: 'Tema değiştirildi',
                                govde: '',
                                emoji: '🎨',
                                // Peş peşe tema değişiminde tek (son) afiş.
                                etiket: 'tema',
                              ),
                            );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
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

            // ── BİZİ TAKİP ET ───────────────────────────────────────────
            const SizedBox(height: 20),
            const DsSectionHeader(title: '📣 Bizi Takip Et'),
            const SizedBox(height: 8),
            DsCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _SosyalSatir(
                    renk: const Color(0xFFE1306C),
                    emoji: '📸',
                    baslik: 'Instagram',
                    kullaniciAdi: '@kpsshazirliksorubankasi',
                    aciklama:
                        'Her gün 4 Akılda Kalıcı Kodlama, 4 Motivasyon, 4 "Bunu biliyor musunuz?"',
                    onTap: () => _sosyalAc(
                      context,
                      appUri:
                          'instagram://user?username=kpsshazirliksorubankasi',
                      webUrl:
                          'https://www.instagram.com/kpsshazirliksorubankasi?igsh=NDh4cGFlZmFlbWln&utm_source=qr',
                    ),
                  ),
                  Divider(height: 1, color: c.border),
                  _SosyalSatir(
                    renk: c.text,
                    emoji: '🧵',
                    baslik: 'Threads',
                    kullaniciAdi: '@kpsshazirliksorubankasi',
                    aciklama:
                        'Her gün 12 Anketli Soru, 4 Akılda Kalıcı Kodlama, 4 Motivasyon, 4 "Bunu biliyor musunuz?"',
                    onTap: () => _sosyalAc(
                      context,
                      appUri: null,
                      webUrl:
                          'https://www.threads.com/@kpsshazirliksorubankasi?igshid=NTc4MTIwNjQ2YQ==',
                    ),
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

            const SizedBox(height: 20),
            // ── SINAV TÜRÜ ──────────────────────────────────────────────
            // Gireceğin KPSS sınavı. Seçim tüm uygulamada geçerli
            // (Question.examType ve Doğru/Yanlış oyunu buna göre süzülür) ve
            // aynı zamanda zorluğu belirler: Ortaöğretim=kolay, Önlisans=normal,
            // Lisans=zor. Bu seçim eskiden Profil'deydi, buraya taşındı.
            const DsSectionHeader(title: '🎓 Gireceğin KPSS Sınavı'),
            const SizedBox(height: 8),
            DsCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gireceğin sınavı seç; sorular ve oyunlar bu sınavın düzeyine '
                    'göre gelsin. Yeterli soru yoksa havuz otomatik genişler.',
                    style: TextStyle(fontSize: 12.5, height: 1.35, color: c.textFaint),
                  ),
                  const SizedBox(height: 12),
                  for (final sv in _kSinavTuruSecenekleri) ...[
                    _RadioSecenek(
                      baslik: sv.baslik,
                      aciklama: sv.aciklama,
                      selected: storage.getExamType() == sv.deger,
                      onTap: () {
                        context.read<SoundService>().click();
                        storage.setExamType(sv.deger);
                        ustBildirim('${sv.baslik} seçildi.');
                      },
                    ),
                    if (sv != _kSinavTuruSecenekleri.last) const SizedBox(height: 10),
                  ],
                ],
              ),
            ),

            // ── HAKLAR (yalnızca ücretsiz kullanıcıda) ──────────────────
            // Premium'da hak/reklam sistemi tümüyle GİZLİ (sınırsız + reklamsız).
            if (!premium) ...[
              const SizedBox(height: 20),
              const DsSectionHeader(title: '🎟️ Haklarım'),
              const SizedBox(height: 8),
              DsCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: DsIconBadge(
                      emoji: '🎟️', color: c.gold, size: 42, glow: false),
                  title: Text('${storage.getHaklar()} hak',
                      style: TextStyle(fontWeight: FontWeight.w800, color: c.text)),
                  subtitle: Text(
                      'Oyunlarda ekstra oynama ve deneme sınavı tekrarı için. '
                      'Satın al ya da reklam izleyerek kazan.',
                      style: TextStyle(fontSize: 12, color: c.textFaint)),
                  trailing: Icon(Icons.chevron_right, size: 18, color: c.textFaint),
                  onTap: () {
                    context.read<SoundService>().click();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const HakSatinAlScreen()));
                  },
                ),
              ),
            ],

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
                        ustBildirim('${secenek.baslik} seçildi.');
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
                                    : 'Son güncelleme: ${_tarihSaatMetni(son)}',
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
                  // ── Oyun Kartlarını Güncelle (kullanıcı isteği: soru
                  // güncellemesiyle AYNI yerde, aynı mekanizma) ──
                  const SizedBox(height: 16),
                  Divider(color: c.border, height: 1),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DsIconBadge(
                          icon: Icons.style_rounded,
                          color: c.gold,
                          size: 42,
                          circle: false,
                          glow: false),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Oyun Kartlarını Güncelle',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 14, color: c.text)),
                            const SizedBox(height: 2),
                            Builder(builder: (_) {
                              final son = _sonKartKontrol(storage);
                              return Text(
                                son == null
                                    ? 'Henüz güncellenmedi'
                                    : 'Son güncelleme: ${_tarihSaatMetni(son)}',
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
                    'Kart Eşleştirme oyunundaki kartlar, güncel ders içeriğinden '
                    'beslenir. Yeni içerik için dokun.',
                    style: TextStyle(fontSize: 12, height: 1.35, color: c.textFaint),
                  ),
                  const SizedBox(height: 12),
                  if (_checkingCards)
                    Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: c.gold),
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
                        label: 'Oyun Kartlarını Güncelle',
                        color: c.gold,
                        leadingIcon: Icons.refresh,
                        onPressed: () {
                          context.read<SoundService>().click();
                          _kartGuncelle();
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
            const SizedBox(height: 10),
            // Resmî kurum feragatı + tıklanabilir ÖSYM bağlantısı — uygulamanın
            // bağımsız olduğunu açıkça beyan eder (Play/App Store "resmî devlet
            // uygulaması" izlenimi kaygısına karşı). Görünür bir yer: Hakkında.
            const ResmiKurumFeragati(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

/// "Bizi Takip Et" bölümündeki tek sosyal medya satırı — ikon rozeti, ad +
/// kullanıcı adı, kısa açıklama ve dış bağlantı oku.
class _SosyalSatir extends StatelessWidget {
  final Color renk;
  final String emoji;
  final String baslik;
  final String kullaniciAdi;
  final String aciklama;
  final VoidCallback onTap;
  const _SosyalSatir({
    required this.renk,
    required this.emoji,
    required this.baslik,
    required this.kullaniciAdi,
    required this.aciklama,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: renk.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: renk.withValues(alpha: 0.45)),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 20)),
      ),
      title: Row(
        children: [
          Text(baslik,
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14, color: c.text)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(kullaniciAdi,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: renk)),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(aciklama,
            style: TextStyle(fontSize: 11.5, height: 1.35, color: c.textFaint)),
      ),
      trailing: Icon(Icons.open_in_new_rounded, size: 18, color: c.textFaint),
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
        // Genişlik dışarıdan (LayoutBuilder ile 3 sütun) verilir; sabit
        // genişlik yok — böylece her satırda tam 3 tema dizilir.
        width: double.infinity,
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
              // Platforma göre doğru mağaza adı (Android'de "App Store"
              // yazması yanıltıcıydı).
              defaultTargetPlatform == TargetPlatform.android
                  ? 'Satın aldığın bir abonelik varsa Google Play üzerinden ayrıca '
                      'iptal etmen gerekir — hesap silmek aboneliği durdurmaz.'
                  : 'Satın aldığın bir abonelik varsa App Store üzerinden ayrıca '
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
