import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';
import 'quiz_screen.dart';
import 'premium_screen.dart';

/// JS karşılığı: renderWrongBank() (src/js/app.js).
class WrongBankScreen extends StatefulWidget {
  const WrongBankScreen({super.key});

  @override
  State<WrongBankScreen> createState() => _WrongBankScreenState();
}

class _WrongBankScreenState extends State<WrongBankScreen> {
  void _startWrongTest(BuildContext context, List<Map<String, dynamic>> bank) {
    final shuffled = List<Map<String, dynamic>>.of(bank)..shuffle();
    final qs = shuffled.take(20).map((w) => Question(
          soru: w['soru'] as String,
          secenekler: List<String>.from(w['secenekler'] as List),
          dogruIndex: w['dogruIndex'] as int,
          aciklama: w['aciklama'] as String? ?? '',
          distractorAciklama: w['distractorAciklama'] as String?,
          kaynak: w['kaynak'] as String?,
        )).toList();
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => QuizScreen(
        subjectId: 'wrong',
        subjectAd: 'Yanlışlarım',
        topicId: 'wrong-bank',
        topicBaslik: 'Yanlışlar Testi',
        questions: qs,
        isFullTest: false,
        isWrongBankMode: true,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final c = context.watch<ThemeProvider>().colors;
    final premium = storage.isPremiumUser();

    if (!premium) {
      return Scaffold(
        appBar: AppBar(title: const Text('🔒 Yanlışlarım')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bu bölüm sadece Premium kullanıcılar için aktif.',
                  style: TextStyle(fontSize: 14.5)),
              const SizedBox(height: 14),
              Text(
                'Yanlış sorularının özel testlerine erişmek, hatalarını hedeflemek ve '
                'hata analizini derinleştirmek için Premium planına geç.',
                style: TextStyle(color: c.textFaint, height: 1.6),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () {
                  context.read<SoundService>().click();
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                },
                child: const Text("Premium'a Geç"),
              ),
            ],
          ),
        ),
      );
    }

    final bank = storage.getWrongBank();
    if (bank.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('❌ Yanlışlarım')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('🌟 Yanlış sorular bankan boş! Harika gidiyorsun.',
                textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final q in bank) {
      final ad = q['subjectAd'] as String? ?? 'Diğer';
      (grouped[ad] ??= []).add(q);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('❌ Yanlışlarım')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('${bank.length} soru birikmiş', style: TextStyle(color: c.textFaint)),
            const SizedBox(height: 12),
            for (final entry in grouped.entries)
              Card(
                child: ListTile(
                  title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: Text('${entry.value.length} yanlış',
                      style: TextStyle(color: c.danger, fontWeight: FontWeight.w700)),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      context.read<SoundService>().click();
                      _startWrongTest(context, bank);
                    },
                    child: const Text('Yanlışlarımı Sına →'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () async {
                    context.read<SoundService>().click();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        content: const Text('Tüm yanlış soru bankasını temizlemek istiyor musun?'),
                        actions: [
                          TextButton(
                            onPressed: () {
                              context.read<SoundService>().click();
                              Navigator.pop(ctx, false);
                            },
                            child: const Text('Vazgeç'),
                          ),
                          TextButton(
                            onPressed: () {
                              context.read<SoundService>().click();
                              Navigator.pop(ctx, true);
                            },
                            child: const Text('Temizle'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) await storage.clearWrongBank();
                  },
                  child: const Text('Bankayı Temizle'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
