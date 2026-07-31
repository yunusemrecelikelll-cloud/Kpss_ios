import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subject.dart';
import '../models/topic.dart';
import '../models/question.dart';
import '../services/storage_service.dart';
import '../services/sound_service.dart';
import '../services/remote_question_service.dart';
import '../services/tts_service.dart';
import '../theme/design_system.dart';
import '../theme/subject_colors.dart';
import 'topic_screen.dart';
import 'quiz_screen.dart';
import '../utils/ust_bildirim.dart';

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
      ustBildirim('Yeterli soru yüklenemedi.', tur: UstBildirimTuru.hata);
      return;
    }

    // Ders sınavı da bir konu testi sayılır (isFullTest == false): SÜRE
    // SINIRI YOKTUR — süre sorulmaz, geri sayım kurulmaz. Ayarlar'daki süre
    // tercihi yalnızca 120 soruluk KPSS genel denemesi için geçerlidir.
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
    final completed = storage.getCompletedTopics();
    final examQCount = subject.konular.length * kSubjectExamQPerTopic;
    final subjectPalette = subjectPaletteFor(subject.id);

    // GRUPLAMA (kullanıcı isteği): grup kimliği olan konular (ör. paragraf)
    // ders listesinde TEK bir başlık altında toplanır; dokununca alt konuların
    // olduğu bir sayfa açılır. Grupsuz konular doğrudan listelenir.
    final gruplanmamis = <Topic>[];
    final gruplar = <String, List<Topic>>{};
    for (final t in subject.konular) {
      if (t.grup == null) {
        gruplanmamis.add(t);
      } else {
        (gruplar[t.grup!] ??= <Topic>[]).add(t);
      }
    }
    final grupKeys = gruplar.keys.toList();
    final satirSayisi = gruplanmamis.length + grupKeys.length;

    return Scaffold(
      appBar: AppBar(title: Text('${subject.icon} ${subject.ad}')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        // 0: ders sınavı hero, 1: "Konular" başlığı, sonrası konu + grup satırları.
        itemCount: satirSayisi + 2,
        separatorBuilder: (_, _) => const SizedBox(height: kDsGap),
        itemBuilder: (context, i) {
          if (i == 0) {
            return DsHeroCard(
              overline: '${subject.ad.toUpperCase()} SINAVI',
              emoji: subject.icon,
              title: '$examQCount soru (her konudan $kSubjectExamQPerTopic)',
              subtitle: 'Bilgini test et, eksiklerini tamamla!',
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
          final topicPalette = topicPaletteFor(subject.id, index);

          // Önce grupsuz konular, sonra grup satırları.
          if (index < gruplanmamis.length) {
            final t = gruplanmamis[index];
            final done = completed[t.id] == true;
            final best = storage.getBestScore(t.id);
            return DsListRow(
              emoji: done ? '✅' : subject.icon,
              index: index + 1,
              title: t.baslik,
              status: best != null ? '⭐ %$best en iyi' : '🔒 Henüz çözülmedi',
              accent: topicPalette.a,
              onTap: () {
                context.read<SoundService>().click();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TopicScreen(subject: subject, topic: t)));
              },
            );
          }

          // Grup satırı (ör. Paragraf) → alt konular sayfasını açar.
          final grup = grupKeys[index - gruplanmamis.length];
          final grupKonulari = gruplar[grup]!;
          return DsListRow(
            emoji: _grupEmoji(grup),
            index: index + 1,
            title: _grupBaslik(grup),
            status: '${grupKonulari.length} alt konu • anlatım + testler',
            accent: topicPalette.a,
            onTap: () {
              context.read<SoundService>().click();
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _KonuGrupScreen(
                        subject: subject,
                        baslik: _grupBaslik(grup),
                        emoji: _grupEmoji(grup),
                        konular: grupKonulari,
                      )));
            },
          );
        },
      ),
    );
  }

  static String _grupBaslik(String grup) =>
      switch (grup) { 'paragraf' => 'Paragraf', _ => grup };
  static String _grupEmoji(String grup) =>
      switch (grup) { 'paragraf' => '📄', _ => '📚' };
}

/// Bir konu GRUBUNUN (ör. Paragraf) alt konularını listeleyen sayfa — ders
/// ekranıyla aynı dilde (DsListRow → TopicScreen). Her alt konunun kendi
/// anlatımı ve testleri vardır.
class _KonuGrupScreen extends StatelessWidget {
  final Subject subject;
  final String baslik;
  final String emoji;
  final List<Topic> konular;
  const _KonuGrupScreen({
    required this.subject,
    required this.baslik,
    required this.emoji,
    required this.konular,
  });

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final completed = storage.getCompletedTopics();
    return Scaffold(
      appBar: AppBar(title: Text('$emoji $baslik')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: konular.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: kDsGap),
        itemBuilder: (context, i) {
          if (i == 0) return DsSectionHeader(title: '$baslik Konuları');
          final index = i - 1;
          final t = konular[index];
          final done = completed[t.id] == true;
          final best = storage.getBestScore(t.id);
          final topicPalette = topicPaletteFor(subject.id, index);
          return DsListRow(
            emoji: done ? '✅' : emoji,
            index: index + 1,
            title: t.baslik,
            status: best != null ? '⭐ %$best en iyi' : '🔒 Henüz çözülmedi',
            accent: topicPalette.a,
            onTap: () {
              context.read<SoundService>().click();
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TopicScreen(subject: subject, topic: t)));
            },
          );
        },
      ),
    );
  }
}
