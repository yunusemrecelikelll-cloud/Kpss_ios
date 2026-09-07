import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/data_service.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final data = context.read<DataService>();
    final storage = context.read<StorageService>();
    final subjects = await data.loadAll();
    if (!mounted) return;

    // Uygulama artık kayıt/giriş sormadan direkt açılıyor — tek kullanıcılı
    // yapı için sessizce yerel bir varsayılan profil oluşturulur. İsim/
    // cinsiyet/sınav türü istenildiğinde Profil ekranından, hesap girişi
    // (Google/Apple) ise Anasayfa'daki banner'dan ya da Sohbet'ten yapılabilir.
    if (!storage.hasProfile) {
      final name = await storage.addUser('Misafir');
      await storage.setActiveUser(name);
      await storage.setUserName(name);
    }

    // Kullanıcı zaten (önceki bir oturumdan) Google/Apple ile giriş yapmışsa,
    // her açılışta buluttaki en güncel ilerleme/premium durumunu sessizce
    // çek — böylece telefon değiştirince ya da uygulamayı silip tekrar
    // kurunca "her şey sıfırlanmış" gibi görünmez.
    final auth = context.read<AuthService>();
    if (auth.isSignedIn) {
      // ZAMAN AŞIMI ŞART: Firestore'a hiç erişilemeyen bir ağda (uçak modu,
      // captive portal, mağaza inceleme cihazının kısıtlı ağı) bu çağrı
      // dakikalarca asılı kalabilir ve kullanıcı açılış ekranında sonsuz
      // spinner görür. Yedek indirilemezse uygulama zaten yerel veriyle
      // sorunsuz çalışır — bekletmeye değmez.
      await CloudSyncService()
          .syncDown(storage)
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
    }
    if (!mounted) return;

    // İLK KURULUM: kaydırmalı tanıtımı bir kez göster. Sonraki açılışlarda
    // (bayrak set) doğrudan uygulamaya gir — bu splash zaten logo+slogan
    // gösterip otomatik başladığı için ayrı bir "başla" adımı yok.
    final onboardingBitti = storage.onboardingGorulduMu();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => onboardingBitti
            ? MainShell(subjects: subjects)
            : OnboardingScreen(subjects: subjects),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo (masaüstündeki logo.jpeg'den üretilen ikon).
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset('assets/images/logo.png',
                  width: 132, height: 132, fit: BoxFit.cover),
            ),
            const SizedBox(height: 20),
            Text('KPSS Hazırlık',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w900, color: c.text)),
            const SizedBox(height: 6),
            Text('Sıkılmadan çalış, sınavı kazan',
                style: TextStyle(fontSize: 13.5, color: c.textFaint)),
            const SizedBox(height: 26),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6, color: c.violet),
            ),
          ],
        ),
      ),
    );
  }
}
