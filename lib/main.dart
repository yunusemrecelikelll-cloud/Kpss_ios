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
import 'services/notification_service.dart';
import 'theme/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initFirebaseIfConfigured();
  final storage = StorageService();
  await storage.init();
  // Günlük Çalışma Planı hatırlatmaları için yerel bildirim altyapısını
  // hazırla. Desteklenmeyen platformlarda (web/masaüstü) ya da izin
  // verilmediğinde sessizce no-op olur — asla istisna fırlatmaz.
  await NotificationService.instance.initialize();

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
      home: const SplashScreen(),
    );
  }
}
