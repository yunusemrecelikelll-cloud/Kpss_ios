import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';
import 'tools_hub_screen.dart';

class MentorTip {
  final String title;
  final String text;
  const MentorTip(this.title, this.text);
}

/// JS: MENTOR_TIPS — birebir taşındı.
const List<MentorTip> kMentorTips = [
  MentorTip(
    '⏳ Zaman Yönetimi',
    'Sınavda bir soruya 60-70 saniyeden fazla takılma. Emin olamadığın soruyu işaretleyip geç, '
        'tur sonunda geri dön.',
  ),
  MentorTip(
    '🎯 Eleme Tekniği',
    "Doğru şıkkı bilmesen bile önce kesin yanlış olan şıkları ele. 5 şıktan 2'sini eleyip kalanlar "
        'arasından seçmek isabet oranını ciddi artırır.',
  ),
  MentorTip(
    '📉 Zayıf Konuya Öncelik Ver',
    'Profil sayfandaki "çalışman gereken ders" önerisini haftada en az 2 kez tekrar et; '
        'en çok net, en zayıf dersten gelir.',
  ),
  MentorTip(
    '🧪 Deneme Ritmi',
    'Haftada en az 1 tam deneme çöz ve gerçek sınav saatinde, gerçek süre baskısıyla otur. '
        'Zamana alışmak kadar önemli bir şey yok.',
  ),
  MentorTip(
    '🔁 Yanlış Tekrarı',
    'Her denemeden sonra yanlışlarını 24 saat içinde tekrar et. Unutma eğrisi en hızlı ilk gün işler.',
  ),
  MentorTip(
    '😴 Sınav Öncesi Bakım',
    'Sınavdan önceki gece erken yat, ağır yemekten kaçın. Dinlenmiş beyin, ezberden çok daha iyi '
        'çıkarım yapar.',
  ),
];

/// Mentörlük Seansları — JS: renderMentor.
class MentorScreen extends StatelessWidget {
  const MentorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    if (!storage.isPremiumUser()) {
      return const LockedFeatureCard(
        title: 'Mentörlük Seansları',
        desc: "Sınav stratejileri ve haftalık çalışma planı önerileri için Premium'a geç.",
      );
    }

    final c = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(title: const Text('🎓 Mentörlük Seansları')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            // NOT: Buradaki "yakında canlı mentörlük açılacak" vaadi kaldırıldı.
            // Ekran premium'a kapalı; ücretli bir özellikte var olmayan bir
            // şeyi vaat etmek hem App Store Guideline 2.1 hem Play'in
            // yanıltıcı satın alma değerlendirmesi açısından risklidir.
            'Sınavda işine yarayacak, denenmiş çalışma stratejileri.',
            style: TextStyle(fontSize: 13, color: c.textFaint),
          ),
          const SizedBox(height: 16),
          for (final t in kMentorTips)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    const SizedBox(height: 6),
                    Text(t.text, style: const TextStyle(fontSize: 13, height: 1.4)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
