import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/question.dart';
import '../../models/subject.dart';
import '../../services/remote_question_service.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/design_system.dart';
import '../../theme/theme_provider.dart';

/// 5 şıklı sorularda ortak harf etiketleri (A-E) — Bilgi Maratonu / Günün
/// Patronu / 60 Saniye Challenge ekranlarında paylaşılır.
const List<String> kQuickModeOptionLetters = ['A', 'B', 'C', 'D', 'E'];

/// Hızlı Modlar (Hızlı Karar / Bilgi Maratonu / Günün Patronu / 60 Saniye
/// Challenge) için ortak yardımcılar ve küçük UI parçaları.
///
/// NOT: [collectAll]'a verilen `subjects` `DataService.loadAll()`'dan gelir ve
/// SADECE akademik dersleri içerir (Türkçe/Matematik/Tarih/Coğrafya/
/// Vatandaşlık/Güncel) — Harita Oyunu (lib/screens/map_game/) ayrı bir
/// özellik olduğundan ve bu ders listesinde YER ALMADIĞINDAN burada otomatik
/// olarak hariç kalır; ayrıca bir filtre gerekmez.
class QuickModesShared {
  QuickModesShared._();

  /// Verilen derslerin tüm konularından, [RemoteQuestionService.getPool] ile
  /// soru havuzlarını EŞZAMANLI (Future.wait — konu başına sırayla await
  /// ETMEDEN) çeker, her soruyu geldiği konu/ders bilgisiyle etiketler
  /// (Question.copyWith) ve karışık, TEK bir listede döner.
  ///
  /// RemoteQuestionService tamamen savunmacı olduğundan (asla hata fırlatmaz/
  /// asılı kalmaz — bkz. services/remote_question_service.dart) bu metot da
  /// network beklemeden, en kötü ihtimalle gömülü yedek sorularla hızlıca
  /// döner.
  static Future<List<Question>> collectAll(
    List<Subject> subjects,
    RemoteQuestionService remote, {
    Random? rnd,
  }) async {
    final futures = <Future<List<Question>>>[];
    final subjectIds = <String>[];
    final subjectAds = <String>[];
    final topicBasliklar = <String>[];
    for (final s in subjects) {
      for (final t in s.konular) {
        if (t.sorular.isEmpty) continue;
        futures.add(remote.getPool(t.id, t.sorular));
        subjectIds.add(s.id);
        subjectAds.add(s.ad);
        topicBasliklar.add(t.baslik);
      }
    }
    if (futures.isEmpty) return const [];
    final results = await Future.wait(futures);
    final all = <Question>[];
    for (var i = 0; i < results.length; i++) {
      for (final q in results[i]) {
        all.add(q.copyWith(subjectId: subjectIds[i], subjectAd: subjectAds[i], topicBaslik: topicBasliklar[i]));
      }
    }
    all.shuffle(rnd ?? Random());
    return all;
  }
}

/// Hızlı Modlar'ın ortak SKOR ŞERİDİ — doğru/yanlış sayısını AYRI AYRI ve
/// hemen ALTINDA kullanıcının o oyundaki "En Yüksek Skor"unu (rekorunu)
/// gösterir. Rekor [StorageService.getHighScore] ile okunur; `context.watch`
/// kullanıldığı için tur bitip yeni rekor kaydedildiğinde kendiliğinden
/// tazelenir.
///
/// [leading] soldaki serbest metindir (ör. '⏳ 42 sn' ya da 'Soru 3/25');
/// [extraLine] varsa rekor satırının altına eklenen ikinci küçük satırdır
/// (ör. toplam oynama süresi).
class QuickModeScoreBar extends StatelessWidget {
  final String gameId;
  final int correct;
  final int wrong;
  final String? leading;
  final Color? leadingColor;
  final String? extraLine;

