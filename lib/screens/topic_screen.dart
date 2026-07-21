import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/link.dart';
import '../models/attempt.dart';
import '../models/subject.dart';
import '../models/topic.dart';
import '../models/question.dart';
import '../data/teachers.dart';
import '../services/data_service.dart';
import '../services/remote_question_service.dart';
import '../services/storage_service.dart';
import '../services/question_picker.dart';
import '../services/sound_service.dart';
import '../services/tts_service.dart';
import '../services/timer_service.dart';
import '../services/pdf_export_service.dart';
import '../theme/app_theme.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';
import 'quiz_screen.dart';
import 'premium_screen.dart';

const int kFreeMaxAttemptsPerTopic = 2;

/// Türkçe kısa ay adları — "12 Tem 2026" biçimi için.
const List<String> _kAylarKisa = [
  'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
  'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
];

/// Geçmiş test satırlarında gösterilen kısa tarih.
/// Bugünse "Bugün", dünse "Dün", değilse "12 Tem 2026".
String _kisaTarih(DateTime t) {
  final now = DateTime.now();
  final bugun = DateTime(now.year, now.month, now.day);
  final gun = DateTime(t.year, t.month, t.day);
  final fark = bugun.difference(gun).inDays;
  if (fark == 0) return 'Bugün';
  if (fark == 1) return 'Dün';
  return '${t.day} ${_kAylarKisa[t.month - 1]} ${t.year}';
}

/// Paragraf kutucuklarında sırayla dönen rozet emojileri.
const _kParagraphEmojis = ['📖', '✏️', '🔍', '🎯', '💭', '📝', '🧭', '🧩'];

/// Anahtar nokta kutucuklarında, metnin başında emoji yoksa kullanılacak yedek emojiler.
const _kKeyPointFallbackEmojis = ['🔑', '💡', '⭐', '🎯'];

class TopicScreen extends StatefulWidget {
  final Subject subject;
  final Topic topic;
  const TopicScreen({super.key, required this.subject, required this.topic});

  @override
  State<TopicScreen> createState() => _TopicScreenState();
}

class _TopicScreenState extends State<TopicScreen> with WidgetsBindingObserver {
  bool _startingQuiz = false;
  late final TtsService _ttsService;
  // dispose()'ta context.read güvenli olmadığından depolama referansı da
  // initState'te yakalanır.
  late final StorageService _storageService;

  // ── Çalışma süresi sayacı (madde 4) ──
  // Konu ekranında geçirilen süre üstte canlı gösterilir ve ekrandan
  // çıkılırken mevcut istatistik altyapısına (StorageService.addStudyTime —
  // Çalışma Kronometresi ile aynı alan) yazılır.
  final Stopwatch _studySw = Stopwatch();
  Timer? _studyTicker;
  bool _studySaved = false;
  /// Bu konudan açılan test ekranı hâlâ üstte mi? Öyleyse buradaki sayaç
  /// duraklatılmış kalmalı (aynı süre iki kez kaydedilmesin) — uygulama arka
  /// plandan geri dönse bile yeniden başlatılmaz.
  bool _quizAcik = false;

  Subject get subject => widget.subject;
  Topic get topic => widget.topic;

  @override
  void initState() {
    super.initState();
    // Konu ekranı açılır açılmaz bu konunun tam soru havuzunu arka planda
    // sessizce indirmeye başla (bkz. RemoteQuestionService) — kullanıcı
    // anlatımı okurken indirme tamamlanır, "Teste Başla" anında hazır olur.
    context.read<RemoteQuestionService>().prefetch(topic.id);
    _ttsService = context.read<TtsService>();
    _storageService = context.read<StorageService>();
    WidgetsBinding.instance.addObserver(this);

    // Başka bir konudan/ekrandan gelinmiş olabilir — orada başlatılmış bir
    // sesli anlatım varsa burada devam etmesin (madde 2).
    _ttsService.stopNow();

    _studySw.start();
    _studyTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _studyTicker?.cancel();
    _saveStudyTime();
    // Kullanıcı sesli anlatımı dinlerken ekrandan ayrılırsa konuşmayı durdur.
    _ttsService.stopNow();
    super.dispose();
  }

