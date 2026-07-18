import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/data_service.dart';
import '../services/storage_service.dart';
import 'main_shell.dart';

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
      await CloudSyncService().syncDown(storage);
    }
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MainShell(subjects: subjects)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🌙', style: TextStyle(fontSize: 48)),
            SizedBox(height: 16),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