  const QuickModeScoreBar({
    super.key,
    required this.gameId,
    required this.correct,
    required this.wrong,
    this.leading,
    this.leadingColor,
    this.extraLine,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final record = context.watch<StorageService>().getHighScore(gameId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (leading != null)
              Flexible(
                child: Text(
                  leading!,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: leadingColor ?? colors.text,
                  ),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('✓ $correct', style: TextStyle(color: colors.success, fontWeight: FontWeight.w800)),
                const SizedBox(width: 12),
                Text('✗ $wrong', style: TextStyle(color: colors.danger, fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 3),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '🏆 En Yüksek Skor: $record',
            style: TextStyle(fontSize: 11.5, color: colors.textFaint, fontWeight: FontWeight.w700),
          ),
        ),
        if (extraLine != null)
          Text(extraLine!, style: TextStyle(fontSize: 11, color: colors.textFaint)),
      ],
    );
  }
}

/// Sonuç ekranlarında kullanılan tek satırlık rekor metni — yeni rekor
/// kırıldıysa vurgulu bir mesaj döner.
///
/// NOT: Artık sonuç ekranlarında rekor AYRI bir kartta ([GameResultScreen]
/// içindeki "En Yüksek Skor" satırı + altın "🏆 YENİ REKOR" rozeti) gösterildiği
/// için bu yardımcıya yeni çağrı EKLENMEMELİDİR; sadece geriye dönük uyumluluk
/// için duruyor.
String quickModeRecordLine({required int record, required bool yeniRekor}) =>
    yeniRekor ? '🏆 YENİ REKOR! En Yüksek Skor: $record' : '🏆 En Yüksek Skor: $record';

/// ── Ortak oyun sonu istatistiği ───────────────────────────────────────────
///
/// [GameResultScreen] içindeki [DsStatStrip]'in tek bir sütunu: renkli büyük
/// bir sayı + altında emoji'li etiket. Renk çağırandan gelir (doğru için
/// `colors.success`, yanlış için `colors.danger`, rekor/puan için `colors.gold`
/// gibi) — burada SABİT renk yoktur, böylece 9 temanın hepsinde ve açık temada
/// okunur kalır.
class GameResultStat {
  final String emoji;
  final String value;
  final String label;
  final Color? color;
  const GameResultStat({
    required this.emoji,
    required this.value,
    required this.label,
    this.color,
  });
}

/// ── TÜM oyunların ortak "oyun sonu" ekranı ────────────────────────────────
///
/// Hızlı Modlar, Harita Oyunu modları ve Kart Eşleştirme aynı iskeleti kullanır:
///   1) üstte başarıya göre değişen büyük [DsIllustration] (🏆 / 🎉 / 📚 / 💪),
///   2) başlık + kısa değerlendirme cümlesi,
///   3) [DsStatStrip] ile sayısal özet (doğru / yanlış / skor / süre),
///   4) "En Yüksek Skor" satırı — yeni rekorda altın vurgulu [DsChip],
///   5) altta dolu "Tekrar Oyna" + dış çizgili "Oyunlara Dön" [DsPillButton]'ları.
///
/// İçerik ListView içinde olduğundan uzun değerlendirme metinlerinde bile
/// TAŞMA olmaz.
class GameResultScreen extends StatelessWidget {
  /// AppBar başlığı (oyunun adı).
  final String title;

  /// Üstteki illüstrasyonun emojisi — başarıya göre çağıran seçer.
  final String emoji;

  /// Büyük başlık ("Oturum Bitti!", "Zincir Tamamlandı!" gibi).
  final String headline;

  /// Başlığın altındaki kısa değerlendirme cümlesi.
  final String? message;

  /// Sayısal özet — en fazla 4 öğe önerilir (daha fazlası dar ekranda sıkışır).
  final List<GameResultStat> stats;

  /// Kalıcı rekor. null verilirse rekor satırı hiç çizilmez (rekor tutmayan
  /// oyunlarda sahte "0" göstermemek için).
  final int? highScore;

  /// Bu turda rekor kırıldı mı — altın vurgulu rozeti tetikler.
  final bool newRecord;

  /// Rekor satırının etiketi (varsayılan: "En Yüksek Skor").
  final String highScoreLabel;

  /// Alt kartta gösterilen uzun açıklama (ör. "neye çalışmalısın" yorumu).
  final String? note;

  /// Ekranın vurgu rengi — verilmezse temanın moru kullanılır.
  final Color? accent;

  /// Harita modlarının gradyan arka planı gibi ekran zemini.
  final BoxDecoration? backgroundDecoration;

  final VoidCallback? onRetry;
  final String retryLabel;
  final String backLabel;

