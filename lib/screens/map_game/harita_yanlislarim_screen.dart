import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/turkey_map_data.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/theme_provider.dart';
import 'map_shared.dart';

/// Harita YANLIŞLARIM bankası (kullanıcı isteği): harita oyunlarında yanlış
/// işaretlenen iller, doğrularıyla birlikte HARİTA ÜZERİNDE gösterilir; neden
/// yanlış olduğunun açıklaması yer alır ve "tekrar test et" ile yeniden
/// çözülebilir. Yanlışlar bankası mantığı (bkz. StorageService.getMapWrongBank).
class HaritaYanlislarimScreen extends StatefulWidget {
  const HaritaYanlislarimScreen({super.key});

  @override
  State<HaritaYanlislarimScreen> createState() =>
      _HaritaYanlislarimScreenState();
}

class _HaritaYanlislarimScreenState extends State<HaritaYanlislarimScreen> {
  List<Map<String, dynamic>> _liste = [];

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  void _yukle() {
    setState(() => _liste = context.read<StorageService>().getMapWrongBank());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('🗺️❌ Harita Yanlışlarım'),
        actions: [
          if (_liste.isNotEmpty) ...[
            IconButton(
              tooltip: 'Tümünü test et',
              icon: const Icon(Icons.quiz_outlined),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _YanlisTestScreen(liste: _liste)));
                _yukle();
              },
            ),
            IconButton(
              tooltip: 'Yanlışları temizle',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final storage = context.read<StorageService>();
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    content: const Text(
                        'Tüm harita yanlışların temizlensin mi?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Vazgeç')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Temizle')),
                    ],
                  ),
                );
                if (ok == true) {
                  await storage.clearMapWrongBank();
                  if (mounted) _yukle();
                }
              },
            ),
          ],
        ],
      ),
      body: _liste.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🎉', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text('Harita yanlışın yok!',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: c.text)),
                    const SizedBox(height: 6),
                    Text(
                      'Harita oyunlarında yanlış işaretlediğin iller burada '
                      'toplanır; nedeniyle birlikte gösterilir ve tekrar test '
                      'edebilirsin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: c.textFaint),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: _liste.length,
              itemBuilder: (context, i) => _YanlisKart(
                kayit: _liste[i],
                onSil: () async {
                  await context.read<StorageService>().removeMapWrong(
                      _liste[i]['soru'] as String,
                      _liste[i]['dogruId'] as String);
                  _yukle();
                },
              ),
            ),
    );
  }
}

class _YanlisKart extends StatelessWidget {
  final Map<String, dynamic> kayit;
  final VoidCallback onSil;
  const _YanlisKart({required this.kayit, required this.onSil});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final dogruId = kayit['dogruId'] as String;
    final secilenIds =
        List<String>.from((kayit['secilenIds'] as List?) ?? const []);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${kayit['modAd'] ?? ''} • ${kayit['soru'] ?? ''}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: c.text),
                  ),
                ),
                IconButton(
                  tooltip: 'Bankadan çıkar',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.check_circle_outline,
                      size: 20, color: c.success),
                  onPressed: onSil,
                ),
              ],
            ),
          ),
          // Harita: doğru (yeşil) + yanlış işaretlenenler (kırmızı).
          SizedBox(
            height: 200,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: TurkeyMapCanvas(
                provinces: kTurkeyProvinces,
                colorFor: (p) {
                  if (p.id == dogruId) return c.success;
                  if (secilenIds.contains(p.id)) return c.danger;
                  return c.textFaint.withValues(alpha: 0.14);
                },
              ),
            ),
          ),
          // Lejant.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                _lejant(c.success, 'Doğru: ${kayit['dogruAd']}'),
                const SizedBox(width: 14),
                _lejant(c.danger, 'Senin seçimin'),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: c.warn.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.warn.withValues(alpha: 0.35)),
            ),
            child: Text('💡 ${kayit['aciklama'] ?? ''}',
                style: TextStyle(fontSize: 12, height: 1.4, color: c.text)),
          ),
        ],
      ),
    );
  }

  Widget _lejant(Color renk, String metin) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 12,
            height: 12,
            decoration:
                BoxDecoration(color: renk, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(metin, style: TextStyle(fontSize: 11, color: renk)),
      ],
    );
  }
}

/// Yanlışları TEKRAR TEST etme akışı: her soruda doğru ili haritada bul.
/// Doğru bulunca kayıt bankadan çıkarılır.
class _YanlisTestScreen extends StatefulWidget {
  final List<Map<String, dynamic>> liste;
  const _YanlisTestScreen({required this.liste});

  @override
  State<_YanlisTestScreen> createState() => _YanlisTestScreenState();
}

class _YanlisTestScreenState extends State<_YanlisTestScreen> {
  int _i = 0;
  bool _sonuc = false;
  bool _dogruMu = false;
  int _cozulen = 0;

  Map<String, dynamic> get _k => widget.liste[_i];

  void _tap(TurkeyProvince p) {
    if (_sonuc) return;
    context.read<SoundService>().click();
    // Bölge/Komşu modlarında tek doğru il yoktur: kaydedilen `dogruIds`
    // listesindeki HERHANGİ bir il doğru sayılır. Diğer modlarda tek `dogruId`.
    final dogruIds = (_k['dogruIds'] as List?)?.cast<String>() ?? const <String>[];
    final dogru = dogruIds.isNotEmpty
        ? dogruIds.contains(p.id)
        : p.id == _k['dogruId'];
    setState(() {
      _sonuc = true;
      _dogruMu = dogru;
    });
    if (dogru) {
      _cozulen++;
      context
          .read<StorageService>()
          .removeMapWrong(_k['soru'] as String, _k['dogruId'] as String? ?? '');
    }
  }

  void _next() {
    if (_i + 1 >= widget.liste.length) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _i++;
      _sonuc = false;
      _dogruMu = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final dogruId = _k['dogruId'] as String;
    return Scaffold(
      appBar: AppBar(title: Text('Tekrar Test • ${_i + 1}/${widget.liste.length}')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('${_k['soru']}?',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: c.text)),
            ),
            Expanded(
              child: TurkeyMapCanvas(
                provinces: kTurkeyProvinces,
                colorFor: (p) {
                  if (_sonuc && p.id == dogruId) return c.success;
                  return mapNeutral(context, 0.30);
                },
                onTap: _sonuc ? null : _tap,
              ),
            ),
            if (_sonuc)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                color: (_dogruMu ? c.success : c.danger).withValues(alpha: 0.12),
                child: Column(
                  children: [
                    Text(
                      _dogruMu
                          ? '✅ Doğru! (${_k['dogruAd']}) — bankadan çıkarıldı.'
                          : '❌ Yanlış. Doğrusu: ${_k['dogruAd']}.',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, color: c.text),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _next,
                        child: Text(_i + 1 < widget.liste.length
                            ? 'Sonraki →'
                            : 'Bitir (çözülen: $_cozulen)'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
