import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';

/// Son güncelleme tarihi — politika metni değiştikçe elle güncellenmeli.
const String kPrivacyPolicyUpdatedAt = '16 Temmuz 2026';

/// Gizlilik Politikası — uygulamanın GERÇEK veri toplama/kullanma
/// davranışını yansıtır (bkz. StorageService, AuthService, ChatService,
/// LeagueService, DuelService, PurchaseService). Yayına almadan önce
/// aşağıdaki "[...]" ile işaretli yer tutucu iletişim bilgisini gerçek bir
/// e-posta adresiyle değiştir.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(title: const Text('🔒 Gizlilik Politikası')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Son güncelleme: $kPrivacyPolicyUpdatedAt',
                style: TextStyle(fontSize: 12, color: c.textFaint, fontStyle: FontStyle.italic)),
            const SizedBox(height: 16),
            _Section(
              title: '1. Bu politika neyi kapsar?',
              body:
                  'Bu Gizlilik Politikası, "KPSS Hazırlık" uygulamasını kullanırken hangi '
                  'verilerin toplandığını, nasıl kullanıldığını ve haklarının neler '
                  'olduğunu açıklar. Uygulamayı kullanarak bu politikayı kabul etmiş '
                  'olursun.',
            ),
            _Section(
              title: '2. Cihazında yerel olarak saklanan veriler',
              body:
                  'Aşağıdaki bilgiler öncelikli olarak kendi cihazında '
                  '(SharedPreferences ile) saklanır:\n\n'
                  '• Profil bilgilerin: isim, cinsiyet, hedeflediğin sınav türü '
                  '(Lisans/Önlisans/Ortaöğretim), hedef meslek tercihin\n'
                  '• Çözdüğün testler, doğru/yanlış sayıların, konu bazlı ilerlemen\n'
                  '• Rozet, seviye/XP, günlük görev ve çalışma serisi (streak) bilgilerin\n'
                  '• Uygulama ayarların (tema, ses tercihleri)\n'
                  '• Yanlış yaptığın soruların listesi ("Yanlışlarım Bankası")\n\n'
                  'ÖNEMLİ: Bu verilerin bir kısmı, YALNIZCA sen hesabına giriş yapmışsan '
                  'VE Ayarlar > Hesap bölümündeki "Bulut yedekleme" seçeneğini AÇMIŞSAN '
                  'hesabına bağlı olarak buluta da yedeklenir (bkz. 3. bölüm). Bulut '
                  'yedekleme varsayılan olarak KAPALIDIR; kapalıyken hiçbir ilerleme '
                  'verisi sunucularımıza gönderilmez.\n\n'
                  'Yerel veriler, uygulamayı cihazından kaldırdığında (uninstall) '
                  'tamamen silinir. Ancak bu, buluttaki hesabını SİLMEZ — bunun için '
                  'Ayarlar > Hesap > "Hesabımı Sil" seçeneğini kullan (bkz. 6. bölüm).',
            ),
            _Section(
              title: '3. Bulut sunucularında (Firebase) saklanan veriler',
              body:
                  'Bazı özellikler gerçek zamanlı çalışabilmek için Firebase (Google) '
                  'altyapısında veri saklar:\n\n'
                  '• Hesabına giriş yaptıysan (Google/Apple ile): ad, e-posta adresi ve '
                  'benzersiz kullanıcı kimliğin kimlik doğrulama için Firebase Authentication\'da tutulur\n'
                  '• Sohbet özelliğini kullanırsan: gönderdiğin genel sohbet mesajları ve '
                  'özel mesajların (DM) içeriği, kimin engellediğin/şikayet ettiğin bilgisi\n'
                  '• Özel Lig\'de: kullanıcı adın ve haftalık/toplam skor bilgin (diğer '
                  'kullanıcılarla karşılaştırma için)\n'
                  '• KPSS Düello/Royale\'de: oyuncu adın, oda içindeki cevapların ve skorun '
                  '(maç süresince, diğer oda oyuncularıyla paylaşılır)\n\n'
                  'Bu veriler sen silinene ya da hesabını kapatana kadar sunucuda kalır.',
            ),
            _Section(
              title: '4. Uygulama içi satın alma',
              body:
                  'Premium abonelik satın alırsan, ödeme işlemi tamamen Apple App Store / '
                  'Google Play tarafından yürütülür — kart bilgilerin bize ULAŞMAZ, bunları '
                  'hiçbir şekilde görmeyiz ya da saklamayız. Sadece "premium aktif mi" bilgisini '
                  'cihazında tutarız.',
            ),
            _Section(
              title: '5. Üçüncü taraf servisler',
              body:
                  'Uygulama şu üçüncü taraf servisleri kullanır: Firebase (Authentication, '
                  'Firestore veritabanı) — Google LLC tarafından işletilir; Google Sign-In ve '
                  'Sign in with Apple — hesap girişi için. Bu servislerin kendi gizlilik '
                  'politikaları da geçerlidir.',
            ),
            _Section(
              title: '6. Verilerini silme hakkın',
              body:
                  'Hesabını ve tüm verilerini uygulama içinden, tek başına silebilirsin: '
                  'Ayarlar > Hesap > "Hesabımı Sil". Bu işlem geri alınamaz ve şunların '
                  'tamamını kalıcı olarak siler: giriş hesabın, bulut yedeğin, test '
                  'sonuçların ve istatistiklerin, rozetlerin ve lig kaydın, genel '
                  'sohbetteki mesajların, özel konuşmaların, engellediğin kullanıcı '
                  'listesi, gönderdiğin şikayet kayıtları ve açtığın düello odaları. '
                  'Ayrıca cihazındaki tüm yerel ilerleme de temizlenir.\n\n'
                  'Not: Uygulamayı cihazından kaldırmak yalnızca yerel veriyi siler, '
                  'buluttaki hesabını silmez. Bir aboneliğin varsa hesap silmek aboneliği '
                  'durdurmaz — aboneliği App Store / Google Play hesabından ayrıca iptal '
                  'etmen gerekir.',
            ),
            _Section(
              title: '7. Çocukların gizliliği',
              body:
                  'Uygulama KPSS\'ye (Kamu Personeli Seçme Sınavı) hazırlanan yetişkin '
                  'adaylar için tasarlanmıştır ve bilerek 13 yaş altı çocuklardan veri '
                  'toplamayı hedeflemez.',
            ),
            _Section(
              title: '8. Bu politikadaki değişiklikler',
              body:
                  'Bu politika zaman zaman güncellenebilir; önemli değişikliklerde '
                  'uygulama içinde bilgilendirme yapılır. Güncel sürüm her zaman bu '
                  'sayfada yer alır.',
            ),
            _Section(
              title: '9. İletişim',
              body:
                  'Gizlilikle ilgili sorular, veri erişim/silme talepleri için: '
                  '[GELİŞTİRİCİ İLETİŞİM E-POSTASINI BURAYA EKLE]',
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: c.violet)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(fontSize: 13, height: 1.55)),
        ],
      ),
    );
  }
}
