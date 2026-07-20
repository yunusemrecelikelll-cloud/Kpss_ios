import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/subject.dart';
import '../../models/question.dart';
import '../../services/remote_question_service.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_provider.dart';
import '../tools_hub_screen.dart';
import 'quick_modes_shared.dart';

/// 60 Saniye Challenge — GENEL oyun kimliği. DİKKAT: bu, harita oyunundaki
/// "60 Saniyede Türkiye" (lib/screens/map_game/hiz_modu.dart) modundan
/// FARKLIDIR — o sadece harita/il sorularını kullanır, bu ekran ise TÜM
/// derslerden (harita hariç — zaten DataService.loadAll() haritayı içermez)
/// karışık soru çeker.
const String kHiz60GameId = 'hiz-60-genel';
const int kHiz60Suresi = 60;

/// 60 Saniye Challenge — 60 saniye boyunca art arda gelen karışık sorulara
/// hızlıca cevap verilir; doğru cevap sayısına göre puan alınır.
class Hiz60Screen extends StatefulWidget {
  final List<Subject> subjects;
  const Hiz60Screen({super.key, required this.subjects});

  @override
  State<Hiz60Screen> createState() => _Hiz60ScreenState();
}

class _Hiz60ScreenState extends State<Hiz60Screen> {
  final _rnd = Random();
  bool _locked = false;
  bool _loading = true;
  bool _noQuestions = false;
  bool _finished = false;

  List<Question> _pool = [];
  final List<Question> _queue = [];
  Question? _current;
  int _secondsLeft = kHiz60Suresi;
  int _score = 0;
  int _wrong = 0;
  int _attempts = 0;
  Timer? _ticker;

  /// Son cevabın doğru olup olmadığı — soru ANINDA değiştiği için, kullanıcıya
  /// çok kısa (ve akışı HİÇ bekletmeyen) bir geri bildirim rozeti göstermekte
  /// kullanılır. null = henüz cevap verilmedi.
  bool? _lastCorrect;

  /// Yanlışların hangi ders/konuda yoğunlaştığını saymak için — sonuç
  /// ekranındaki "neye çalışmalısın" yorumu bu sayaçlardan üretilir.
  final Map<String, int> _wrongBySubject = {};
  final Map<String, int> _wrongByTopic = {};

  /// Rekor bir kez kaydedilsin diye (süre bitişi + dispose yarışını önler).
  bool _saved = false;
  bool _yeniRekor = false;

  // Toplam oynama süresi takibi: oturum, soru havuzu yüklenip ilk soru
  // gösterildiğinde başlar; ekran kapandığında (erken çıkış dahil, dispose
  // her zaman çağrılır) kısmi süre de kaydedilir.
  DateTime? _sessionStart;
  late final StorageService _storage;

  @override
  void initState() {
    super.initState();
    _storage = context.read<StorageService>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _flushPlayTime();
    _ticker?.cancel();
    super.dispose();
  }

  void _flushPlayTime() {
    final start = _sessionStart;
    if (start == null) return;
    _sessionStart = null;
    _storage.addGameTimeSpent(kHiz60GameId, DateTime.now().difference(start));
  }

