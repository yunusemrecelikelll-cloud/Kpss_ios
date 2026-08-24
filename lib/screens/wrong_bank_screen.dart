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
import '../utils/ust_bildirim.dart';

/// Ücretsiz kullanıcının GÜNDE çözebileceği yanlış soru sayısı (kullanıcı isteği:
/// Yanlışlarım ücretsize açık ama günlük belli sayıda; üstü Premium). Premium'da
/// sınırsız.
const int kFreeWrongBankDaily = 15;

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

  Future<void> _startWrongTest(BuildContext context,
      List<Map<String, dynamic>> bank,
      {required bool premium, required StorageService storage}) async {
    // Ücretsiz: günlük kalan hak kadar soru; premium: 20'lik normal tur.
    int limit = 20;
    if (!premium) {
      final kalan = (kFreeWrongBankDaily - storage.getWrongBankSolvedToday())
          .clamp(0, kFreeWrongBankDaily);
      if (kalan <= 0) {
        ustBildirim(
          'Bugünkü ücretsiz Yanlışlarım hakkın ($kFreeWrongBankDaily soru) doldu. '
          'Sınırsız çözmek için Premium\'a geç.',
          tur: UstBildirimTuru.hata,
        );
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PremiumScreen()));
        return;
      }
      limit = kalan < 20 ? kalan : 20;
    }
    final shuffled = List<Map<String, dynamic>>.of(bank)..shuffle();
    final adet = limit < bank.length ? limit : bank.length;
    final qs = shuffled.take(adet).map((w) => Question(
          soru: w['soru'] as String,
          secenekler: List<String>.from(w['secenekler'] as List),
          dogruIndex: w['dogruIndex'] as int,
          aciklama: w['aciklama'] as String? ?? '',
          distractorAciklama: w['distractorAciklama'] as String?,
          kaynak: w['kaynak'] as String?,
        )).toList();
    // Ücretsizde günlük sayaç, tur başlarken çözülecek soru kadar artar.
    if (!premium) await storage.addWrongBankSolvedToday(adet);
    if (!context.mounted) return;
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

    // NOT: Yanlışlarım artık ÜCRETSİZE de AÇIK (kullanıcı isteği). Ücretsiz
    // kullanıcı günde en fazla [kFreeWrongBankDaily] yanlış soru çözebilir;
    // üstü Premium. Kilit kaldırıldı; aşağıda ücretsize günlük hak bilgisi
    // gösterilir ve "Yanlışlarımı Sına" o hakka göre sınırlanır.
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
            // ── Ücretsiz günlük hak bilgisi (premium değilse) ──
            if (!premium) ...[
              Builder(builder: (_) {
                final kalan = (kFreeWrongBankDaily -
                        storage.getWrongBankSolvedToday())
                    .clamp(0, kFreeWrongBankDaily);
                return Container(
                  padding: const EdgeInsets.all(13),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: c.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.gold.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 18, color: c.gold),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Ücretsiz: bugün $kalan / $kFreeWrongBankDaily yanlış soru '
                          'çözebilirsin. Sınırsız çözmek için Premium’a geç.',
                          style: TextStyle(
                              fontSize: 12, height: 1.35, color: c.textDim,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            // ── Aksiyonlar ──
            DsPillButton(
              label: 'Yanlışlarımı Sına',
              color: c.rose,
              trailingIcon: Icons.arrow_forward_rounded,
              gradient: LinearGradient(colors: [c.rose, c.violet]),
              onPressed: () {
                context.read<SoundService>().click();
                _startWrongTest(context, bank,
                    premium: premium, storage: storage);
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
