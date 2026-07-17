import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/question.dart';
import '../../models/subject.dart';
import '../../services/remote_question_service.dart';
import '../../services/sound_service.dart';
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

/// Hızlı Modlar'ın ortak "oturum bitti" sonuç kartı — harita oyununun
/// MapSessionResult'ına görsel olarak benzer, ama Hızlı Modlar kendi
/// klasöründe bağımsız kalsın diye burada ayrıca tanımlandı.
class QuickModeResultCard extends StatelessWidget {
  final String title;
  final String emoji;
  final String message;
  final String? subMessage;
  final VoidCallback? onRetry;
  final String retryLabel;
  const QuickModeResultCard({
    super.key,
    required this.title,
    required this.emoji,
    required this.message,
    this.subMessage,
    this.onRetry,
    this.retryLabel = '🔄 Tekrar Oyna',
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 44)),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                if (subMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(subMessage!, textAlign: TextAlign.center, style: TextStyle(color: colors.textFaint, height: 1.5)),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (onRetry != null)
                      ElevatedButton(
                        onPressed: () {
                          context.read<SoundService>().click();
                          onRetry!();
                        },
                        child: Text(retryLabel),
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
}
