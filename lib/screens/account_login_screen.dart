import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';

/// Anasayfa'daki "Giriş yap" banner'ından açılan, isteğe bağlı hesap girişi
/// ekranı. Uygulama artık girişsiz de tam çalıştığı için bu ekran zorunlu bir
/// adım değil — sadece Google/Apple ile bağlanmanın getirdiği ekstraları
/// (sohbet kimliği, ileride bulut yedekleme) anlatır.
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
    if (result.success) {
      // ÖNEMLİ: Google/Apple girişi Firebase Auth'ta oturum açar ama yerel
      // StorageService'teki isim/aktif kullanıcı alanlarını KENDİLİĞİNDEN
      // güncellemez — bu yüzden giriş sonrası anasayfa hâlâ "Misafir"
      // gösteriyordu. Gerçek hesap adını burada senkronize ediyoruz.
      final displayName = result.user?.displayName?.trim();
      final storage = context.read<StorageService>();
      if (displayName != null && displayName.isNotEmpty) {
        await storage.setUserName(displayName);
      }
      // ÖNEMLİ: Bu hesapla daha önce başka bir cihazda/kurulumda ilerleme
      // kaydedilmişse önce onu indir (syncDown — yerelde eksik olanı tamamlar,
      // var olanı ÇİFTLEMEZ), sonra güncel yerel durumu buluta yaz (syncUp) —
      // böylece "giriş yap, ilerlemen/satın alman geri gelsin" gerçekten çalışır.
      // Zaman aşımı: ağ kötüyse giriş akışı burada asılı kalmasın —
      // senkronizasyon başarısız olsa bile giriş BAŞARILIDIR, veri bir
      // sonraki açılışta/test bitiminde tekrar denenir.
      final cloud = CloudSyncService();
      await cloud
          .syncDown(storage)
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
      await cloud
          .syncUp(storage)
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Giriş başarılı! 🎉')),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? 'Giriş başarısız oldu.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final c = context.watch<ThemeProvider>().colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Giriş Yap')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🔐', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                const Text('Hesabına Giriş Yap', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(
                  'Giriş yaparsan:',
                  style: TextStyle(fontSize: 13, color: c.textFaint, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const _Perk(icon: '💬', text: 'Sohbette gerçek adınla mesajlaşabilirsin'),
                const _Perk(icon: '☁️', text: 'İlerlemen hesabına bağlanır, telefon değiştirsen de kaybolmaz'),
                const _Perk(icon: '🔒', text: 'Satın alımların hesabınla eşleşir, güvenle geri yüklenir'),
                const SizedBox(height: 28),
                SizedBox(
                  width: 300,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _signIn(auth.signInWithGoogle),
                    icon: const Text('🇬', style: TextStyle(fontSize: 16)),
                    label: const Text('Google ile Giriş Yap'),
                  ),
                ),
                if (auth.isAppleSignInAvailable) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 300,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _signIn(auth.signInWithApple),
                      icon: const Icon(Icons.apple, size: 18),
                      label: const Text('Apple ile Giriş Yap'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    context.read<SoundService>().click();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Şimdi değil'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  final String icon, text;
  const _Perk({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
