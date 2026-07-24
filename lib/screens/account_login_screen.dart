import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/presence_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';

/// Hesap giriş ekranı — YALNIZCA Google ve Apple ile giriş.
///
/// E-POSTA/ŞİFRE/KULLANICI ADI KAYIT VE GİRİŞİ KALDIRILDI (kullanıcı kararı):
/// şifre unutma, yarım kayıt, silinen hesapla giriş denemesi gibi bir dizi
/// destek yükü tek hamlede ortadan kalktı. Firebase Auth'ta e-posta sağlayıcısı
/// açık kalsa da uygulama içinden erişilen tek yol Google/Apple.
///
/// Apple ile giriş SADECE iOS'ta gösterilir (App Store kuralı gereği üçüncü
/// taraf girişi olan iOS uygulamasında Apple zorunlu; Android'de gereksiz).
class AccountLoginScreen extends StatefulWidget {
  const AccountLoginScreen({super.key});

  @override
  State<AccountLoginScreen> createState() => _AccountLoginScreenState();
}

class _AccountLoginScreenState extends State<AccountLoginScreen> {
  bool _busy = false;

  Future<void> _signIn(Future<AuthResult> Function() method) async {
    context.read<SoundService>().click();
    setState(() => _busy = true);
    final result = await method();
    if (!mounted) return;
    setState(() => _busy = false);

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? 'Giriş başarısız oldu.')),
      );
      return;
    }

    final storage = context.read<StorageService>();

    // 1) HESABA BAĞLI PROFİL: her hesabın KENDİ yerel verisi var. Girişte o
    //    hesabın profiline geçilir — başka hesabın istatistiği/premium'u
    //    asla görünmez, hesap değişiminde veri karışmaz (kök sorun buydu).
    final uid = result.user?.uid;
    if (uid != null) {
      await storage.hesapProfilineGec(uid);
    }

    // 2) İSİM ÖN DOLGUSU: bu hesabın profili BOŞSA hesap adıyla (Google adı ya
    //    da e-posta öneki) doldurulur — birazdan açılacak isim penceresine
    //    hazır metin olsun diye. Kullanıcı Profil'den kendi ismini yazdıysa o
    //    isim KALICIDIR, ezilmez.
    if (storage.getUserName().isEmpty) {
      final displayName = result.user?.displayName?.trim();
      if (displayName != null && displayName.isNotEmpty) {
        await storage.setUserName(displayName);
      } else {
        final epostaOnEki = result.user?.email?.split('@').first.trim();
        if (epostaOnEki != null && epostaOnEki.isNotEmpty) {
          await storage.setUserName(epostaOnEki);
        }
      }
    }

    // Bulut yedeklemeyi giriş başarılı olur olmaz aç (syncUp bu ayara bakar).
    await storage.setCloudBackupEnabled(true);

    final cloud = CloudSyncService();

    // 3) Önce buluttaki ilerlemeyi indir (isim + isim-onayı da geri gelir; böylece
    //    cihaz değiştiren dönüş kullanıcısına isim TEKRAR sorulmaz). Zaman aşımı +
    //    try/catch: ağ/bozuk veri GİRİŞİ ASLA çökertmesin.
    try {
      await cloud
          .syncDown(storage)
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
    } catch (e) {
      debugPrint('Giriş sonrası syncDown hatası (giriş yine de başarılı): $e');
    }

    // 4) İSMİ SOR: bu hesap ismini daha önce onaylamadıysa bir kez sor. Aktif
    //    profil ARTIK bu hesabın profili olduğu için (adım 1) isim doğru yere
    //    yazılır — hesaplar arası karışma olmaz. Onaylanınca bir daha sorulmaz.
    if (mounted && !storage.getNameConfirmed()) {
      final girilen = await _isimSor(storage.getUserName());
      if (!mounted) return;
      if (girilen != null && girilen.trim().isNotEmpty) {
        await storage.setUserName(girilen);
      }
      await storage.setNameConfirmed(true);
    }

    // 5) Onaylanan ismi + ilerlemeyi buluta yükle.
    try {
      await cloud
          .syncUp(storage)
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
    } catch (e) {
      debugPrint('Giriş sonrası syncUp hatası (giriş yine de başarılı): $e');
    }

    // Yönetici panelden bu hesaba premium verdiyse hemen uygula + canlılık
    // kaydını düş (bkz. PresenceService).
    await PresenceService.instance.premiumKontrol(storage);
    // ignore: unawaited_futures
    PresenceService.instance.bildir(storage);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Giriş başarılı! 🎉')),
    );
    Navigator.of(context).pop();
  }

  /// Giriş sonrası bir kez gösterilen isim penceresi. [onDolgu] ön-dolgu metni
  /// (Google adı / e-posta öneki / buluttaki isim). Kullanıcının onayladığı adı
  /// döner; boş bırakılamaz (Kaydet yalnızca dolu metinde aktif). Pencere
  /// kapatılamaz (barrierDismissible: false) — isim uygulamada her yerde
  /// göründüğü için mutlaka bir değer alınır.
  Future<String?> _isimSor(String onDolgu) async {
    final ctrl = TextEditingController(text: onDolgu);
    final sonuc = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final c = context.read<ThemeProvider>().colors;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Adın ne olsun?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Uygulamada (ana sayfa, sohbet, düello, lig) bu isim görünecek. '
                  'İstediğin zaman Profil’den değiştirebilirsin.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textFaint),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 24,
                  decoration: const InputDecoration(
                    labelText: 'İsim',
                    hintText: 'Örn. Ahmet',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) Navigator.of(dialogCtx).pop(v.trim());
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: ctrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(dialogCtx).pop(ctrl.text.trim()),
                child: const Text('Kaydet'),
              ),
            ],
          ),
        );
      },
    );
    ctrl.dispose();
    return sonuc;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final auth = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Hesap')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DsIllustration(emoji: '🔐', glowColor: c.violetL),
                const SizedBox(height: 16),
                Text('Hesabınla devam et',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900, color: c.text)),
                const SizedBox(height: 8),
                Text(
                  'Giriş yap; ilerlemen buluta yedeklensin, sohbete ve '
                  'düelloya katıl, cihaz değiştirsen de kaldığın yerden devam et.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.5, color: c.textFaint),
                ),
                const SizedBox(height: 28),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  )
                else ...[
                  SizedBox(
                    width: 300,
                    child: DsPillButton(
                      label: 'Google ile Giriş Yap',
                      color: c.violet,
                      leadingIcon: Icons.g_mobiledata_rounded,
                      onPressed: () => _signIn(auth.signInWithGoogle),
                    ),
                  ),
                  if (auth.isAppleSignInAvailable) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 300,
                      // DÜZELTİLDİ: dolu (filled) buton koyu temada c.text
                      // beyaza yakın olduğu için beyaz yazıyla birleşip
                      // okunmuyordu. Dış çizgili stilde yazı/simge vurgu
                      // renginin kendisi olur — her temada zeminle kontrastlı.
                      child: DsPillButton(
                        label: 'Apple ile Giriş Yap',
                        color: c.text,
                        filled: false,
                        leadingIcon: Icons.apple,
                        onPressed: () => _signIn(auth.signInWithApple),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                Text(
                  'Hesabın yoksa endişelenme — ilk girişte otomatik oluşturulur.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: c.textFaint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
