import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/attempt.dart';
import '../models/question.dart';
import '../models/subject.dart';
import '../services/data_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import 'result_screen.dart' show motivationColorFor;
import 'subject_screen.dart';

/// Bir dersteki başarı oranı bu eşiğin ALTINDAYSA "zayıf" (çalışılması
/// gereken) konu olarak işaretlenir. %60, ResultScreen'deki motivasyon
/// renklerinin (bkz. motivationColorFor) de kullandığı "iyi/orta" sınırıyla
/// tutarlı bir eşik.
const int kWeakSubjectThreshold = 60;

/// "Beni Sına" analizinde tek bir dersin özet istatistiği.
class SubjectPlacementStat {
  final String subjectId;
  final String subjectAd;
  final String icon;
  final int correct;
  final int total;

  const SubjectPlacementStat({
    required this.subjectId,
    required this.subjectAd,
    required this.icon,
    required this.correct,
    required this.total,
  });

  int get rate => total == 0 ? 0 : ((correct / total) * 100).round();
  bool get isWeak => total > 0 && rate < kWeakSubjectThreshold;
}

/// Teşhis sınavı sonrası genel karşılama başlığı. Tek bir konu değil TÜM
/// sınavın genel sonucu için — bu yüzden ayrı bir fonksiyon.
///
/// CİNSİYETE GÖRE HİTAP KALDIRILDI (bkz. home_screen.dart'taki aynı not).
String placementHeadlineFor(String name, int overallRate) {
  if (overallRate >= 80) return '$name, harika başlangıç! 🌟 Genel olarak çok iyi durumdasın.';
  if (overallRate >= 60) return '$name, gayet iyi gidiyorsun! 💪 Birkaç konuya odaklanman yeterli.';
  return '$name, bu senin başlangıç noktan! 🌱 Aşağıdaki dersler senin için harika bir yol haritası.';
}

/// "Beni Sına" teşhis sınavı bitince gösterilen ders bazlı zayıf/güçlü analiz
/// ekranı. quiz_screen.dart _finish() içinde isPlacementExam bayrağı true
/// olduğunda ResultScreen yerine buraya yönlendirilir (bkz. quiz_screen.dart).
///
/// [questions], PlacementExamScreen'in QuizEngine'e VERDİĞİ orijinal soru
/// listesidir — her biri copyWith ile kendi subjectId/subjectAd'ini taşır.
/// QuizEngine.finish() review listesini bu questions listesiyle BİREBİR AYNI
/// sırada/uzunlukta üretir (bkz. quiz_engine.dart finish()), bu yüzden
/// Attempt/ReviewItem modeline dokunmadan (paralel çalışan diğer işlerle
/// çakışmamak için) burada indeks bazlı eşleştirme ile ders kırılımı
/// hesaplanabiliyor.
class PlacementResultScreen extends StatefulWidget {
  final Attempt result;
  final List<Question> questions;
  const PlacementResultScreen({super.key, required this.result, required this.questions});

  @override
  State<PlacementResultScreen> createState() => _PlacementResultScreenState();
}

class _PlacementResultScreenState extends State<PlacementResultScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markTaken());
  }

  Future<void> _markTaken() async {
    // Anasayfa'daki "Beni Sına" kartının bir dahaki açılışta agresif bir
    // şekilde tekrar tekrar davet etmek yerine daha sakin bir "Tekrar Dene"
    // görünümüne geçmesi için (bkz. home_screen.dart, storage_service.dart
    // hasProfile ile AYNI kalıcı bayrak deseni).
    await context.read<StorageService>().markPlacementExamTaken();
  }

  List<SubjectPlacementStat> _computeStats(List<Subject> subjects, DataService data) {
    final counts = <String, List<int>>{}; // subjectId -> [dogru, toplam]
    final order = <String>[];
    final review = widget.result.review;
    final n = review.length < widget.questions.length ? review.length : widget.questions.length;
    for (var i = 0; i < n; i++) {
      final q = widget.questions[i];
      final sid = q.subjectId ?? 'diger';
      final c = counts.putIfAbsent(sid, () {
        order.add(sid);
        return [0, 0];
      });
      c[1] = c[1] + 1;
      if (review[i].status == 'dogru') c[0] = c[0] + 1;
    }
    return [
      for (final sid in order)
        SubjectPlacementStat(
          subjectId: sid,
          subjectAd: data.subjectById(subjects, sid)?.ad ?? sid,
          icon: data.subjectById(subjects, sid)?.icon ?? '📘',
          correct: counts[sid]![0],
          total: counts[sid]![1],
        ),
    ]..sort((a, b) => a.rate.compareTo(b.rate)); // en zayıf ders en üstte
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final data = context.read<DataService>();
    final subjects = data.cachedSubjects;
    final c = context.watch<ThemeProvider>().colors;
    final result = widget.result;
    final stats = _computeStats(subjects, data);
    final name = storage.getActiveUser().isNotEmpty
        ? storage.getActiveUser()
        : (storage.getUserName().isNotEmpty ? storage.getUserName() : 'Aday');
    final headline = placementHeadlineFor(name, result.skor);
    final headlineColor = motivationColorFor(result.skor, c);

    return Scaffold(
      appBar: AppBar(title: const Text('Beni Sına — Sonuç')),
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
                    decoration: BoxDecoration(
                      color: headlineColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: headlineColor.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      headline,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: headlineColor),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('%${result.skor}', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
                  Text('${result.dogru} doğru • ${result.yanlis} yanlış • ${result.bos} boş — ${result.toplam} soru',
                      style: TextStyle(fontSize: 12.5, color: c.textFaint)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Ders Bazlı Analiz', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Her dersten birkaç soruyla hızlıca nerede güçlü, nerede eksik olduğunu gördük.',
            style: TextStyle(fontSize: 12, color: c.textFaint),
          ),
          const SizedBox(height: 12),
          for (final stat in stats) ...[
            _SubjectStatCard(
              stat: stat,
              colors: c,
              onFocus: () {
                final subject = data.subjectById(subjects, stat.subjectId);
                if (subject == null) return;
                context.read<SoundService>().click();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => SubjectScreen(subject: subject)));
              },
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () {
              context.read<SoundService>().click();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            child: const Text('Anasayfa'),
          ),
        ],
      ),
    );
  }
}

class _SubjectStatCard extends StatelessWidget {
  final SubjectPlacementStat stat;
  final KpssColors colors;
  final VoidCallback onFocus;
  const _SubjectStatCard({required this.stat, required this.colors, required this.onFocus});

  @override
  Widget build(BuildContext context) {
    final barColor = stat.isWeak ? colors.warn : colors.success;
    return Card(
      color: (stat.isWeak ? colors.warn : colors.mint).withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(stat.icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(stat.subjectAd,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                ),
                Text('${stat.correct}/${stat.total} • %${stat.rate}',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: barColor)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: stat.total == 0 ? 0 : stat.correct / stat.total,
                minHeight: 8,
                color: barColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              stat.isWeak
                  ? '📌 Bu konuda çalışman gerekiyor — ama endişelenme, biraz pratikle hızla toparlarsın!'
                  : '✅ Bu derste gayet iyisin, böyle devam!',
              style: TextStyle(fontSize: 12.5, color: colors.textDim),
            ),
            if (stat.isWeak) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: onFocus,
                child: const Text('Bu Derse Odaklan →'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
