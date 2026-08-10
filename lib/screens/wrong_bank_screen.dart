import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';
import 'quiz_screen.dart';
import 'premium_screen.dart';

/// "Yanlışlarım" — kullanıcının yanlış yaptığı soruların bankası. Tasarım
/// sistemine (DsCard/DsPillButton/DsIllustration) ve tema renklerine uygun,
/// renkli gradyanlı yenilenmiş sürüm.
class WrongBankScreen extends StatefulWidget {
  const WrongBankScreen({super.key});

  @override
  State<WrongBankScreen> createState() => _WrongBankScreenState();
}

class _WrongBankScreenState extends State<WrongBankScreen> {
  // Ders adına göre emoji (rozet için); bulunamazsa ❓.
  static const Map<String, String> _dersEmoji = {
    'Türkçe': '📘',
    'Matematik': '🔢',
    'Tarih': '🏛️',
    'Coğrafya': '🌍',
    'Vatandaşlık': '⚖️',
    'Genel Kültür': '🧠',
    'Güncel Bilgiler': '📰',
    'Diğer': '📌',
  };

  void _startWrongTest(BuildContext context, List<Map<String, dynamic>> bank) {
    final shuffled = List<Map<String, dynamic>>.of(bank)..shuffle();
    final qs = shuffled.take(20).map((w) => Question(
          soru: w['soru'] as String,
          secenekler: List<String>.from(w['secenekler'] as List),
          dogruIndex: w['dogruIndex'] as int,
          aciklama: w['aciklama'] as String? ?? '',
          distractorAciklama: w['distractorAciklama'] as String?,
          kaynak: w['kaynak'] as String?,
        )).toList();
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => QuizScreen(
        subjectId: 'wrong',
        subjectAd: 'Yanlışlarım',
        topicId: 'wrong-bank',
        topicBaslik: 'Yanlışlar Testi',
        questions: qs,
        isFullTest: false,
        isWrongBankMode: true,
      ),
    ));
  }

  /// Renkli gradyanlı AppBar başlığı — kırmızı hedef rozeti + "Yanlışlarım".
  PreferredSizeWidget _appBar(BuildContext context, KpssColors c) {
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c.rose, c.roseL]),
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(color: c.rose.withValues(alpha: 0.45), blurRadius: 10),
              ],
            ),
            child: const Icon(Icons.gps_fixed_rounded, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 9),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) =>
                LinearGradient(colors: [c.roseL, c.violet]).createShader(rect),
            child: const Text(
              'Yanlışlarım',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final c = context.watch<ThemeProvider>().colors;
    final premium = storage.isPremiumUser();

    // ── Premium değil: kilit ekranı ──
    if (!premium) {
      return Scaffold(
        appBar: _appBar(context, c),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DsCard(
                accent: c.gold,
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    DsIllustration(emoji: '🔒', glowColor: c.gold, size: 84),
                    const SizedBox(height: 12),
                    Text('Yanlışlarım — Premium',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w900, color: c.text)),
                    const SizedBox(height: 8),
                    Text(
                      'Yanlış sorularını biriktir, onlara özel testlerle eksiklerini '
                      'kapat. Bu bölüm Premium ile açılır.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, height: 1.5, color: c.textDim),
                    ),
                    const SizedBox(height: 18),
                    DsPillButton(
                      label: "Premium'a Geç",
                      color: c.gold,
                      leadingIcon: Icons.workspace_premium_rounded,
                      onPressed: () {
                        context.read<SoundService>().click();
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const PremiumScreen()));
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final bank = storage.getWrongBank();

    // ── Banka boş: kutlama ──
    if (bank.isEmpty) {
      return Scaffold(
        appBar: _appBar(context, c),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DsCard(
                accent: c.mint,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    DsIllustration(emoji: '🌟', glowColor: c.mint, size: 92),
                    const SizedBox(height: 12),
                    Text('Bankan tertemiz!',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900, color: c.text)),
                    const SizedBox(height: 8),
                    Text(
                      'Henüz biriken yanlış sorun yok. Test çözdükçe yanlışların '
                      'burada toplanır ve onlara özel sınav yapabilirsin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, height: 1.5, color: c.textDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Dolu banka ──
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final q in bank) {
      final ad = q['subjectAd'] as String? ?? 'Diğer';
      (grouped[ad] ??= []).add(q);
    }
    // En çok yanlış olan ders en üstte.
    final entries = grouped.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    // Ders kartlarına dönüşümlü renkler.
    final renkler = [c.rose, c.violet, c.mint, c.gold, c.roseL, c.violetL];

    return Scaffold(
      appBar: _appBar(context, c),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Hero banner (gradyan) ──
            DsCard(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.roseL, c.violet],
              ),
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                    ),
                    child: const Text('🎯', style: TextStyle(fontSize: 30)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${bank.length} yanlış soru',
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(
                          '${entries.length} derste birikti — hatalarını hedefle, eksiklerini kapat.',
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: Colors.white.withValues(alpha: 0.9)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: kDsGap + 6),
            const DsSectionHeader(title: 'Derslere Göre'),
            const SizedBox(height: kDsGap - 2),

            // ── Ders kartları ──
            for (var i = 0; i < entries.length; i++) ...[
              _DersSatiri(
                ad: entries[i].key,
                adet: entries[i].value.length,
                toplam: bank.length,
                emoji: _dersEmoji[entries[i].key] ?? '❓',
                renk: renkler[i % renkler.length],
              ),
              const SizedBox(height: kDsGap - 2),
            ],

            const SizedBox(height: 8),
            // ── Aksiyonlar ──
            DsPillButton(
              label: 'Yanlışlarımı Sına',
              color: c.rose,
              trailingIcon: Icons.arrow_forward_rounded,
              gradient: LinearGradient(colors: [c.rose, c.violet]),
              onPressed: () {
                context.read<SoundService>().click();
                _startWrongTest(context, bank);
              },
            ),
            const SizedBox(height: 10),
            DsPillButton(
              label: 'Bankayı Temizle',
              color: c.danger,
              filled: false,
              leadingIcon: Icons.delete_outline_rounded,
              onPressed: () async {
                context.read<SoundService>().click();
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Bankayı temizle?'),
                    content: const Text(
                        'Tüm yanlış soru bankası silinsin mi? Bu işlem geri alınamaz.'),
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
                if (ok == true) await storage.clearWrongBank();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Bir dersin yanlış özeti — emoji rozeti, ad, oransal çubuk ve "N yanlış" çipi.
class _DersSatiri extends StatelessWidget {
  final String ad;
  final int adet;
  final int toplam;
  final String emoji;
  final Color renk;

  const _DersSatiri({
    required this.ad,
    required this.adet,
    required this.toplam,
    required this.emoji,
    required this.renk,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final oran = toplam == 0 ? 0.0 : adet / toplam;

    return DsCard(
      accent: renk,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          DsIconBadge(emoji: emoji, color: renk, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(ad,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800, color: c.text)),
                const SizedBox(height: 7),
                // Oransal çubuk (bu dersin toplam içindeki payı).
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: oran.clamp(0.05, 1.0),
                    minHeight: 6,
                    backgroundColor: renk.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(renk),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          DsChip(label: '$adet yanlış', color: renk),
        ],
      ),
    );
  }
}