  /// Geri dönüş davranışı — verilmezse `Navigator.pop()`.
  final VoidCallback? onBack;

  const GameResultScreen({
    super.key,
    required this.title,
    required this.emoji,
    required this.headline,
    this.message,
    this.stats = const [],
    this.highScore,
    this.newRecord = false,
    this.highScoreLabel = 'En Yüksek Skor',
    this.note,
    this.accent,
    this.backgroundDecoration,
    this.onRetry,
    this.retryLabel = 'Tekrar Oyna',
    this.backLabel = 'Oyunlara Dön',
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final vurgu = accent ?? c.violet;
    // Rekor kırıldıysa illüstrasyonun ışıması ve rekor kartı altına döner.
    final isimaRengi = newRecord ? c.gold : vurgu;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Container(
        decoration: backgroundDecoration,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Center(
                child: DsIllustration(emoji: emoji, size: 96, glowColor: isimaRengi),
              ),
              const SizedBox(height: 10),
              Text(
                headline,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c.text),
              ),
              if (message != null && message!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, height: 1.45, color: c.textDim),
                ),
              ],
              if (stats.isNotEmpty) ...[
                const SizedBox(height: 16),
                DsStatStrip(
                  items: [
                    for (final s in stats)
                      DsStatItem(
                        // Sayının kendisi "visual" olarak veriliyor ki doğru/yanlış
                        // renk token'ları (success/danger/gold) sayıya uygulanabilsin.
                        visual: Text(
                          s.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            color: s.color ?? c.text,
                          ),
                        ),
                        value: '',
                        label: '${s.emoji} ${s.label}',
                      ),
                  ],
                ),
              ],
              if (highScore != null) ...[
                const SizedBox(height: kDsGap),
                DsCard(
                  accent: newRecord ? c.gold : null,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Text('🏆', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              highScoreLabel,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: c.textDim,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$highScore',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: newRecord ? c.gold : c.text,
                            ),
                          ),
                        ],
                      ),
                      if (newRecord) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: DsChip(label: '🏆 YENİ REKOR', color: c.gold),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (note != null && note!.trim().isNotEmpty) ...[
                const SizedBox(height: kDsGap),
                DsCard(
                  child: Text(
                    note!,
                    style: TextStyle(fontSize: 12.5, height: 1.5, color: c.textDim),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              // Wrap: dar ekranda butonlar alt alta iner, asla taşmaz.
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  if (onRetry != null)
                    DsPillButton(
                      label: retryLabel,
                      leadingIcon: Icons.refresh,
                      color: vurgu,
                      onPressed: () {
                        context.read<SoundService>().click();
                        onRetry!();
                      },
                    ),
                  DsPillButton(
                    label: backLabel,
                    filled: false,
                    color: vurgu,
                    onPressed: () {
                      context.read<SoundService>().click();
                      if (onBack != null) {
                        onBack!();
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hızlı Modlar'ın "oturum bitti" kartı — artık ortak [GameResultScreen]'in
/// ince bir sarmalayıcısıdır; böylece Hızlı Modlar, Harita Oyunu ve Kart
/// Oyunu'nun sonuç ekranları TEK bir tasarım dilinden beslenir.
class QuickModeResultCard extends StatelessWidget {
  final String title;
  final String emoji;
  final String message;
  final String? subMessage;
  final VoidCallback? onRetry;
  final String retryLabel;

  /// Büyük başlık — verilmezse "Oturum Bitti!".
  final String? headline;
  final List<GameResultStat> stats;
  final int? highScore;
  final bool newRecord;
  final Color? accent;

  const QuickModeResultCard({
    super.key,
    required this.title,
    required this.emoji,
    required this.message,
    this.subMessage,
    this.onRetry,
    this.retryLabel = 'Tekrar Oyna',
    this.headline,
    this.stats = const [],
    this.highScore,
    this.newRecord = false,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GameResultScreen(
      title: title,
      emoji: emoji,
      headline: headline ?? message,
      message: headline == null ? null : message,
      stats: stats,
      highScore: highScore,
      newRecord: newRecord,
      note: subMessage,
      accent: accent,
      onRetry: onRetry,
      retryLabel: retryLabel,
    );
  }
}
