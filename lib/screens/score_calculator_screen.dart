import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/sound_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';

/// KPSS Puan Hesaplama (tahmini) — Genel Kültür (Tarih/Coğrafya/Vatandaşlık/
/// Güncel Bilgiler) ve Genel Yetenek (Türkçe/Matematik) derslerinin her biri
/// için girilen Doğru VE Boş sayısından Yanlış (soruSayısı - Doğru - Boş)
/// otomatik hesaplanır, ardından Net (Doğru - Yanlış/4) bulunur — gerçek KPSS
/// kuralında 4 yanlış 1 doğruyu götürür. Tüm derslerin Net toplamından KABA
/// bir KPSS puanı tahmini üretilir.
///
/// ÖNEMLİ: ÖSYM'nin gerçek puanlama formülü o yıl sınava giren TÜM adayların
/// ortalamasına ve standart sapmasına dayanır ve önceden KESİN OLARAK
/// bilinemez. Buradaki basit ölçekleme SADECE kabaca bir fikir vermek
/// içindir — ekranda bu durum AÇIKÇA belirtilir. Herkese açık, ücretsiz bir
/// araçtır; premium/günlük oyun hakkı kısıtlaması YOKTUR.
class _ScoreSubject {
  final String ad;
  final int soruSayisi;
  const _ScoreSubject(this.ad, this.soruSayisi);
}

const List<_ScoreSubject> _kGenelKultur = [
  _ScoreSubject('Tarih', 27),
  _ScoreSubject('Coğrafya', 18),
  _ScoreSubject('Vatandaşlık', 9),
  _ScoreSubject('Güncel Bilgiler', 6),
];

const List<_ScoreSubject> _kGenelYetenek = [
  _ScoreSubject('Türkçe', 30),
  _ScoreSubject('Matematik', 30),
];

class ScoreCalculatorScreen extends StatefulWidget {
  const ScoreCalculatorScreen({super.key});

  @override
  State<ScoreCalculatorScreen> createState() => _ScoreCalculatorScreenState();
}

class _ScoreCalculatorScreenState extends State<ScoreCalculatorScreen> {
  final Map<String, TextEditingController> _dogruCtrl = {};
  final Map<String, TextEditingController> _bosCtrl = {};

  @override
  void initState() {
    super.initState();
    for (final s in [..._kGenelKultur, ..._kGenelYetenek]) {
      _dogruCtrl[s.ad] = TextEditingController();
      _bosCtrl[s.ad] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _dogruCtrl.values) {
      c.dispose();
    }
    for (final c in _bosCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _intOf(TextEditingController c, int maxValue) {
    final v = int.tryParse(c.text.trim()) ?? 0;
    return v.clamp(0, maxValue);
  }

  int _dogruOf(_ScoreSubject s) => _intOf(_dogruCtrl[s.ad]!, s.soruSayisi);
  int _bosOf(_ScoreSubject s) => _intOf(_bosCtrl[s.ad]!, s.soruSayisi);

  // Kullanıcı Doğru VE Boş sayısını girer; Yanlış, kalan sorular üzerinden
  // otomatik hesaplanır (Doğru + Boş, soru sayısını aşarsa 0'a sabitlenir).
  int _yanlisOf(_ScoreSubject s) => (s.soruSayisi - _dogruOf(s) - _bosOf(s)).clamp(0, s.soruSayisi);

  double _netOf(_ScoreSubject s) => _dogruOf(s) - (_yanlisOf(s) / 4);

  double get _toplamNet {
    var toplam = 0.0;
    for (final s in [..._kGenelKultur, ..._kGenelYetenek]) {
      toplam += _netOf(s);
    }
    return toplam;
  }

  int get _toplamSoru {
    var toplam = 0;
    for (final s in [..._kGenelKultur, ..._kGenelYetenek]) {
      toplam += s.soruSayisi;
    }
    return toplam;
  }

  /// Basit, KESİN OLMAYAN bir tahmini ölçekleme: 0 net ≈ 50 puan, tam net
  /// (120/120) ≈ 100 puan civarına yaklaşır. Gerçek ÖSYM formülü DEĞİLDİR.
  double get _tahminiPuan {
    final puan = 50 + (_toplamNet / _toplamSoru) * 50;
    return puan.clamp(0, 100);
  }

  void _sifirla() {
    context.read<SoundService>().click();
    setState(() {
      for (final c in _dogruCtrl.values) {
        c.clear();
      }
      for (final c in _bosCtrl.values) {
        c.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('🧮 Puan Hesaplama'),
        actions: [
          IconButton(
            tooltip: 'Sıfırla',
            onPressed: _sifirla,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionCard('Genel Kültür', _kGenelKultur, colors),
            const SizedBox(height: 14),
            _buildSectionCard('Genel Yetenek', _kGenelYetenek, colors),
            const SizedBox(height: 18),
            _buildResultCard(colors),
            const SizedBox(height: 14),
            _buildWarning(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(String title, List<_ScoreSubject> subjects, KpssColors colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.glass2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final s in subjects) _buildSubjectRow(s, colors),
        ],
      ),
    );
  }

  Widget _buildSubjectRow(_ScoreSubject s, KpssColors colors) {
    final net = _netOf(s);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${s.ad} (${s.soruSayisi})',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.textDim),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _buildNumField('Doğru', _dogruCtrl[s.ad]!, colors)),
              const SizedBox(width: 8),
              Expanded(child: _buildNumField('Boş', _bosCtrl[s.ad]!, colors)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildYanlisDisplay(_yanlisOf(s), colors)),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: colors.violet.withValues(alpha: 0.12),
                    border: Border.all(color: colors.violet.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    children: [
                      Text('Net', style: TextStyle(fontSize: 10.5, color: colors.textFaint, fontWeight: FontWeight.w700)),
                      Text(net.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildYanlisDisplay(int yanlis, KpssColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: colors.glass,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Text('Yanlış', style: TextStyle(fontSize: 11.5, color: colors.textFaint, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('$yanlis', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildNumField(String label, TextEditingController ctrl, KpssColors colors) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w700),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: TextStyle(fontSize: 11.5, color: colors.textFaint),
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildResultCard(KpssColors colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [colors.violet.withValues(alpha: 0.18), colors.rose.withValues(alpha: 0.14)]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.violet.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Toplam Net', style: TextStyle(fontSize: 12.5, color: colors.textFaint, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(_toplamNet.toStringAsFixed(2), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              Container(width: 1, height: 44, color: colors.border),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('KPSS Puanı (tahmini)', style: TextStyle(fontSize: 12.5, color: colors.textFaint, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(_tahminiPuan.toStringAsFixed(2), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: colors.violet)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: colors.violet.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '❕ 4 Yanlış 1 Doğruyu Götürür',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: colors.textDim),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarning(KpssColors colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.warn.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bu hesaplama tahminidir ve gerçek ÖSYM formülüne dayanmaz. '
              'ÖSYM puanı, o dönem sınava giren tüm adayların ortalama ve standart sapmasına göre hesaplanır ve önceden kesin olarak bilinemez. '
              'Kesin sonuçlar yalnızca ÖSYM tarafından açıklanır.',
              style: TextStyle(fontSize: 12, color: colors.textDim, height: 1.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
