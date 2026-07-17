import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/turkey_map_data.dart';
import '../../data/turkey_map_quiz_data.dart';
import '../../models/badge.dart';
import '../../models/question.dart';
import '../../models/subject.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_provider.dart';
import 'map_shared.dart';

/// Çoktan seçmeli seçenek harfleri (A, B, C, D, E).
const List<String> kOptionLetters = ['A', 'B', 'C', 'D', 'E'];

const String _kHowToPlay =
    'Haritada bir ile dokun, 5 soruluk mini bir quiz çöz. En az 3/5 doğru '
    'cevaplarsan o ili fethedersin. Günlük hak sınırı YOKTUR — istediğin '
    'kadar il deneyebilir, fethedilmiş illeri de tekrar oynayabilirsin. 81 '
    'ilin tamamını fethedince özel bir "KPSS Fatihi" rozeti kazanırsın.';

/// "81 İl Fethi" — bayrak mod. Kullanıcının en dikkat çekici/viral bulduğu
/// mod olarak öncelik sırasının başında; TAM ÇALIŞIR olacak şekilde
/// tasarlanmıştır. Günlük oyun hakkından SAYILMAZ (bkz. map_shared.dart) —
/// bir il her denendiğinde useGamePlay ÇAĞRILMAZ, dilediği kadar
/// denenebilir/tekrar oynanabilir.
class IlFethiScreen extends StatefulWidget {
  final List<Subject> subjects;
  const IlFethiScreen({super.key, required this.subjects});

  @override
  State<IlFethiScreen> createState() => _IlFethiScreenState();
}

class _IlFethiScreenState extends State<IlFethiScreen> {
  DateTime? _sessionStart;

  @override
  void initState() {
    super.initState();
    _sessionStart = DateTime.now();
  }

  @override
  void dispose() {
    final start = _sessionStart;
    if (start != null) {
      context.read<StorageService>().addGameTimeSpent(kIlFethiTimeGameId, DateTime.now().difference(start));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final colors = context.watch<ThemeProvider>().colors;
    final passed = storage.getGamePassedTopics(kMapGameId);
    final conqueredCount = passed.length;
    final allDone = conqueredCount >= 81;
    final palette = mapModePaletteFor(kIlFethiTimeGameId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('👑 81 İl Fethi'),
        actions: [
          IconButton(
            tooltip: 'Nasıl oynanır?',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showHowToPlaySheet(context, title: '81 İl Fethi', body: _kHowToPlay),
          ),
        ],
      ),
      body: Container(
        decoration: mapModeBackgroundDecoration(palette, colors.isLight),
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Bir ile dokun, 5 soruluk mini quiz\'i çöz, ili fethet! Günlük hak sınırı YOK.',
                      style: TextStyle(fontSize: 13, color: colors.textFaint),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: conqueredCount / 81, minHeight: 8),
              ),
              const SizedBox(height: 4),
              Text('$conqueredCount / 81 il fethedildi', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              if (allDone) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    context.read<SoundService>().click();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const _FatihCelebrationScreen()),
                    );
                  },
                  icon: const Text('🏆'),
                  label: const Text('KPSS Fatihi kutlamasını gör'),
                ),
              ],
              const SizedBox(height: 10),
              Expanded(
                child: TurkeyMapCanvas(
                  provinces: kTurkeyProvinces,
                  // Sadece fethedilen iller yeşil boyanır; fethedilmemişler
                  // nötr/soluk renkte kalır — kilit ikonu KALDIRILDI (kullanıcı
                  // "her il her zaman denenebilir" hissini istedi, kilitli
                  // görünüm yanıltıcıydı).
                  colorFor: (p) => (passed[p.id] == true) ? colors.success : colors.textFaint.withValues(alpha: 0.35),
                  overlayFor: (p) => (passed[p.id] == true) ? const Text('👑', style: TextStyle(fontSize: 13)) : null,
                  onTap: (p) async {
                    final alreadyDone = passed[p.id] == true;
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => _ProvinceQuizScreen(
                          province: p,
                          alreadyConquered: alreadyDone,
                          subjects: widget.subjects,
                        ),
                      ),
                    );
                    if (result == true && mounted) setState(() {});
                  },
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// Bir ilin 5 soruluk fetih quiz'i. En az 3/5 doğru cevap ile il fethedilir.
class _ProvinceQuizScreen extends StatefulWidget {
  final TurkeyProvince province;
  final bool alreadyConquered;
  final List<Subject> subjects;
  const _ProvinceQuizScreen({
    required this.province,
    required this.alreadyConquered,
    required this.subjects,
  });

  @override
  State<_ProvinceQuizScreen> createState() => _ProvinceQuizScreenState();
}

class _ProvinceQuizScreenState extends State<_ProvinceQuizScreen> {
  late List<Question> _questions;
  int _index = 0;
  int _correct = 0;
  int? _given;
  bool _showResult = false;
  bool _finished = false;
  bool _justUnlockedFatih = false;

  static const int kPassThreshold = 3;

