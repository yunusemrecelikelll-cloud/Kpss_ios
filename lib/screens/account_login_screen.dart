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

    // 2) İSİM: yalnızca bu hesabın profili BOŞSA hesap adıyla doldurulur.
    //    Kullanıcı Profil'den kendi ismini yazdıysa o isim KALICIDIR — her
    //    girişte Google adıyla ezilmez (kullanıcı isteği: profildeki isim
    //    her yerde geçerli olsun).
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

    // Önce buluttaki ilerlemeyi indir, sonra yerel durumu yükle. Zaman aşımı
    // + try/catch: ağ ya da bozuk veri GİRİŞİ ASLA çökertmesin ("hesap
    // değişince anasayfa çöküyor" şikayetine karşı savunma hattı).
    try {
      final cloud = CloudSyncService();
      await cloud
          .syncDown(storage)
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
      await cloud
          .syncUp(storage)
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
    } catch (e) {
      debugPrint('Giriş sonrası senkron hatası (giriş yine de başarılı): $e');
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
