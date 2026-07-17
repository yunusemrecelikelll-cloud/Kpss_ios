import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subject.dart';
import '../models/topic.dart';
import '../services/data_service.dart';
import '../services/remote_question_service.dart';
import '../services/storage_service.dart';
import '../services/question_picker.dart';
import '../services/sound_service.dart';
import '../services/tts_service.dart';
import '../services/pdf_export_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import 'quiz_screen.dart';
import 'premium_screen.dart';

const int kFreeMaxAttemptsPerTopic = 2;

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

class _TopicScreenState extends State<TopicScreen> {
  bool _startingQuiz = false;
  late final TtsService _ttsService;

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
  }

  @override
  void dispose() {
    // Kullanıcı sesli anlatımı dinlerken ekrandan ayrılırsa konuşmayı durdur.
    _ttsService.stop();
    super.dispose();
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

  Future<void> _exportPdf(BuildContext context, bool premium) async {
    context.read<SoundService>().click();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PDF oluşturuluyor…'), duration: Duration(seconds: 2)),
    );
    try {
      final pool = await context
          .read<RemoteQuestionService>()
          .getPool(topic.id, topic.sorular);
      await PdfExportService.exportTopic(
        subject: subject.meta,
        topic: topic,
        premium: premium,
        soruHavuzu: pool,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF oluşturulamadı: $e')),
      );
    }
  }

  Future<void> _startQuiz(BuildContext context, StorageService storage, bool premium) async {
    context.read<SoundService>().click();
    setState(() => _startingQuiz = true);
    final pool = await context.read<RemoteQuestionService>().getPool(topic.id, topic.sorular);
    if (!context.mounted) return;
    setState(() => _startingQuiz = false);
    final picker = QuestionPicker(storage);
    final qs = picker.pickForTopic(pool, 10, topic.id, premium: premium);
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => QuizScreen(
        subjectId: subject.id,
        subjectAd: subject.ad,
        topicId: topic.id,
        topicBaslik: topic.baslik,
        questions: qs,
        isFullTest: false,
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
    final a = topic.anlatim;

    return Scaffold(
      appBar: AppBar(
        title: Text('📘 ${topic.baslik}'),
        actions: [
          IconButton(
            tooltip: 'PDF Oluştur',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => _exportPdf(context, premium),
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
            _SectionHeader(emoji: '📚', title: 'Konu Anlatımı', colors: colors),
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
            _SectionHeader(emoji: '🔑', title: 'Anahtar Noktalar', colors: colors),
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
                    _SectionHeader(emoji: '🧠', title: 'Akılda Kalıcı', colors: colors),
                    const SizedBox(height: 10),
                    if (!premium)
                      Card(
                        color: colors.gold.withValues(alpha: 0.08),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('🔒 Bu konu için akılda kalıcı kodlama teknikleri Premium\'a özel.',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              const SizedBox(height: 10),
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
                      )
                    else
                      for (final tip in tips) ...[
                        Card(
                          color: colors.violet.withValues(alpha: 0.06),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: colors.violet.withValues(alpha: 0.25)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(tip, style: const TextStyle(fontSize: 13, height: 1.5)),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          if (attempts.isNotEmpty) ...[
            const Text('📋 Geçmiş Testlerin', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (var i = 0; i < attempts.length; i++)
              Card(
                child: ListTile(
                  dense: true,
                  leading: Text('${i + 1}. Test'),
                  title: Text('${attempts[i].dogru} doğru / ${attempts[i].yanlis} yanlış'),
                  trailing: Text('%${attempts[i].skor}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            const SizedBox(height: 12),
          ],
          if (maxed)
            Card(
              color: colors.gold.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🎓 Ücretsiz pakette bu konuyu $maxAtt kez çözdün. '
                        "Sınırsız test için Premium'a geç ya da sıfırlayıp yeniden başla."),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, children: [
                      OutlinedButton(
                        onPressed: () async {
                          context.read<SoundService>().click();
                          await storage.resetTopicAttempts(topic.id);
                        },
                        child: const Text('🔄 Testleri Sıfırla'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          context.read<SoundService>().click();
                          Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                        },
                        child: const Text("💎 Premium'a Geç"),
                      ),
                    ]),
                  ],
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(premium
                          ? 'Sınırsıza yakın soru havuzu • Sınırsız test hakkın var ✨'
                          : '20 soruluk havuz • ${maxAtt - attempts.length} hak kaldı'),
                    ),
                    ElevatedButton(
                      onPressed: _startingQuiz ? null : () => _startQuiz(context, storage, premium),
                      child: _startingQuiz
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(attempts.isNotEmpty ? 'Tekrar Çöz →' : 'Teste Başla →'),
                    ),
                  ],
                ),
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

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.5), width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(speaking ? Icons.stop_circle_outlined : Icons.volume_up_rounded),
        label: Text(
          speaking ? '⏹ Durdur' : '🔊 Sesli Dinle',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
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

/// Bölüm başlığı: emoji + başlık + ince ayraç çizgisi.
class _SectionHeader extends StatelessWidget {
  final String emoji;
  final String title;
  final KpssColors colors;
  const _SectionHeader({required this.emoji, required this.title, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            letterSpacing: 0.2,
            color: colors.text,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.violet.withValues(alpha: 0.5), colors.violet.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Özet için dikkat çekici, temaya göre gradient dolgulu kutu.
class _SummaryBox extends StatelessWidget {
  final String text;
  final KpssColors colors;
  const _SummaryBox({required this.text, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.violet.withValues(alpha: 0.20),
            colors.rose.withValues(alpha: 0.14),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.violet.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.violet.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: const Text('💡', style: TextStyle(fontSize: 20)),
          ),
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