  @override
  void initState() {
    super.initState();
    _questions = List<Question>.from(kTurkeyProvinceQuiz[widget.province.id] ?? const []);
  }

  void _select(int i) {
    if (_showResult) return;
    context.read<SoundService>().click();
    setState(() {
      _given = i;
      _showResult = true;
      if (i == _questions[_index].dogruIndex) _correct++;
    });
  }

  Future<void> _next() async {
    context.read<SoundService>().click();
    if (_index + 1 < _questions.length) {
      setState(() {
        _index++;
        _given = null;
        _showResult = false;
      });
      return;
    }
    // Quiz bitti.
    final passedNow = _correct >= kPassThreshold;
    if (passedNow) {
      final storage = context.read<StorageService>();
      final before = storage.getGamePassedTopics(kMapGameId).length;
      await storage.markGameTopicPassed(kMapGameId, widget.province.id);
      final after = storage.getGamePassedTopics(kMapGameId).length;
      if (before < 81 && after >= 81) {
        await checkAndUnlockBadges(storage, widget.subjects);
        _justUnlockedFatih = true;
      }
    }
    if (!mounted) return;
    setState(() => _finished = true);
  }

  void _retry() {
    setState(() {
      _questions = List<Question>.from(kTurkeyProvinceQuiz[widget.province.id] ?? const [])..shuffle();
      _index = 0;
      _correct = 0;
      _given = null;
      _showResult = false;
      _finished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('👑 ${widget.province.ad}')),
        body: const Center(child: Text('Bu il için soru bulunamadı.')),
      );
    }
    if (_finished) return _buildFinished(context);
    return _buildQuestion(context);
  }

  Widget _buildQuestion(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final q = _questions[_index];
    return Scaffold(
      appBar: AppBar(title: Text('👑 ${widget.province.ad} Fethi')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Soru ${_index + 1}/${_questions.length}', style: TextStyle(fontSize: 12.5, color: colors.textFaint)),
                  Text('Doğru: $_correct', style: TextStyle(fontSize: 12.5, color: colors.success, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: (_index) / _questions.length, minHeight: 6),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: colors.glass2,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(q.soru, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 14),
                        for (var i = 0; i < q.secenekler.length; i++) _buildOption(q, i, colors),
                        if (_showResult) ...[
                          const Divider(height: 24),
                          Text('💡 ${q.aciklama}', style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 14),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton(
                              onPressed: _next,
                              child: Text(_index + 1 < _questions.length ? 'Sonraki Soru →' : 'Bitir'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOption(Question q, int i, KpssColors colors) {
    Color? borderColor;
    Color? bgColor;
    if (_showResult) {
      if (i == q.dogruIndex) {
        borderColor = colors.success;
        bgColor = colors.success.withValues(alpha: 0.12);
      } else if (i == _given) {
        borderColor = colors.danger;
        bgColor = colors.danger.withValues(alpha: 0.12);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: !_showResult ? () => _select(i) : null,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor ?? colors.border),
            color: bgColor,
          ),
          child: Row(
            children: [
              CircleAvatar(radius: 13, child: Text(kOptionLetters[i], style: const TextStyle(fontSize: 12))),
              const SizedBox(width: 12),
              Expanded(child: Text(q.secenekler[i])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinished(BuildContext context) {
    final passedNow = _correct >= kPassThreshold;
    if (_justUnlockedFatih) {
      return const _FatihCelebrationScreen();
    }
    final colors = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(title: Text('👑 ${widget.province.ad}')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(passedNow ? '🎉' : '📚', style: const TextStyle(fontSize: 44)),
                const SizedBox(height: 12),
                Text(
                  passedNow
                      ? '${widget.province.ad} ilini fethettin! ${_questions.length} sorudan $_correct tanesini doğru bildin.'
                      : '${widget.province.ad} ilini fethedemedin (${_questions.length} sorudan $_correct doğru, en az $kPassThreshold doğru gerekiyor). Tekrar dene!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textFaint, height: 1.5),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        context.read<SoundService>().click();
                        _retry();
                      },
                      child: const Text('🔄 Tekrar Dene'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        context.read<SoundService>().click();
                        Navigator.of(context).pop(true);
                      },
                      child: const Text('Haritaya Dön'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tüm 81 il fethedildiğinde gösterilen özel kutlama ekranı.
class _FatihCelebrationScreen extends StatelessWidget {
  const _FatihCelebrationScreen();

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(title: const Text('🗺️ KPSS Fatihi')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.elasticOut,
                    builder: (context, v, child) => Transform.scale(scale: v, child: child),
                    child: const Text('🗺️👑', style: TextStyle(fontSize: 54)),
                  ),
                  const SizedBox(height: 16),
                  const Text('KPSS Fatihi!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    "Türkiye'nin 81 ilini de fethettin! Yeni bir rozet kazandın: 🗺️ Harita Fatihi.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textFaint, height: 1.5),
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed: () {
                      context.read<SoundService>().click();
                      Navigator.of(context).pop(true);
                    },
                    child: const Text('Haritaya Dön'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