  Future<void> _boot() async {
    final storage = context.read<StorageService>();
    final premium = storage.isPremiumUser();
    if (!premium) {
      final gp = storage.getGamePlayState(kHiz60GameId);
      if ((gp['plays'] as int) >= kFreeGameDailyLimit) {
        if (!mounted) return;
        setState(() => _locked = true);
        return;
      }
      await storage.useGamePlay(kHiz60GameId);
    }
    if (!mounted) return;

    final remote = context.read<RemoteQuestionService>();
    final pool = await QuickModesShared.collectAll(widget.subjects, remote, rnd: _rnd);
    if (!mounted) return;

    if (pool.isEmpty) {
      setState(() {
        _loading = false;
        _noQuestions = true;
      });
      return;
    }

    _pool = pool;
    _queue
      ..clear()
      ..addAll(pool);
    context.read<SoundService>().resetTickPhase();
    _wrongBySubject.clear();
    _wrongByTopic.clear();
    setState(() {
      _loading = false;
      _finished = false;
      _saved = false;
      _yeniRekor = false;
      _secondsLeft = kHiz60Suresi;
      _score = 0;
      _wrong = 0;
      _attempts = 0;
      _lastCorrect = null;
      _current = _popNext();
    });
    _sessionStart ??= DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Question _popNext() {
    if (_queue.isEmpty) {
      _queue.addAll(List<Question>.from(_pool)..shuffle(_rnd));
    }
    return _queue.removeLast();
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _secondsLeft--);
    if (_secondsLeft <= 5 && _secondsLeft > 0) {
      context.read<SoundService>().tick();
    }
    if (_secondsLeft <= 0) {
      _ticker?.cancel();
      _finish();
    }
  }

  /// Süre bittiğinde bir kez çalışır: rekoru ve son tur istatistiğini kaydeder.
  Future<void> _finish() async {
    if (_saved) return;
    _saved = true;
    setState(() => _finished = true);
    final yeni = await _storage.submitHighScore(kHiz60GameId, _score);
    await _storage.setLastRoundStats(kHiz60GameId, correct: _score, wrong: _wrong);
    if (!mounted) return;
    setState(() => _yeniRekor = yeni);
  }

  /// Şıkka dokunulduğu ANDA cevabı işler ve sonraki soruya geçer — arada
  /// hiçbir `Future.delayed`/animasyon beklemesi YOKTUR (60 saniyelik modda
  /// her milisaniye önemli). Geri bildirim, akışı durdurmayan küçük bir
  /// ✓/✗ rozetiyle üst şeritte verilir.
  void _select(int idx) {
    if (_finished || _current == null) return;
    final q = _current!;
    final correct = idx == q.dogruIndex;
    context.read<SoundService>().click();
    if (!correct) {
      final ders = (q.subjectAd ?? '').trim();
      if (ders.isNotEmpty) _wrongBySubject[ders] = (_wrongBySubject[ders] ?? 0) + 1;
      final konu = (q.topicBaslik ?? '').trim();
      if (konu.isNotEmpty) _wrongByTopic[konu] = (_wrongByTopic[konu] ?? 0) + 1;
    }
    setState(() {
      _attempts++;
      _lastCorrect = correct;
      if (correct) {
        _score++;
      } else {
        _wrong++;
      }
      _current = _popNext();
    });
  }

