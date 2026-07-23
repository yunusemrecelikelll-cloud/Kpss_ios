import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/tarihleri_bil_data.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_provider.dart';
import '../tools_hub_screen.dart';
import 'quick_modes_shared.dart';

/// Mini oyun — Tarihleri Bil: bir tarihi olay/açıklama gösterilir, altında 2
/// yıl seçeneği (doğru yıl + yakın ama yanlış bir çeldirici yıl) sunulur.
/// Soru başına [kTarihleriBilSureSn] saniye süre vardır; süre dolarsa
/// otomatik yanlış sayılır. Veriler [kTarihOlaylari] içinde (bkz.
/// lib/data/tarihleri_bil_data.dart) tanımlıdır — KPSS'de sık çıkan gerçek
/// Osmanlı/Cumhuriyet tarihi olayları ve doğrulanmış tarihler.
const String kTarihleriBilGameId = 'tarihleri-bil';
const int kTarihleriBilSoruSayisi = 25;
const int kTarihleriBilSureSn = 8;

/// Cevap YANLIŞ (ya da süre doldu) olduğunda doğru yılın ekranda kaldığı süre
/// — bu sırada soru sayacı DURUR ve sonraki soruya otomatik geçilir. Doğru
/// cevapta ise hiç beklenmez. (Yazım Yanlışları ile AYNI davranış.)
const Duration kTarihleriBilYanlisBekleme = Duration(milliseconds: 1800);

class TarihleriBilScreen extends StatefulWidget {
  const TarihleriBilScreen({super.key});

  @override
  State<TarihleriBilScreen> createState() => _TarihleriBilScreenState();
}

class _TBOption {
  final int yil;
  final bool dogruMu;
  _TBOption(this.yil, this.dogruMu);
}

class _TarihleriBilScreenState extends State<TarihleriBilScreen> {
  final Random _rnd = Random();

  bool _locked = false;
  bool _booted = false;
  bool _finished = false;

  final List<TarihOlay> _order = [];
  int _index = 0;
  List<_TBOption> _options = [];
  int _correctCount = 0;
  int _wrongCount = 0;
  int _secondsLeft = kTarihleriBilSureSn;
  bool _answered = false;
  bool _lastCorrect = false;
  int? _selectedYil;
  Timer? _ticker;

  /// Yanlış cevaptan sonra sonraki soruya otomatik geçişi sağlayan zamanlayıcı.
  Timer? _autoNext;
  bool _yeniRekor = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _autoNext?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    final storage = context.read<StorageService>();
    final premium = storage.isPremiumUser();
    if (!premium) {
      final gp = storage.getGamePlayState(kTarihleriBilGameId);
      if ((gp['plays'] as int) >= kFreeGameDailyLimit + storage.getExtraPlays(kTarihleriBilGameId)) {
        if (!mounted) return;
        setState(() => _locked = true);
        return;
      }
      await storage.useGamePlay(kTarihleriBilGameId);
    }
    if (!mounted) return;

