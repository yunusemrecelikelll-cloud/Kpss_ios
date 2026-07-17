import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subject.dart';
import '../services/data_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';
import 'tools_hub_screen.dart';

class _MnemonicItem {
  final String subjectAd;
  final String topicBaslik;
  final String text;
  const _MnemonicItem({required this.subjectAd, required this.topicBaslik, required this.text});
}

/// Akılda Kalıcı Kodlama — gerçek, araştırılmış mnemonic teknikleri
/// (assets/data/mnemonics.json). Sadece Tarih ve Coğrafya konularında içerik
/// var; aynı veri topic_screen.dart'ta da konu altında gösteriliyor, burası
/// tüm teknikleri tek bir karıştırılabilir deste hâlinde sunar.
class MnemonicsScreen extends StatefulWidget {
  final List<Subject> subjects;
  const MnemonicsScreen({super.key, required this.subjects});

  @override
  State<MnemonicsScreen> createState() => _MnemonicsScreenState();
}

class _MnemonicsScreenState extends State<MnemonicsScreen> {
  final _rng = Random();
  List<_MnemonicItem>? _items;
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mnemonics = await context.read<DataService>().loadMnemonics();
    final items = <_MnemonicItem>[];
    for (final s in widget.subjects) {
      for (final t in s.konular) {
        final tips = mnemonics[t.id];
        if (tips == null) continue;
        for (final tip in tips) {
          items.add(_MnemonicItem(subjectAd: s.ad, topicBaslik: t.baslik, text: tip));
        }
      }
    }
    if (!mounted) return;
    setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    if (!storage.isPremiumUser()) {
      return const LockedFeatureCard(
        title: 'Akılda Kalıcı Kodlama',
        desc: 'Tarih ve coğrafya konuları için gerçek ezber teknikleriyle hızlı tekrar yapmak için Premium\'a geç.',
      );
    }
    if (_items == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_items!.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('🧠  Henüz içerik yüklenemedi, birazdan tekrar dene.', textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (_idx >= _items!.length) _idx = 0;
    final it = _items![_idx];
    final c = context.watch<ThemeProvider>().colors;

    return Scaffold(
      appBar: AppBar(title: const Text('🧠 Akılda Kalıcı Kodlama')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_idx + 1} / ${_items!.length}', style: TextStyle(fontSize: 13, color: c.textFaint)),
            const SizedBox(height: 14),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${it.subjectAd} • ${it.topicBaslik}',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 14),
                      Text(it.text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.5)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      context.read<SoundService>().click();
                      setState(() => _idx = (_idx - 1 + _items!.length) % _items!.length);
                    },
                    child: const Text('← Önceki'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      context.read<SoundService>().click();
                      setState(() => _idx = _rng.nextInt(_items!.length));
                    },
                    child: const Text('🔀 Karıştır'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      context.read<SoundService>().click();
                      setState(() => _idx = (_idx + 1) % _items!.length);
                    },
                    child: const Text('Sonraki →'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