  /// Doğru/yanlış dağılımına göre Türkçe bir değerlendirme + "neye çalışmalı"
  /// önerisi üretir. Öneri, yanlışların EN ÇOK yoğunlaştığı konuya (yoksa
  /// derse) göre verilir.
  String _sonucYorumu() {
    if (_attempts == 0) {
      return 'Hiç soru cevaplamadın. Bir dahakine süre başlar başlamaz ilk şıkkı '
          'okumaya başla — hız da bir çalışma becerisidir!';
    }
    final oran = _score / _attempts;
    final buf = StringBuffer();
    if (oran >= 0.85) {
      buf.write('Harika bir isabet oranı! Bilgin sağlam, artık tek eksiğin daha fazla soru çözerek hızlanmak.');
    } else if (oran >= 0.6) {
      buf.write('Fena değil — doğruların yanlışlarından belirgin şekilde fazla. Biraz daha tekrar seni üst seviyeye taşır.');
    } else if (oran >= 0.4) {
      buf.write('Doğru ve yanlışların birbirine yakın. Hızlanmadan önce konu tekrarına ağırlık vermelisin.');
    } else {
      buf.write('Yanlışların doğrularından fazla. Acele etmek yerine önce konuları pekiştirmen daha çok kazandırır.');
    }

    // En çok yanlış yapılan konu/ders — öneri buradan çıkar.
    String? enZayif;
    int enCok = 0;
    _wrongByTopic.forEach((k, v) {
      if (v > enCok) {
        enCok = v;
        enZayif = k;
      }
    });
    if (enZayif == null) {
      _wrongBySubject.forEach((k, v) {
        if (v > enCok) {
          enCok = v;
          enZayif = k;
        }
      });
    }
    if (enZayif != null && enCok > 0) {
      final ders = _wrongBySubject.isEmpty
          ? null
          : (_wrongBySubject.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
      buf.write('\n\n📌 Yanlışların en çok "$enZayif" konusunda yoğunlaştı ($enCok yanlış).');
      if (ders != null && ders != enZayif) {
        buf.write(' Öncelikle $ders dersindeki bu konuyu tekrar et.');
      } else {
        buf.write(' Öncelikle bu konuyu tekrar et.');
      }
    } else if (_wrong == 0) {
      buf.write('\n\n📌 Hiç yanlışın yok — zorluk seviyeni artırmak için daha fazla soru çözmeyi dene.');
    }
    return buf.toString();
  }

  void _retry() {
    setState(() {
      _locked = false;
      _loading = true;
      _noQuestions = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return const LockedFeatureCard(
        title: '60 Saniye Challenge',
        desc: "Bugünkü ücretsiz hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_noQuestions) {
      return const Scaffold(body: Center(child: Text('Yeterli soru bulunamadı.')));
    }
    if (_finished) {
      final record = context.watch<StorageService>().getHighScore(kHiz60GameId);
      return QuickModeResultCard(
        title: '⏱️ 60 Saniye Challenge',
        emoji: _yeniRekor ? '🏆' : (_score >= 15 ? '🎉' : '📚'),
        message: '✅ $_score doğru   •   ❌ $_wrong yanlış\n($_attempts soru cevapladın)',
        subMessage: '${quickModeRecordLine(record: record, yeniRekor: _yeniRekor)}\n\n${_sonucYorumu()}',
        onRetry: _retry,
      );
    }
    return _buildBoard(context);
  }

  Widget _buildBoard(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final totalSeconds = context.watch<StorageService>().getGameTimeSpent(kHiz60GameId);
    final q = _current!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('⏱️ 60 Saniye Challenge'),
        actions: const [
          HowToPlayButton(
            title: '⏱️ Nasıl Oynanır?',
            body: '60 saniye boyunca art arda gelen karışık sorulara olabildiğince '
                'hızlı ve doğru cevap vermeye çalış. Şıkka dokunduğun anda bir sonraki '
                'soru gelir; doğru ve yanlış sayıların ayrı ayrı tutulur. Süre '
                'dolduğunda hangi konuda zorlandığına dair bir değerlendirme alırsın '
                've skorun "En Yüksek Skor" rekorunla karşılaştırılır!',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              QuickModeScoreBar(
                gameId: kHiz60GameId,
                correct: _score,
                wrong: _wrong,
                leading: '⏳ $_secondsLeft sn',
                leadingColor: _secondsLeft <= 10 ? colors.danger : colors.text,
                extraLine: 'Toplam: ${formatPlayDuration(totalSeconds)} oynadın',
              ),
              if (_lastCorrect != null) ...[
                const SizedBox(height: 6),
                Text(
                  _lastCorrect! ? '✅ Doğru!' : '❌ Yanlış',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _lastCorrect! ? colors.success : colors.danger,
                  ),
                ),
              ],
              const SizedBox(height: 12),
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
    // Seçim ANINDA sonraki soruya geçildiği için burada "flash" (doğru/yanlış
    // boyama) durumu YOKTUR — şıklar her zaman tıklanabilir ve nötr görünür.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _select(i),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              CircleAvatar(radius: 13, child: Text(kQuickModeOptionLetters[i], style: const TextStyle(fontSize: 12))),
              const SizedBox(width: 12),
              Expanded(child: Text(q.secenekler[i])),
            ],
          ),
        ),
      ),
    );
  }
}