    final shuffled = List<TarihOlay>.from(kTarihOlaylari)..shuffle(_rnd);
    final count = min(kTarihleriBilSoruSayisi, shuffled.length);
    setState(() {
      _order
        ..clear()
        ..addAll(shuffled.take(count));
      _index = 0;
      _correctCount = 0;
      _wrongCount = 0;
      _finished = false;
      _booted = true;
    });
    _startQuestion();
  }

  void _startQuestion() {
    final item = _order[_index];
    final opts = [_TBOption(item.dogruYil, true), _TBOption(item.celdiriciYil, false)]..shuffle(_rnd);
    context.read<SoundService>().resetTickPhase();
    setState(() {
      _options = opts;
      _secondsLeft = kTarihleriBilSureSn;
      _answered = false;
      _lastCorrect = false;
      _selectedYil = null;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted || _answered) return;
    setState(() => _secondsLeft--);
    if (_secondsLeft <= 3 && _secondsLeft > 0) {
      context.read<SoundService>().tick();
    }
    if (_secondsLeft <= 0) {
      _ticker?.cancel();
      _answer(null);
    }
  }

  /// Cevap işlenir. DOĞRUYSA hiç beklemeden sonraki soruya geçilir; YANLIŞSA
  /// (ya da süre dolduysa) süre durur, doğru yıl gösterilir ve
  /// [kTarihleriBilYanlisBekleme] kadar sonra otomatik olarak sonraki soruya
  /// geçilir.
  void _answer(int? yil) {
    if (_answered) return;
    _ticker?.cancel(); // süre DURUR
    if (yil != null) context.read<SoundService>().click();
    final item = _order[_index];
    final correct = yil == item.dogruYil;
    setState(() {
      _answered = true;
      _selectedYil = yil;
      _lastCorrect = correct;
      if (correct) {
        _correctCount++;
      } else {
        _wrongCount++;
      }
    });
    if (correct) {
      _next();
    } else {
      _autoNext?.cancel();
      _autoNext = Timer(kTarihleriBilYanlisBekleme, () {
        if (!mounted) return;
        _next();
      });
    }
  }

  void _next() {
    _autoNext?.cancel();
    final isLast = _index + 1 >= _order.length;
    if (isLast) {
      _finish();
      return;
    }
    setState(() => _index++);
    _startQuestion();
  }

  /// Test bitti: doğru sayısını rekor olarak kaydeder.
  Future<void> _finish() async {
    setState(() => _finished = true);
    final storage = context.read<StorageService>();
    final yeni = await storage.submitHighScore(kTarihleriBilGameId, _correctCount);
    await storage.setLastRoundStats(kTarihleriBilGameId, correct: _correctCount, wrong: _wrongCount);
    if (!mounted) return;
    setState(() => _yeniRekor = yeni);
  }

  void _retry() {
    _autoNext?.cancel();
    setState(() {
      _locked = false;
      _booted = false;
      _yeniRekor = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return LockedFeatureCard(
        gameId: kTarihleriBilGameId,
        oyunAdi: 'Tarihleri Bil',
        onUnlocked: () => setState(() => _locked = false),

        title: 'Tarihleri Bil',
        desc: "Bugünkü ücretsiz Tarihleri Bil hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return Scaffold(
        appBar: AppBar(title: const Text('📅 Tarihleri Bil')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_finished) {
      final colors = context.watch<ThemeProvider>().colors;
      final basari = _correctCount >= (_order.length * 0.7);
      final record = context.watch<StorageService>().getHighScore(kTarihleriBilGameId);
      final isabet = _order.isEmpty ? 0 : (_correctCount * 100 / _order.length).round();
      return GameResultScreen(
        title: '📅 Tarihleri Bil',
        emoji: _yeniRekor ? '🏆' : (basari ? '🎉' : (isabet >= 40 ? '💪' : '📚')),
        headline: _yeniRekor
            ? 'Yeni rekor kırdın!'
            : (basari ? 'Tarihlere hâkimsin!' : 'Tur bitti'),
        message: '${_order.length} tarihten $_correctCount tanesini doğru bildin.',
        stats: [
          GameResultStat(emoji: '✅', value: '$_correctCount', label: 'Doğru', color: colors.success),
          GameResultStat(emoji: '❌', value: '$_wrongCount', label: 'Yanlış', color: colors.danger),
          GameResultStat(emoji: '🎯', value: '%$isabet', label: 'İsabet'),
        ],
        highScore: record,
        newRecord: _yeniRekor,
        onRetry: _retry,
      );
    }
    return _buildBoard(context);
  }

  Widget _buildBoard(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final progress = _index / _order.length;
    final olay = _order[_index].olay;
    return Scaffold(
      appBar: AppBar(title: const Text('📅 Tarihleri Bil')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            QuickModeScoreBar(
              gameId: kTarihleriBilGameId,
              correct: _correctCount,
              wrong: _wrongCount,
              leading: '${_index + 1}/${_order.length}',
              leadingColor: colors.textFaint,
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: progress, minHeight: 6),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.glass2,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.border),
              ),
              child: Text(
                olay,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.35),
              ),
            ),
            const SizedBox(height: 18),
            Center(child: _buildCountdownRing(colors)),
            const SizedBox(height: 18),
            Text(
              'Hangi yıl?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: colors.textFaint, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final opt in _options) _buildOption(opt, colors),
            // Doğru cevapta anında sonraki soruya geçildiği için bu panel
            // pratikte YALNIZCA yanlış cevap / süre dolması durumunda görünür.
            if (_answered && !_lastCorrect) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.danger.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _selectedYil == null
                          ? '⏰ Süre doldu! Doğru yıl: ${_order[_index].dogruYil}'
                          : '❌ Doğru yıl: ${_order[_index].dogruYil}',
                      style: TextStyle(fontWeight: FontWeight.w800, color: colors.danger),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _index + 1 >= _order.length ? 'Test bitiyor...' : 'Sonraki soruya geçiliyor...',
                      style: TextStyle(fontSize: 11.5, color: colors.textFaint),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownRing(KpssColors colors) {
    final ratio = (_secondsLeft / kTarihleriBilSureSn).clamp(0.0, 1.0);
    final ringColor = _secondsLeft <= 3 ? colors.danger : colors.violet;
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
              value: ratio,
              strokeWidth: 5,
              color: ringColor,
              backgroundColor: colors.border,
            ),
          ),
          Text('$_secondsLeft', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: ringColor)),
        ],
      ),
    );
  }

  Widget _buildOption(_TBOption opt, KpssColors colors) {
    Color? borderColor;
    Color? bgColor;
    if (_answered) {
      if (opt.dogruMu) {
        borderColor = colors.success;
        bgColor = colors.success.withValues(alpha: 0.12);
      } else if (opt.yil == _selectedYil) {
        borderColor = colors.danger;
        bgColor = colors.danger.withValues(alpha: 0.12);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: !_answered ? () => _answer(opt.yil) : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor ?? colors.border),
            color: bgColor,
          ),
          child: Text(
            '${opt.yil}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
        ),
      ),
    );
  }
}
