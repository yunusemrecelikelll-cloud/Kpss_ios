import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/attempt.dart';
import '../models/badge.dart';
import '../services/data_service.dart';
import '../services/storage_service.dart';
import '../services/sound_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';

/// Skora göre değişen motivasyon mesajı.
///
/// CİNSİYETE GÖRE HİTAP KALDIRILDI (bkz. home_screen.dart'taki aynı not):
/// mesajlar eskiden kullanıcının cinsiyetine göre "Prenses"/"Aslanım" diye
/// sesleniyordu. Artık herkes aynı, adıyla hitap eden nötr mesajı görüyor.
String motivationMessageFor(String name, int skor) {
  if (skor >= 85) return '$name, muhteşem! 🌟 Bu konuyu tamamen kavramışsın!';
  if (skor >= 70) return '$name, çok iyi! 💪 Küçük eksiklerini gider, bu konu sende!';
  if (skor >= 50) return '$name, fena değil! 🌱 Biraz daha çalışırsan harika olacaksın.';
  return '$name, bu konu biraz zorluyordu ama sorun değil! 🤗 Anlatımı tekrar oku ve yeniden dene.';
}

/// Skor aralığına göre motivasyon kutusunun rengi (yeşil→kırmızı gradasyonu).
/// Temaya duyarlı olması için sabit Material renkleri yerine KpssColors kullanılır.
Color motivationColorFor(int skor, KpssColors c) {
  if (skor >= 85) return c.success;
  if (skor >= 70) return c.mint;
  if (skor >= 50) return c.warn;
  return c.danger;
}

class ResultScreen extends StatefulWidget {
  final Attempt result;
  const ResultScreen({super.key, required this.result});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBadges());
  }

  Future<void> _checkBadges() async {
    final storage = context.read<StorageService>();
    final subjects = context.read<DataService>().cachedSubjects;
    final newlyUnlocked = await checkAndUnlockBadges(storage, subjects);
    if (newlyUnlocked.isEmpty || !mounted) return;
    for (final b in newlyUnlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🏅 Yeni rozet: ${b.name}!'), duration: const Duration(seconds: 4)),
      );
    }
  }

  Attempt get result => widget.result;

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final c = context.watch<ThemeProvider>().colors;
    final premium = storage.isPremiumUser();
    final k = KpssPoints.compute(dogru: result.dogru, yanlis: result.yanlis);
    final name = storage.getActiveUser().isNotEmpty
        ? storage.getActiveUser()
        : (storage.getUserName().isNotEmpty ? storage.getUserName() : 'Aday');
    final motivation = motivationMessageFor(name, result.skor);
    final motivationColor = motivationColorFor(result.skor, c);

    return Scaffold(
      appBar: AppBar(title: const Text('Sonuç')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: motivationColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: motivationColor.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      motivation,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: motivationColor),
                    ),
                  ),
                  Text('%${result.skor}', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
                  Text('${result.subjectAd} • ${result.topicBaslik}'),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Stat(label: 'Doğru ✓', value: '${result.dogru}', color: c.success),
                      _Stat(label: 'Yanlış ✗', value: '${result.yanlis}', color: c.danger),
                      _Stat(label: 'Boş —', value: '${result.bos}', color: c.textFaint),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Net: ${k.net.toStringAsFixed(2)}'),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Stat(label: 'P3', value: '${k.p3}'),
                      _Stat(label: 'P93', value: '${k.p93}'),
                      _Stat(label: 'P94', value: '${k.p94}'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      context.read<SoundService>().click();
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                    child: const Text('Anasayfa'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Soru Soru Değerlendirme', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (var i = 0; i < result.review.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Chip(
                          label: Text(result.review[i].status == 'dogru'
                              ? 'Doğru ✓'
                              : result.review[i].status == 'yanlis'
                                  ? 'Yanlış ✗'
                                  : 'Boş'),
                          backgroundColor: result.review[i].status == 'dogru'
                              ? c.success.withValues(alpha: 0.15)
                              : result.review[i].status == 'yanlis'
                                  ? c.danger.withValues(alpha: 0.15)
                                  : null,
                        ),
                        const SizedBox(width: 8),
                        Text('Soru ${i + 1}'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(result.review[i].soru, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    for (var oi = 0; oi < result.review[i].secenekler.length; oi++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${String.fromCharCode(65 + oi)}) ${result.review[i].secenekler[oi]}',
                          style: TextStyle(
                            color: oi == result.review[i].dogruIndex
                                ? c.success
                                : oi == result.review[i].verilenIndex
                                    ? c.danger
                                    : null,
                            fontWeight: oi == result.review[i].dogruIndex ? FontWeight.w700 : null,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text('💡 ${result.review[i].aciklama}', style: const TextStyle(fontSize: 13)),
                    if (result.review[i].status == 'yanlis' && result.review[i].distractorAciklama != null) ...[
                      const SizedBox(height: 8),
                      if (premium)
                        Text('🤔 Büyük ihtimalle neden seçtin? ${result.review[i].distractorAciklama}',
                            style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic))
                      else
                        Text('Premium kullanıcılar için detaylı yanılgı analizi burada gösterilir.',
                            style: TextStyle(fontSize: 12, color: c.textFaint)),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _Stat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
