import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subject.dart';
import '../models/question.dart';
import '../services/storage_service.dart';
import '../services/sound_service.dart';
import '../services/remote_question_service.dart';
import '../services/tts_service.dart';
import '../theme/design_system.dart';
import '../theme/subject_colors.dart';
import 'topic_screen.dart';
import 'quiz_screen.dart';

class SubjectScreen extends StatefulWidget {
  final Subject subject;
  const SubjectScreen({super.key, required this.subject});

  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> with WidgetsBindingObserver {
  Subject get subject => widget.subject;
  bool _startingExam = false;
  // dispose()'ta context.read güvenli olmadığından TTS referansı initState'te
  // yakalanır (madde 2).
  late final TtsService _ttsService;

  @override
  void initState() {
    super.initState();
    _ttsService = context.read<TtsService>();
    WidgetsBinding.instance.addObserver(this);
    // Başka bir konudan bu ekrana dönüldüyse orada başlamış sesli anlatım
    // burada çalmaya devam etmesin.
    _ttsService.stopNow();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ttsService.stopNow();
    super.dispose();
  }

  /// Uygulama arka plana gidince sesli anlatım sussun.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) _ttsService.stopNow();
  }

  // Not: State.context kullanılır (parametre olarak ayrı bir BuildContext
  // almaz) — böylece `mounted` kontrolü ile aynı context güvenle eşleşir.
  Future<void> _startSubjectExam() async {
    // Madde 2: sınava girerken sesli anlatım kesin olarak dursun.
    _ttsService.stopNow();
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

    // Madde 1: sınav süresini kullanıcı kendisi belirler (elle dakika ya da
    // "soru başına saniye" preset'i). Vazgeçerse sınav açılmaz.
    final sureSn = await showTestSuresiDialog(context, allQs.length);
    if (sureSn == null || !mounted) return;

    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => QuizScreen(
        subjectId: subject.id,
        subjectAd: subject.ad,
        topicId: '${subject.id}-sinav',
        topicBaslik: '${subject.ad} Sınavı',
        questions: allQs,
        isFullTest: false,
        durationSec: sureSn,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final completed = storage.getCompletedTopics();
    final examQCount = subject.konular.length * kSubjectExamQPerTopic;
    final subjectPalette = subjectPaletteFor(subject.id);

    return Scaffold(
      appBar: AppBar(title: Text('${subject.icon} ${subject.ad}')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        // 0: ders sınavı hero kartı, 1: "Konular" bölüm başlığı, sonrası konular.
        itemCount: subject.konular.length + 2,
        separatorBuilder: (_, _) => const SizedBox(height: kDsGap),
        itemBuilder: (context, i) {
          if (i == 0) {
            return DsHeroCard(
              overline: '${subject.ad.toUpperCase()} SINAVI',
              emoji: subject.icon,
              // Soru sayısı mevcut hesaplamadan gelir (konu sayısı × konu başına soru).
              title: '$examQCount soru (her konudan $kSubjectExamQPerTopic)',
              subtitle: 'Bilgini test et, eksiklerini tamamla!',
              // Yükleme sürerken buton pasifleşsin ve etiket durumu bildirsin.
              actionLabel: _startingExam ? 'Hazırlanıyor…' : 'Sınava Gir',
              accent: subjectPalette.a,
              accent2: subjectPalette.b,
              illustrationEmoji: '🗂️',
              onAction: _startingExam
                  ? null
                  : () {
                      context.read<SoundService>().click();
                      _startSubjectExam();
                    },
            );
          }
          if (i == 1) {
            return const DsSectionHeader(title: 'Konular');
          }
          final index = i - 2;
          final t = subject.konular[index];
          final done = completed[t.id] == true;
          final best = storage.getBestScore(t.id);
          // Her satır dersin paletinden türeyen, sıraya göre hafifçe kayan bir
          // vurgu rengi alır — liste tekdüze görünmesin.
          final topicPalette = topicPaletteFor(subject.id, index);
          return DsListRow(
            emoji: done ? '✅' : subject.icon,
            index: index + 1,
            title: t.baslik,
            status: best != null ? '⭐ %$best en iyi' : '🔒 Henüz çözülmedi',
            accent: topicPalette.a,
            onTap: () {
              context.read<SoundService>().click();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => TopicScreen(subject: subject, topic: t)),
              );
            },
          );
        },
      ),
    );
  }
}
