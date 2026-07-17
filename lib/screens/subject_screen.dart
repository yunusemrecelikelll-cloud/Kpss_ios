import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subject.dart';
import '../models/question.dart';
import '../services/storage_service.dart';
import '../services/sound_service.dart';
import '../services/remote_question_service.dart';
import '../theme/subject_colors.dart';
import '../theme/theme_provider.dart';
import 'topic_screen.dart';
import 'quiz_screen.dart';

class SubjectScreen extends StatefulWidget {
  final Subject subject;
  const SubjectScreen({super.key, required this.subject});

  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  Subject get subject => widget.subject;
  bool _startingExam = false;

  Future<void> _startSubjectExam(BuildContext context) async {
    setState(() => _startingExam = true);
    final remote = context.read<RemoteQuestionService>();
    final rng = Random();
    final allQs = <Question>[];
    for (final t in subject.konular) {
      final havuz = await remote.getPool(t.id, t.sorular);
      final pool = List<Question>.of(havuz)..shuffle(rng);
      allQs.addAll(pool.take(kSubjectExamQPerTopic).map((q) => q.copyWith(topicBaslik: t.baslik)));
    }
    if (!mounted) return;
    setState(() => _startingExam = false);
    if (allQs.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Yeterli soru yüklenemedi.')));
      return;
    }
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => QuizScreen(
        subjectId: subject.id,
        subjectAd: subject.ad,
        topicId: '${subject.id}-sinav',
        topicBaslik: '${subject.ad} Sınavı',
        questions: allQs,
        isFullTest: false,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final c = context.watch<ThemeProvider>().colors;
    final completed = storage.getCompletedTopics();
    final examQCount = subject.konular.length * kSubjectExamQPerTopic;
    final subjectPalette = subjectPaletteFor(subject.id);

    return Scaffold(
      appBar: AppBar(title: Text('${subject.icon} ${subject.ad}')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: subject.konular.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Container(
              decoration: subjectCardDecoration(palette: subjectPalette, isLight: c.isLight),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: ListTile(
                  title: Text('📝 ${subject.ad} Sınavı', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('$examQCount soru (her konudan $kSubjectExamQPerTopic)'),
                  trailing: ElevatedButton(
                    onPressed: _startingExam
                        ? null
                        : () {
                            context.read<SoundService>().click();
                            _startSubjectExam(context);
                          },
                    child: _startingExam
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sınava Gir'),
                  ),
                ),
              ),
            );
          }
          final t = subject.konular[i - 1];
          final done = completed[t.id] == true;
          final best = storage.getBestScore(t.id);
          final topicPalette = topicPaletteFor(subject.id, i - 1);
          return Container(
            decoration: subjectCardDecoration(palette: topicPalette, isLight: c.isLight),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: done ? c.success.withValues(alpha: 0.2) : topicPalette.a.withValues(alpha: 0.25),
                  child: Text(done ? '✓' : '$i'),
                ),
                title: Text(t.baslik, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(best != null ? '%$best en iyi' : 'Henüz çözülmedi'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  context.read<SoundService>().click();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => TopicScreen(subject: subject, topic: t)),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