  /// Uygulama arka plana gidince sesli anlatım sussun ve çalışma süresi sayacı
  /// duraklasın — çalışılmayan süre kaydedilmesin (madde 2 + 4).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final arkaPlanda = state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (arkaPlanda) {
      _ttsService.stopNow();
      _studySw.stop();
    } else if (state == AppLifecycleState.resumed && !_quizAcik) {
      _studySw.start();
    }
  }

  /// Bu ekranda geçen süreyi ders bazlı çalışma süresine ekler (tek kez).
  void _saveStudyTime() {
    if (_studySaved) return;
    _studySaved = true;
    _studySw.stop();
    final sn = _studySw.elapsed.inSeconds;
    if (sn <= 0) return;
    // ignore: unawaited_futures
    _storageService.addStudyTime(subject.id, sn);
  }

  /// Özet + paragraflar + anahtar noktaları tek, akıcı bir metin haline
  /// getirir (sesli anlatım için).
  String _speechText(Anlatim a) {
    final buffer = StringBuffer();
    if (a.ozet != null && a.ozet!.trim().isNotEmpty) {
      buffer.writeln(a.ozet!.trim());
      buffer.writeln();
    }
    for (final paragraf in a.icerik) {
      final t = paragraf.trim();
      if (t.isEmpty) continue;
      buffer.writeln(t);
      buffer.writeln();
    }
    if (a.anahtarNoktalar.isNotEmpty) {
      buffer.writeln('Anahtar noktalar.');
      for (final k in a.anahtarNoktalar) {
        final t = k.trim();
        if (t.isEmpty) continue;
        buffer.writeln(t);
      }
    }
    return buffer.toString().trim();
  }

  Future<void> _exportPdf(BuildContext context) async {
    context.read<SoundService>().click();
    final storage = context.read<StorageService>();
    final count = storage.getPdfExportCount(topic.id);
    // İlk indirişte (count == 0) konu anlatımı dahil; sonrakilerde sadece
    // farklı sorular.
    final includeLecture = count == 0;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PDF oluşturuluyor…'), duration: Duration(seconds: 2)),
    );
    try {
      final pool = await context
          .read<RemoteQuestionService>()
          .getPool(topic.id, topic.sorular);
      final sorular = _pick20(pool, count);
      await PdfExportService.exportTopic(
        subject: subject.meta,
        topic: topic,
        sorular: sorular,
        includeLecture: includeLecture,
      );
      await storage.incrementPdfExportCount(topic.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF oluşturulamadı: $e')),
      );
    }
  }

  /// Havuzdan 20 soru seçer; her indirişte (count arttıkça) kayan bir pencere
  /// alınır ki tekrar indirince farklı sorular gelsin.
  List<Question> _pick20(List<Question> pool, int count) {
    const n = 20;
    if (pool.isEmpty) return const <Question>[];
    if (pool.length <= n) return List.of(pool);
    final start = (count * n) % pool.length;
    return [for (var k = 0; k < n; k++) pool[(start + k) % pool.length]];
  }

  Future<void> _startQuiz(BuildContext context, StorageService storage, bool premium) async {
    context.read<SoundService>().click();
    // Madde 2: teste girerken sesli anlatım kesin olarak dursun.
    _ttsService.stopNow();
    setState(() => _startingQuiz = true);
    final pool = await context.read<RemoteQuestionService>().getPool(topic.id, topic.sorular);
    if (!context.mounted) return;
    setState(() => _startingQuiz = false);
    final picker = QuestionPicker(storage);
    final qs = picker.pickForTopic(pool, 10, topic.id, premium: premium);

    // Konu testlerinde SÜRE SINIRI YOKTUR: ne süre sorulur ne de geri sayım
    // kurulur (durationSec verilmez). Ayarlar'daki süre tercihi yalnızca
    // deneme/tam sınav için geçerlidir. Not: aşağıdaki çalışma süresi sayacı
    // bir sınır değil, istatistik olduğu için çalışmaya devam eder.

    // Madde 4: test ekranı kendi süresini saydığı için buradaki sayaç
    // duraklatılır — aynı süre iki kez kaydedilmesin.
    _studySw.stop();
    _quizAcik = true;
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => QuizScreen(
        subjectId: subject.id,
        subjectAd: subject.ad,
        topicId: topic.id,
        topicBaslik: topic.baslik,
        questions: qs,
        isFullTest: false,
      ),
    ));
    _quizAcik = false;
    if (!mounted) return;
    _studySw.start();
  }

  /// Bu konuda çözülmüş TÜM geçmiş testleri ayrı bir ekranda listeler.
  void _tumTestleriAc(List<Attempt> attempts) {
    context.read<SoundService>().click();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _TumGecmisTestlerScreen(
        topicBaslik: topic.baslik,
        attempts: attempts,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final colors = context.watch<ThemeProvider>().colors;
    final premium = storage.isPremiumUser();
    final attempts = storage.getAttemptsForTopic(topic.id);
    final maxAtt = premium ? 1 << 30 : kFreeMaxAttemptsPerTopic;
    final maxed = attempts.length >= maxAtt;
    // Geçmiş testler listesi yalnızca SON 3'ü gösterir; tamamı detay ekranında.
    const gecmisOnizlemeAdedi = 3;
    final tumunuGor = attempts.length > gecmisOnizlemeAdedi;
    final sonUcBaslangic = tumunuGor ? attempts.length - gecmisOnizlemeAdedi : 0;
    final a = topic.anlatim;
    final teachers = kTeachersBySubject[subject.id] ?? const <Teacher>[];

    return Scaffold(
      appBar: AppBar(
        title: Text('📘 ${topic.baslik}'),
        // Madde 4: konu ekranında da üstteki zaman sayacı işler — burada
        // geçirilen süre ders bazlı çalışma süresine eklenir.
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    TimerService.format(_studySw.elapsed.inSeconds),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (a.ozet != null || a.icerik.isNotEmpty) ...[
            _TtsListenButton(text: _speechText(a), colors: colors),
            const SizedBox(height: 16),
          ],
          if (a.ozet != null) ...[
            _SummaryBox(text: a.ozet!, colors: colors),
            const SizedBox(height: 18),
          ],
          if (a.icerik.isNotEmpty) ...[
            const DsSectionHeader(title: '📚 Konu Anlatımı'),
            const SizedBox(height: 10),
            for (var i = 0; i < a.icerik.length; i++) ...[
              _ParagraphCard(
                index: i,
                text: a.icerik[i],
                colors: colors,
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
          ],
          if (a.anahtarNoktalar.isNotEmpty) ...[
            const DsSectionHeader(title: '🔑 Anahtar Noktalar'),
            const SizedBox(height: 10),
            for (var i = 0; i < a.anahtarNoktalar.length; i++) ...[
              _KeyPointCard(
                index: i,
                text: a.anahtarNoktalar[i],
                colors: colors,
              ),
              const SizedBox(height: 8),
            ],
          ],
          FutureBuilder<Map<String, List<String>>>(
            future: context.read<DataService>().loadMnemonics(),
            builder: (context, snap) {
              final tips = snap.data?[topic.id] ?? const [];
              if (tips.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DsSectionHeader(title: '🧠 Akılda Kalıcı'),
                    const SizedBox(height: 10),
                    if (!premium)
                      DsCard(
                        accent: colors.gold,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🔒 Bu konu için akılda kalıcı kodlama teknikleri Premium\'a özel.',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13, color: colors.text),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: DsPillButton(
                                label: "Premium'a Geç",
                                color: colors.gold,
                                onPressed: () {
                                  context.read<SoundService>().click();
                                  Navigator.of(context)
                                      .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                                },
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      for (final tip in tips) ...[
                        DsCard(
                          accent: colors.violet,
                          padding: const EdgeInsets.all(14),
                          child: Text(tip,
                              style: TextStyle(fontSize: 13, height: 1.5, color: colors.text)),
                        ),
                        const SizedBox(height: kDsGap),
                      ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          if (attempts.isNotEmpty) ...[
            // Listede yalnızca SON 3 test görünür; hepsi detay ekranında.
            // 3'ten az test varsa "tümünü gör" bağlantısı hiç çıkmaz.
            DsSectionHeader(
              title: '📋 Geçmiş Testlerin',
              actionLabel: tumunuGor ? 'Tümünü Gör (${attempts.length})' : null,
              onAction: tumunuGor ? () => _tumTestleriAc(attempts) : null,
            ),
            const SizedBox(height: 10),
            DsCard(
              // Karta dokunmak da tüm geçmişi açar (başlıktaki bağlantıyla aynı).
              onTap: tumunuGor ? () => _tumTestleriAc(attempts) : null,
              child: Column(
                children: [
                  for (var i = sonUcBaslangic; i < attempts.length; i++) ...[
                    if (i > sonUcBaslangic)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Container(height: 1, color: colors.border),
                      ),
                    _GecmisTestSatiri(
                      sira: i + 1,
                      attempt: attempts[i],
                      colors: colors,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: kDsGap),
          ],
          if (maxed)
            DsCard(
              accent: colors.gold,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Kota dolduğunda tek çıkış yolu Premium'dur — "sıfırla"
                  // seçeneği bilerek KALDIRILDI (kotayı sıfırlamak Premium'u
                  // anlamsız kılıyordu). Mesaj bu yüzden net ve dürüst.
                  Text(
                    '🎓 Bu konudaki ücretsiz soruların bitti '
                    '(ücretsiz pakette konu başına $maxAtt test). '
                    "Sınırsız soru için Premium'a geç.",
                    style: TextStyle(fontSize: 13, height: 1.4, color: colors.text),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DsPillButton(
                      label: "💎 Premium'a Geç",
                      color: colors.gold,
                      onPressed: () {
                        context.read<SoundService>().click();
                        Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                      },
                    ),
                  ),
                ],
              ),
            )
          else
            DsCard(
              accent: colors.violet,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    premium
                        ? 'Sınırsıza yakın soru havuzu • Sınırsız test hakkın var ✨'
                        : '20 soruluk havuz • ${maxAtt - attempts.length} hak kaldı',
                    style: TextStyle(fontSize: 13, height: 1.4, color: colors.textDim),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DsPillButton(
                      // Soru havuzu indirilirken buton pasif kalsın.
                      label: _startingQuiz
                          ? 'Hazırlanıyor…'
                          : (attempts.isNotEmpty ? 'Tekrar Çöz' : 'Teste Başla'),
                      color: colors.violet,
                      gradient: LinearGradient(colors: [colors.violet, colors.rose]),
                      trailingIcon: Icons.arrow_forward,
                      onPressed:
                          _startingQuiz ? null : () => _startQuiz(context, storage, premium),
                    ),
                  ),
                ],
              ),
            ),
          if (teachers.isNotEmpty) ...[
            const SizedBox(height: 16),
            _TeacherVideosCard(
              teachers: teachers,
              subjectAd: subject.ad,
              topicBaslik: topic.baslik,
              colors: colors,
            ),
            const SizedBox(height: 16),
            _TeacherTemperamentsSection(teachers: teachers, colors: colors),
          ],
          const SizedBox(height: 16),
          DsCard(
            accent: colors.mint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DsIconBadge(emoji: '📄', color: colors.mint, size: 44, glow: false),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('PDF Olarak İndir',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15, color: colors.text)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'İlk indirişinde konu anlatımı + 20 soru gelir; soruların '
                  'cevapları en son sayfada (cevap anahtarı) yer alır. Tekrar '
                  'indirdiğinde konu anlatımı olmadan, sadece farklı 20 soru hazırlanır.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: colors.textFaint),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: DsPillButton(
                    label: 'PDF Oluştur',
                    color: colors.mint,
                    filled: false,
                    leadingIcon: Icons.picture_as_pdf_outlined,
                    onPressed: () => _exportPdf(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tek bir geçmiş test satırı: sıra rozeti + doğru/yanlış + tarih + skor.
///
/// Hem konu ekranındaki son 3'lük önizlemede hem de "tümünü gör" detay
/// ekranında AYNI widget kullanılır — iki yerde de tarih gösterimi
/// ("🗓️ Bugün" / "Dün" / "12 Tem 2026") korunur.
class _GecmisTestSatiri extends StatelessWidget {
  /// Kullanıcıya gösterilen test numarası (1'den başlar, kronolojik).
  final int sira;
  final Attempt attempt;
  final KpssColors colors;

  const _GecmisTestSatiri({
    required this.sira,
    required this.attempt,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DsChip(label: '$sira. TEST', color: colors.violetL),
        const SizedBox(width: 10),
        // Sonuç + testin çözüldüğü tarih. Dar ekranda tarih alt satıra iner,
        // taşma olmaz.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${attempt.dogru} doğru / ${attempt.yanlis} yanlış',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: colors.textDim),
              ),
              const SizedBox(height: 2),
              Text(
                '🗓️ ${_kisaTarih(attempt.tarih)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: colors.textFaint),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text('%${attempt.skor}',
            style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 15, color: colors.text)),
      ],
    );
  }
}

/// Bir konuda çözülmüş TÜM geçmiş testleri gösteren detay ekranı.
/// Konu ekranındaki liste yalnızca son 3'ü gösterdiği için tam geçmiş
/// buradan görülür — en yeni test en üstte.
class _TumGecmisTestlerScreen extends StatelessWidget {
  final String topicBaslik;

  /// Kronolojik (en eskiden en yeniye) sıralı liste — ekranda ters çevrilir.
  final List<Attempt> attempts;

  const _TumGecmisTestlerScreen({required this.topicBaslik, required this.attempts});

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    // En iyi skor ve ortalama, geçmişe bakarken hızlı bir üst bakış sağlar.
    final enIyi = attempts.map((a) => a.skor).reduce((x, y) => x > y ? x : y);
    final ortalama =
        (attempts.map((a) => a.skor).reduce((x, y) => x + y) / attempts.length).round();

    return Scaffold(
      appBar: AppBar(title: const Text('📋 Geçmiş Testlerin')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DsCard(
            accent: colors.violet,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topicBaslik,
                  style: TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15, color: colors.text),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DsChip(label: '${attempts.length} test', color: colors.violetL),
                    DsChip(label: '⭐ En iyi %$enIyi', color: colors.gold),
                    DsChip(label: '📈 Ortalama %$ortalama', color: colors.mint),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: kDsGap),
          const DsSectionHeader(title: 'Tüm Testler'),
          const SizedBox(height: 10),
          DsCard(
            child: Column(
              children: [
                // En yeni test en üstte görünsün.
                for (var i = attempts.length - 1; i >= 0; i--) ...[
                  if (i < attempts.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Container(height: 1, color: colors.border),
                    ),
                  _GecmisTestSatiri(
                    sira: i + 1,
                    attempt: attempts[i],
                    colors: colors,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Konu anlatımını Türkçe seslendiren dinle/durdur düğmesi.
///
/// `TtsService.isSpeaking`'i dinler ve buna göre "🔊 Sesli Dinle" /
/// "⏹ Durdur" arasında geçiş yapar.
class _TtsListenButton extends StatelessWidget {
  final String text;
  final KpssColors colors;
  const _TtsListenButton({required this.text, required this.colors});

  @override
  Widget build(BuildContext context) {
    final tts = context.watch<TtsService>();
    final speaking = tts.isSpeaking;
    final accent = speaking ? colors.rose : colors.violet;

    // İkincil eylem: dış çizgili hap buton.
    return Center(
      child: DsPillButton(
        label: speaking ? 'Durdur' : 'Sesli Dinle',
        color: accent,
        filled: false,
        leadingIcon: speaking ? Icons.stop_circle_outlined : Icons.volume_up_rounded,
        onPressed: text.isEmpty
            ? null
            : () {
                context.read<SoundService>().click();
                if (speaking) {
                  context.read<TtsService>().stop();
                } else {
                  context.read<TtsService>().speak(text);
                }
              },
      ),
    );
  }
}

/// Özet için dikkat çekici, temaya göre gradient dolgulu kart.
class _SummaryBox extends StatelessWidget {
  final String text;
  final KpssColors colors;
  const _SummaryBox({required this.text, required this.colors});

  @override
  Widget build(BuildContext context) {
    return DsCard(
      accent: colors.violet,
      padding: const EdgeInsets.all(18),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colors.violet.withValues(alpha: colors.isLight ? 0.16 : 0.24),
          colors.rose.withValues(alpha: colors.isLight ? 0.08 : 0.14),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DsIconBadge(emoji: '💡', color: colors.violet, size: 42, glow: false),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📌 ÖZET',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: colors.violetL,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1.35,
                    color: colors.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Her konu anlatımı paragrafı için ayrı, hafif renkli kutucuk.
class _ParagraphCard extends StatelessWidget {
  final int index;
  final String text;
  final KpssColors colors;
  const _ParagraphCard({required this.index, required this.text, required this.colors});

  @override
  Widget build(BuildContext context) {
    final palette = [colors.violet, colors.mint, colors.gold, colors.rose];
    final accent = palette[index % palette.length];
    final emoji = _kParagraphEmojis[index % _kParagraphEmojis.length];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, height: 1.45, color: colors.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Anahtar nokta kutucuğu: metnin başında zaten emoji varsa onu büyütüp ayırır,
/// yoksa dönüşümlü bir yedek emoji ile gösterir.
class _KeyPointCard extends StatelessWidget {
  final int index;
  final String text;
  final KpssColors colors;
  const _KeyPointCard({required this.index, required this.text, required this.colors});

  /// Metnin başında tekil kod noktalı bir emoji varsa (🔑, 💡 gibi) onu ve
  /// kalan metni ayrı ayrı döndürür; yoksa null döner.
  static (String, String)? _splitLeadingEmoji(String text) {
    if (text.isEmpty) return null;
    final runes = text.runes.toList();
    final first = runes.first;
    final isEmoji = (first >= 0x1F300 && first <= 0x1FAFF) ||
        (first >= 0x2600 && first <= 0x27BF) ||
        (first >= 0x2190 && first <= 0x21FF) ||
        (first >= 0x2B00 && first <= 0x2BFF);
    if (!isEmoji) return null;
    final emoji = String.fromCharCode(first);
    final rest = String.fromCharCodes(runes.skip(1)).trimLeft();
    if (rest.isEmpty) return null;
    return (emoji, rest);
  }

  @override
  Widget build(BuildContext context) {
    final palette = [colors.gold, colors.mint, colors.violet, colors.rose];
    final accent = palette[index % palette.length];

    final split = _splitLeadingEmoji(text);
    final emoji = split?.$1 ?? _kKeyPointFallbackEmojis[index % _kKeyPointFallbackEmojis.length];
    final label = split?.$2 ?? text;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Konu ekranında ilgili dersin hocalarını gösteren kart — bir hocaya
/// dokununca o hocanın bu konudaki videoları YouTube'da açılır.
class _TeacherVideosCard extends StatelessWidget {
  final List<Teacher> teachers;
  final String subjectAd;
  final String topicBaslik;
  final KpssColors colors;
  const _TeacherVideosCard({
    required this.teachers,
    required this.subjectAd,
    required this.topicBaslik,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return DsCard(
      accent: colors.rose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DsIconBadge(emoji: '🎥', color: colors.rose, size: 44, glow: false),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Hocalardan Konu Anlatımı',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15, color: colors.text)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Bir hoca seç, o hocanın bu konudaki videolarını YouTube\'da aç.',
              style: TextStyle(fontSize: 12, height: 1.4, color: colors.textFaint)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Link widget'ı web'de gerçek bir <a> bağlantısı olarak render
              // edilir → tarayıcının popup engelleyicisine TAKILMADAN yeni
              // sekmede açılır. Mobilde url_launcher ile YouTube açılır.
              for (final t in teachers)
                Link(
                  uri: Uri.parse(
                      youtubeSearchUrlFor(t.name, subjectAd, topicBaslik)),
                  target: LinkTarget.blank,
                  builder: (context, followLink) => DsPillButton(
                    label: t.name,
                    color: colors.rose,
                    filled: false,
                    leadingIcon: Icons.play_circle_fill,
                    onPressed: followLink,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sayfanın en altındaki "Hocaların Mizaçları" bölümü — açılıp kapanabilen,
/// her hocanın adını ve anlatım tarzını (mizacını) listeler.
class _TeacherTemperamentsSection extends StatelessWidget {
  final List<Teacher> teachers;
  final KpssColors colors;
  const _TeacherTemperamentsSection({required this.teachers, required this.colors});

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          // Kart kendi kenarlığını çizdiği için açılır başlık şeffaf kalır.
          backgroundColor: Colors.transparent,
          collapsedBackgroundColor: Colors.transparent,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Text('🎭 Hocaların Mizaçları',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15, color: colors.text)),
          subtitle: Text('Sana en uygun anlatım tarzını seç',
              style: TextStyle(fontSize: 11.5, color: colors.textFaint)),
          children: [
            for (final t in teachers)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            color: colors.violet)),
                    const SizedBox(height: 3),
                    Text(t.mizac,
                        style: TextStyle(fontSize: 12.5, height: 1.4, color: colors.text)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
