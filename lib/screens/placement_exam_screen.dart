import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../models/subject.dart';
import '../services/remote_question_service.dart';
import '../theme/theme_provider.dart';
import 'quiz_screen.dart';

/// "Beni Sına" teşhis (yerleştirme) sınavında her dersten kaç soru
/// sorulacağını belirler. Tam Deneme Sınavı'ndaki (bkz. subject.dart
/// kFullTestDist, 120 soru) gerçek KPSS ağırlıklarıyla ORANTILI ama çok daha
/// kısa bir seçki — kullanıcıyı yormadan (~30 soru, birkaç dakika) her
/// dersten en azından birkaç örnek soru görmesini sağlar.
const Map<String, int> kPlacementExamDist = {
  'turkce': 6,
  'matematik': 6,
  'tarih': 6,
  'cografya': 5,
  'vatandaslik': 4,
  'guncel': 3,
};

const String kPlacementExamTopicId = 'placement-exam';

/// "Beni Sına" — Anasayfa'daki (bkz. home_screen.dart _BeniSinaCard) kısa
/// teşhis sınavına giriş ekranı. Kullanıcıya bir yükleniyor göstergesi
/// gösterirken arka planda her dersten [kPlacementExamDist] kadar soru
/// örnekler (Tam Deneme Sınavı'nda home_screen._startFullTest'in kullandığı
/// AYNI örnekleme deseni: RemoteQuestionService.getPool + karıştır + al),
/// sonra karma soru listesiyle mevcut QuizScreen'i (isPlacementExam: true)
/// başlatır. Test bitince quiz_screen.dart bu bayrağa bakıp PlacementResultScreen'e
/// yönlendirir (bkz. quiz_screen.dart _finish()).
class PlacementExamScreen extends StatefulWidget {
  final List<Subject> subjects;
  const PlacementExamScreen({super.key, required this.subjects});

  @override
  State<PlacementExamScreen> createState() => _PlacementExamScreenState();
}

class _PlacementExamScreenState extends State<PlacementExamScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareAndStart());
  }

  Future<void> _prepareAndStart() async {
    final remote = context.read<RemoteQuestionService>();
    final rng = Random();
    final allQs = <Question>[];
    for (final s in widget.subjects) {
      final n = kPlacementExamDist[s.id] ?? 0;
      if (n == 0 || s.konular.isEmpty) continue;
      final pool = <Question>[];
      for (final t in s.konular) {
        final havuz = await remote.getPool(t.id, t.sorular);
        for (final q in havuz) {
          pool.add(q.copyWith(subjectId: s.id, subjectAd: s.ad));
        }
      }
      pool.shuffle(rng);
      allQs.addAll(pool.take(n));
    }
    // Sorular ders bloğu halinde eklendi (önce tüm Türkçe, sonra tüm
    // Matematik...) — deneyimin tek düze olmaması için genel sırayı karıştır.
    // NOT: PlacementResultScreen analizi bu KARIŞIK sırayla da doğru çalışır,
    // çünkü her sorunun kendi subjectId'si üzerinden eşleştirme yapılır
    // (indeks sırasına değil).
    allQs.shuffle(rng);
    if (!mounted) return;
    if (allQs.length < 10) {
      setState(() => _error = 'Şu an yeterli soru yüklenemedi. Lütfen daha sonra tekrar dene.');
      return;
    }
    Navigator.of(context, rootNavigator: true).pushReplacement(MaterialPageRoute(
      builder: (_) => QuizScreen(
        subjectId: 'placement',
        subjectAd: 'Beni Sına',
        topicId: kPlacementExamTopicId,
        topicBaslik: 'Beni Sına — Seviye Tespit Sınavı',
        questions: allQs,
        isFullTest: false,
        isPlacementExam: true,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Beni Sına')),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.textDim)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Geri Dön'),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🎯', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Senin için sorular hazırlanıyor...', style: TextStyle(color: c.textDim)),
                ],
              ),
      ),
    );
  }
}
