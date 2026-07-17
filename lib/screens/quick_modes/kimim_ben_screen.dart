import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/kimim_ben_data.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../tools_hub_screen.dart';

/// Mini oyun — Kimim Ben: ipuçları sırayla açılır (genelden özele), ilk
/// ipucunda bilen daha fazla puan alır (100 → 60 → 30, azalan puan sistemi).
/// Kişiler [kKimimBenKisiler] içinde (lib/data/kimim_ben_data.dart)
/// tanımlıdır — KPSS'de sık geçen gerçek Osmanlı padişahları, Cumhuriyet
/// dönemi ve tarihi/edebi şahsiyetler.
const String kKimimBenGameId = 'kimim-ben';
const int kKimimBenRoundCount = 10;
const List<int> kKimimBenClueScores = [100, 60, 30];

class KimimBenScreen extends StatefulWidget {
  const KimimBenScreen({super.key});

  @override
  State<KimimBenScreen> createState() => _KimimBenScreenState();
}

class _KimimBenRound {
  final KimimBenKisi kisi;
  final List<String> secenekler; // 4 isim (doğrusu dahil), karışık sırada
  _KimimBenRound(this.kisi, this.secenekler);
}

class _KimimBenScreenState extends State<KimimBenScreen> {
  final Random _rnd = Random();

  bool _locked = false;
  bool _booted = false;
  bool _finished = false;

  final List<KimimBenKisi> _order = [];
  int _roundIndex = 0;
  _KimimBenRound? _round;
  int _clueIndex = 0;
  int _totalScore = 0;
  int _correctCount = 0;
  String? _selectedName;
  bool _showResult = false;
  bool _lastCorrect = false;
  int _lastPoints = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final storage = context.read<StorageService>();
    final premium = storage.isPremiumUser();
    if (!premium) {
      final gp = storage.getGamePlayState(kKimimBenGameId);
      if ((gp['plays'] as int) >= kFreeGameDailyLimit) {
        if (!mounted) return;
        setState(() => _locked = true);
        return;
      }
      await storage.useGamePlay(kKimimBenGameId);
    }
    if (!mounted) return;

    final shuffled = List<KimimBenKisi>.from(kKimimBenKisiler)..shuffle(_rnd);
    final count = min(kKimimBenRoundCount, shuffled.length);
    setState(() {
      _order
        ..clear()
        ..addAll(shuffled.take(count));
      _roundIndex = 0;
      _totalScore = 0;
      _correctCount = 0;
      _finished = false;
      _booted = true;
      _round = _buildRound(_order[0]);
      _clueIndex = 0;
      _showResult = false;
      _selectedName = null;
    });
  }

  _KimimBenRound _buildRound(KimimBenKisi kisi) {
    final others = kKimimBenKisiler.where((k) => k.isim != kisi.isim).toList()..shuffle(_rnd);
    final distractors = others.take(3).map((k) => k.isim).toList();
    final options = [kisi.isim, ...distractors]..shuffle(_rnd);
    return _KimimBenRound(kisi, options);
  }

  void _retry() {
    setState(() {
      _locked = false;
      _booted = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  void _revealNextClue() {
    if (_showResult || _clueIndex >= 2) return;
    context.read<SoundService>().click();
    setState(() => _clueIndex += 1);
  }

  void _guess(String name) {
    if (_showResult || _round == null) return;
    context.read<SoundService>().click();
    final correct = name == _round!.kisi.isim;
    final points = correct ? kKimimBenClueScores[_clueIndex] : 0;
    setState(() {
      _selectedName = name;
      _showResult = true;
      _lastCorrect = correct;
      _lastPoints = points;
      _totalScore += points;
      if (correct) _correctCount += 1;
    });
  }

  void _next() {
    context.read<SoundService>().click();
    final isLast = _roundIndex + 1 >= _order.length;
    if (isLast) {
      setState(() => _finished = true);
      return;
    }
    final nextIndex = _roundIndex + 1;
    setState(() {
      _roundIndex = nextIndex;
      _round = _buildRound(_order[nextIndex]);
      _clueIndex = 0;
      _showResult = false;
      _selectedName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return const LockedFeatureCard(
        title: 'Kimim Ben',
        desc: "Bugünkü $kFreeGameDailyLimit ücretsiz Kimim Ben hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return Scaffold(
        appBar: AppBar(title: const Text('🕵️ Kimim Ben')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_finished) {
      return _buildResult(context);
    }
    return _buildBoard(context);
  }

  Widget _buildResult(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(title: const Text('🕵️ Kimim Ben')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🕵️', style: TextStyle(fontSize: 44)),
                const SizedBox(height: 12),
                const Text('Oturum Bitti!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  '$_correctCount/${_order.length} kişiyi doğru bildin!',
                  style: TextStyle(color: colors.textFaint),
                ),
                const SizedBox(height: 6),
                Text('⭐ Toplam puan: $_totalScore', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
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
                      child: const Text('🔄 Tekrar Oyna'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        context.read<SoundService>().click();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Menüye Dön'),
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

  Widget _buildBoard(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final round = _round;
    if (round == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final revealed = round.kisi.ipuclari.take(_clueIndex + 1).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('🕵️ Kimim Ben')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Kişi ${_roundIndex + 1}/${_order.length}', style: TextStyle(fontSize: 12.5, color: colors.textFaint)),
                Text('⭐ $_totalScore', style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: _roundIndex / _order.length, minHeight: 6),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.glass2,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Bu ipucu için: ${kKimimBenClueScores[_clueIndex]} puan',
                    style: TextStyle(fontSize: 11.5, color: colors.textFaint, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < revealed.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${i + 1}. ', style: const TextStyle(fontWeight: FontWeight.w800)),
                          Expanded(child: Text(revealed[i], style: const TextStyle(fontSize: 14.5, height: 1.3))),
                        ],
                      ),
                    ),
                  if (!_showResult && _clueIndex < 2)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _revealNextClue,
                        child: const Text('Sonraki İpucu →'),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Kim bu kişi?', style: TextStyle(fontSize: 12.5, color: colors.textFaint, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final name in round.secenekler) _buildOption(round, name, colors),
            if (_showResult) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_lastCorrect ? colors.success : colors.danger).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: (_lastCorrect ? colors.success : colors.danger).withValues(alpha: 0.4)),
                ),
                child: Text(
                  _lastCorrect
                      ? '✅ Doğru! +$_lastPoints puan'
                      : '❌ Doğru cevap: ${round.kisi.isim}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: _lastCorrect ? colors.success : colors.danger),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _next,
                  child: Text(_roundIndex + 1 >= _order.length ? 'Bitir 🏁' : 'Sonraki Kişi →'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOption(_KimimBenRound round, String name, KpssColors colors) {
    Color? borderColor;
    Color? bgColor;
    if (_showResult) {
      if (name == round.kisi.isim) {
        borderColor = colors.success;
        bgColor = colors.success.withValues(alpha: 0.12);
      } else if (name == _selectedName) {
        borderColor = colors.danger;
        bgColor = colors.danger.withValues(alpha: 0.12);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: !_showResult ? () => _guess(name) : null,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor ?? colors.border),
            color: bgColor,
          ),
          child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
