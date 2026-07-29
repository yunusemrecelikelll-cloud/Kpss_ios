import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/attempt.dart';
import '../models/subject.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';
import 'tools_hub_screen.dart';

/// "Bugün Sınava Girsen Kaç Alırsın?" — JS: renderPredictor.
/// Geçmiş ders/konu testlerindeki başarı oranı, 120 soruluk tam deneme dağılımına (kFullTestDist)
/// uygulanarak tahmini bir KPSS puanı hesaplanır.
class PredictorScreen extends StatelessWidget {
  const PredictorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    if (!storage.isPremiumUser()) {
      return const LockedFeatureCard(
        title: 'Bugün Sınava Girsen Kaç Alırsın?',
        desc: "Geçmiş performansına göre tahmini KPSS puanını görmek için Premium'a geç.",
      );
    }

    final overall = storage.computeOverall();
    if (overall.tests < 1) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('🎯  Tahmin üretmek için önce birkaç test çöz.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final overallRate = overall.rate / 100;
    var dogru = 0, yanlis = 0;
    kFullTestDist.forEach((sid, n) {
      final avg = storage.computeSubjectAvg(sid);
      final rate = avg != null ? avg / 100 : overallRate;
      final d = (n * rate).round();
      dogru += d;
      yanlis += (n - d);
    });
    final k = KpssPoints.compute(dogru: dogru, yanlis: yanlis, toplam: dogru + yanlis);
    final c = context.watch<ThemeProvider>().colors;

    return Scaffold(
      appBar: AppBar(title: const Text('🎯 Bugün Sınava Girsen Kaç Alırsın?')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Geçmiş test performansına dayanan tahmini bir hesaplamadır, gerçek sınav sonucu farklı olabilir.',
            style: TextStyle(fontSize: 13, color: c.textFaint),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tahmini Net: ${k.net.toStringAsFixed(2)} ($dogru doğru / $yanlis yanlış — 120 soru üzerinden)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _ScoreTile(label: 'P3', value: k.p3),
                      _ScoreTile(label: 'P93', value: k.p93),
                      _ScoreTile(label: 'P94', value: k.p94),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'Bu tahmin, çözdüğün konu/ders testlerindeki ders bazlı başarı oranların 120 soruluk tam '
                'deneme dağılımına uygulanarak hesaplanır. Daha çok test çöz, tahmin daha isabetli olsun.',
                style: TextStyle(fontSize: 12.5, color: c.textFaint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreTile extends StatelessWidget {
  final String label;
  final int value;
  const _ScoreTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('$value', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      ],
    );
  }
}
