import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/storage_service.dart';
import 'services/data_service.dart';
import 'services/quiz_engine.dart';
import 'services/timer_service.dart';
import 'services/sound_service.dart';
import 'services/auth_service.dart';
import 'services/remote_question_service.dart';
import 'services/tts_service.dart';
import 'services/ad_service.dart';
import 'services/ders_bildirim_service.dart';
import 'services/notification_service.dart';
import 'services/study_plan_service.dart';
import 'theme/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'widgets/in_app_notice_overlay.dart';
import 'firebase_bootstrap.dart';

/// Tüm ekranların ÜSTÜNDEKİ katmandan (bildirim/hak göstergesi overlay'i)
/// yönlendirme yapabilmek için kök Navigator anahtarı. Overlay, MaterialApp'in
/// `builder`'ında yaşadığı için normal `Navigator.of(context)` uygulamanın
/// Navigator'ını GÖREMEZ; bu anahtar üzerinden push edilir.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Global hak göstergesi (overlay pili) ANASAYFA KÖKÜNDE gizlenir — çünkü
/// anasayfanın kendi üst panelinde zaten hak çipi vardır; iki kez göstermeyelim.
/// MainShell, aktif sekme "home" ve o sekmede açık alt ekran yokken bunu true
/// yapar. Diğer tüm ekranlarda (testler hariç) pil görünür.
final ValueNotifier<bool> anasayfaKokunde = ValueNotifier<bool>(true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initFirebaseIfConfigured();
  final storage = StorageService();
  await storage.init();

  // TAZE KURULUM: Uygulama silinip yeniden kurulduğunda SharedPreferences
  // temizlenir ama iOS'ta Firebase oturumu KEYCHAIN'de kalır. Bu durumda
  // hesaptan otomatik çıkış yap — böylece kullanıcı "misafir" olarak açılışta
  // giriş seçeneğini görür; tekrar giriş yapınca istatistik + premium buluttan
  // geri gelir (bkz. AccountLoginScreen.syncDown). Kullanıcı isteği.
  var aktifKullanici =
      isFirebaseConfigured ? FirebaseAuth.instance.currentUser : null;
  if (storage.isFreshInstall()) {
    await storage.markInstalled();
    if (aktifKullanici != null) {
      try {
        await AuthService().signOut();
      } catch (_) {}
      aktifKullanici = null;
    }
  }

  // HESABA BAĞLI PROFİL: Önceki oturumdan kalıcı bir Google/Apple girişi
  // varsa, daha ilk kare çizilmeden o hesabın YEREL profiline geç — böylece
  // farklı hesaplar birbirinin istatistiklerini/premium'unu asla görmez
  // (bkz. StorageService.hesapProfilineGec).
  if (aktifKullanici != null && !aktifKullanici.isAnonymous) {
    await storage.hesapProfilineGec(aktifKullanici.uid);
  } else {
    // MİSAFİR GÜVENCESİ (kullanıcı isteği): Giriş yapmamış kullanıcı KESİNLİKLE
    // premium görünmesin. iOS'ta StoreKit aboneliği geri yükleyip misafir
    // profiline premium yazmış olabilir; açılışta misafir profilini free'ye
    // sabitle. (Gerçek premium, kullanıcı giriş yapınca buluttan geri gelir.)
    if (storage.isPremiumUser()) {
      await storage.setUserPlan('free');
    }
  }
  // Günlük Çalışma Planı hatırlatmaları için yerel bildirim altyapısını
  // hazırla. Desteklenmeyen platformlarda (web/masaüstü) ya da izin
  // verilmediğinde sessizce no-op olur — asla istisna fırlatmaz.
  await NotificationService.instance.initialize();

  // Ödüllü reklam SDK'sını başlat (yalnızca kullanıcı butona basınca reklam
  // çıkar — banner/geçiş yok). Açılışı yavaşlatmasın diye beklenmez; premium
  // kullanıcıya reklam hiç gösterilmez (çağrı yerlerinde kontrol edilir).
  // ignore: unawaited_futures
  AdService.instance.baslat();

  // KRİTİK — "izin verdim ama bildirim gelmiyor" düzeltmesi:
  // Android, uygulama YENİDEN KURULDUĞUNDA (yeni APK) planlanmış tüm
  // alarmları siler. Plan yerel kayıtta durduğu hâlde bildirimler bir daha
  // KURULMUYORDU; kullanıcı ancak plan ekranını açıp bir şey değiştirirse
  // yeniden kuruluyordu. Artık HER açılışta plan yeniden kaydediliyor
  // (schedulePlan önce eskileri iptal eder, çift bildirim oluşmaz).
  // Beklenmez (unawaited): açılışı yavaşlatmasın.
  // ignore: unawaited_futures
  NotificationService.instance
      .schedulePlan(StudyPlanService(storage).getActivePlan(), storage: storage)
      .catchError((e) => debugPrint('Açılışta bildirim kurulumu: $e'));

  // Günlük motivasyon: her akşam 18:00–20:00 arası rastgele bir saatte kısa bir
  // hatırlatma. Her açılışta yeniden kurulur (pencere ileriye kayar).
  // ignore: unawaited_futures
  NotificationService.instance
      .scheduleDailyMotivation(storage: storage)
      .catchError((e) => debugPrint('Açılışta motivasyon kurulumu: $e'));

  // Ders bildirimleri (kullanıcı isteği): kullanıcının eklediği ders/gün/saat
  // alarmları da her açılışta yeniden kurulur (yeniden kurulumdan sonra
  // Android'in sildiği alarmlar geri gelsin, çift kurulmasın).
  // Premium'a özel: yalnızca premium kullanıcıda kurulur. Premium biterse boş
  // liste geçilir → scheduleDersBildirimleri önce eskileri iptal eder, hiçbir
  // ders bildirimi kurulmaz.
  // ignore: unawaited_futures
  NotificationService.instance
      .scheduleDersBildirimleri(
          storage.isPremiumUser()
              ? DersBildirimService().getir(storage)
              : const [],
          storage: storage)
      .catchError((e) => debugPrint('Açılışta ders bildirimi kurulumu: $e'));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: storage),
        Provider<DataService>(create: (_) => DataService()),
        ChangeNotifierProvider<QuizEngine>(create: (_) => QuizEngine(storage)),
        ChangeNotifierProvider<TimerService>(create: (_) => TimerService()),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider(storage)),
        Provider<SoundService>(create: (_) => SoundService(storage)),
        ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
        Provider<RemoteQuestionService>(create: (_) => RemoteQuestionService()),
        ChangeNotifierProvider<TtsService>(create: (_) => TtsService()),
      ],
      child: const KpssApp(),
    ),
  );
}

class KpssApp extends StatelessWidget {
  const KpssApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      title: 'KPSS Hazırlık',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: themeProvider.themeData,
      // TÜM ekranların üstünde yaşayan bildirim katmanı: yeni mesaj /
      // arkadaşlık isteği geldiğinde üstten kayan afiş gösterir (test
      // sırasında erteler, uygulama arka plandaysa yerel bildirime düşer).
      // builder kullanıldığı için hangi ekran açık olursa olsun çalışır.
      builder: (context, child) =>
          InAppNoticeOverlay(child: child ?? const SizedBox.shrink()),
      home: const SplashScreen(),
    );
  }
}
