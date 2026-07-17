import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/zincirleme_bilgi_data.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../tools_hub_screen.dart';

/// Mini oyun — Zincirleme Bilgi: her doğru cevap bir sonraki sorunun
/// ipucunu/bağlantısını oluşturur (ör. Samsun'a çıkış → Amasya Genelgesi →
/// Erzurum Kongresi → Sivas Kongresi ...). Zincirler [kBilgiZincirleri]
/// içinde (lib/data/zincirleme_bilgi_data.dart) tanımlıdır; her biri gerçek,
/// doğrulanmış tarih/coğrafya/vatandaşlık bilgisidir.
const String kZincirlemeBilgiGameId = 'zincirleme-bilgi';
const List<String> kZincirOptionLetters = ['A', 'B', 'C', 'D', 'E'];

class ZincirlemeBilgiScreen extends StatelessWidget {
  const ZincirlemeBilgiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final colors = context.watch<ThemeProvider>().colors;
    final premium = storage.isPremiumUser();
    final gp = storage.getGamePlayState(kZincirlemeBilgiGameId);
    final left = (kFreeGameDailyLimit - (gp['plays'] as int)).clamp(0, kFreeGameDailyLimit);
    final passed = storage.getGamePassedTopics(kZincirlemeBilgiGameId);

    return Scaffold(
      appBar: AppBar(title: const Text('🔗 Zincirleme Bilgi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Bir bilgi zinciri seç: her doğru cevap seni bir sonraki soruya '
            'taşır. ${premium ? "Sınırsız oynarsın." : "Bugün $left zincir hakkın kaldı."}',
            style: TextStyle(fontSize: 13.5, color: colors.textFaint),
          ),
          const SizedBox(height: 16),
          for (final chain in kBilgiZincirleri)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Text(passed[chain.id] == true ? '✅' : '🔗', style: const TextStyle(fontSize: 22)),
                title: Text(chain.baslik, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${chain.adimlar.length} adımlık zincir', style: TextStyle(fontSize: 11.5, color: colors.textFaint)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  context.read<SoundService>().click();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => _ChainPlayScreen(chain: chain)),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ChainPlayScreen extends StatefulWidget {
  final BilgiZinciri chain;
  const _ChainPlayScreen({required this.chain});

  @override
  State<_ChainPlayScreen> createState() => _ChainPlayScreenState();
}

class _ChainPlayScreenState extends State<_ChainPlayScreen> {
  bool _locked = false;
  bool _booted = false;
  bool _finished = false;
  int _stepIndex = 0;
  int _score = 0;
  int _mistakes = 0;
  int? _selected;
  bool _showResult = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final storage = context.read<StorageService>();
    final premium = storage.isPremiumUser();
    if (!premium) {
      final gp = storage.getGamePlayState(kZincirlemeBilgiGameId);
      if ((gp['plays'] as int) >= kFreeGameDailyLimit) {
        if (!mounted) return;
        setState(() => _locked = true);
        return;
      }
      await storage.useGamePlay(kZincirlemeBilgiGameId);
    }
    if (!mounted) return;
    setState(() {
      _booted = true;
      _finished = false;
      _stepIndex = 0;
      _score = 0;
      _mistakes = 0;
      _selected = null;
      _showResult = false;
    });
  }

  void _retry() {
    setState(() {
      _locked = false;
      _booted = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  void _select(int i) {
    if (_showResult) return;
    context.read<SoundService>().click();
    final adim = widget.chain.adimlar[_stepIndex];
    final correct = i == adim.dogruIndex;
    setState(() {
      _selected = i;
      _showResult = true;
      if (correct) {
        _score += 10;
      } else {
        _mistakes += 1;
      }
    });
  }

  Future<void> _next() async {
    context.read<SoundService>().click();
    final isLast = _stepIndex + 1 >= widget.chain.adimlar.length;
    if (isLast) {
      final storage = context.read<StorageService>();
      await storage.markGameTopicPassed(kZincirlemeBilgiGameId, widget.chain.id);
      if (!mounted) return;
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _stepIndex += 1;
      _selected = null;
      _showResult = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return const LockedFeatureCard(
        title: 'Zincirleme Bilgi',
        desc: "Bugünkü $kFreeGameDailyLimit ücretsiz zincir hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return Scaffold(
        appBar: AppBar(title: Text('🔗 ${widget.chain.baslik}')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_finished) {
      return _buildCompletion(context);
    }
    return _buildBoard(context);
  }

  Widget _buildBoard(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final adim = widget.chain.adimlar[_stepIndex];
    final total = widget.chain.adimlar.length;

    return Scaffold(
      appBar: AppBar(title: Text('🔗 ${widget.chain.baslik}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Adım ${_stepIndex + 1}/$total', style: TextStyle(fontSize: 12.5, color: colors.textFaint)),
                Text('⭐ $_score', style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: (_stepIndex) / total, minHeight: 6),
            ),
            const SizedBox(height: 14),
            if (_stepIndex > 0)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.violet.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.violet.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '🔗 ${widget.chain.adimlar[_stepIndex - 1].ipucuSonraki}',
                  style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, height: 1.3),
                ),
              ),
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
                  Text(adim.soru, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.3)),
                  const SizedBox(height: 14),
                  for (var i = 0; i < adim.secenekler.length; i++) _buildOption(adim, i, colors),
                  if (_showResult) ...[
                    const Divider(height: 24),
                    Text('💡 ${adim.aciklama}', style: const TextStyle(fontSize: 13, height: 1.35)),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: _next,
                        child: Text(_stepIndex + 1 >= total ? 'Zinciri Bitir 🏁' : 'Sonraki İpucu →'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(ZincirAdim adim, int i, KpssColors colors) {
    Color? borderColor;
    Color? bgColor;
    if (_showResult) {
      if (i == adim.dogruIndex) {
        borderColor = colors.success;
        bgColor = colors.success.withValues(alpha: 0.12);
      } else if (i == _selected) {
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
              CircleAvatar(radius: 13, child: Text(kZincirOptionLetters[i], style: const TextStyle(fontSize: 12))),
              const SizedBox(width: 12),
              Expanded(child: Text(adim.secenekler[i])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompletion(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(title: Text('🔗 ${widget.chain.baslik}')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏁', style: TextStyle(fontSize: 44)),
                const SizedBox(height: 12),
                const Text('Zincir Tamamlandı!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  '"${widget.chain.baslik}" zincirini bitirdin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textFaint),
                ),
                const SizedBox(height: 6),
                Text('⭐ $_score puan • $_mistakes yanlış', style: TextStyle(color: colors.textFaint, fontSize: 12.5)),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        context.read<SoundService>().click();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Zincirlere Dön'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        context.read<SoundService>().click();
                        _retry();
                      },
                      child: const Text('🔄 Tekrar Oyna'),
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
