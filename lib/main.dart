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
import 'services/notification_service.dart';
import 'services/study_plan_service.dart';
import 'theme/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'widgets/in_app_notice_overlay.dart';
import 'firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initFirebaseIfConfigured();
  final storage = StorageService();
  await storage.init();

  // HESABA BAĞLI PROFİL: Önceki oturumdan kalıcı bir Google/Apple girişi
  // varsa, daha ilk kare çizilmeden o hesabın YEREL profiline geç — böylece
  // farklı hesaplar birbirinin istatistiklerini/premium'unu asla görmez
  // (bkz. StorageService.hesapProfilineGec).
  final aktifKullanici =
      isFirebaseConfigured ? FirebaseAuth.instance.currentUser : null;
  if (aktifKullanici != null && !aktifKullanici.isAnonymous) {
    await storage.hesapProfilineGec(aktifKullanici.uid);
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
