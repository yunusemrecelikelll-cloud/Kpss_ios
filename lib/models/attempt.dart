class ReviewItem {
  final String soru;
  final List<String> secenekler;
  final int dogruIndex;
  final int? verilenIndex;
  final String aciklama;
  final String? distractorAciklama;
  final String? kaynak;
  final String status; // 'dogru' | 'yanlis' | 'bos'

  const ReviewItem({
    required this.soru,
    required this.secenekler,
    required this.dogruIndex,
    required this.verilenIndex,
    required this.aciklama,
    required this.status,
    this.distractorAciklama,
    this.kaynak,
  });

  Map<String, dynamic> toJson() => {
        'soru': soru,
        'secenekler': secenekler,
        'dogruIndex': dogruIndex,
        'verilenIndex': verilenIndex,
        'aciklama': aciklama,
        'distractorAciklama': distractorAciklama,
        'kaynak': kaynak,
        'status': status,
      };

  factory ReviewItem.fromJson(Map<String, dynamic> j) => ReviewItem(
        soru: j['soru'] as String,
        secenekler: List<String>.from(j['secenekler'] as List),
        dogruIndex: j['dogruIndex'] as int,
        verilenIndex: j['verilenIndex'] as int?,
        aciklama: j['aciklama'] as String? ?? '',
        distractorAciklama: j['distractorAciklama'] as String?,
        kaynak: j['kaynak'] as String?,
        status: j['status'] as String,
      );
}

class Attempt {
  final String subjectId;
  final String subjectAd;
  final String topicId;
  final String topicBaslik;
  final int toplam;
  final int dogru;
  final int yanlis;
  final int bos;
  final int skor;
  final int sureSn;
  final DateTime tarih;
  final bool isFullTest;
  final List<ReviewItem> review;

  const Attempt({
    required this.subjectId,
    required this.subjectAd,
    required this.topicId,
    required this.topicBaslik,
    required this.toplam,
    required this.dogru,
    required this.yanlis,
    required this.bos,
    required this.skor,
    required this.sureSn,
    required this.tarih,
    required this.isFullTest,
    required this.review,
  });

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'subjectAd': subjectAd,
        'topicId': topicId,
        'topicBaslik': topicBaslik,
        'toplam': toplam,
        'dogru': dogru,
        'yanlis': yanlis,
        'bos': bos,
        'skor': skor,
        'sureSn': sureSn,
        'tarih': tarih.toIso8601String(),
        'isFullTest': isFullTest,
        'review': review.map((r) => r.toJson()).toList(),
      };

  factory Attempt.fromJson(Map<String, dynamic> j) => Attempt(
        subjectId: j['subjectId'] as String,
        subjectAd: j['subjectAd'] as String,
        topicId: j['topicId'] as String,
        topicBaslik: j['topicBaslik'] as String,
        toplam: j['toplam'] as int,
        dogru: j['dogru'] as int,
        yanlis: j['yanlis'] as int,
        bos: j['bos'] as int,
        skor: j['skor'] as int,
        sureSn: j['sureSn'] as int,
        tarih: DateTime.parse(j['tarih'] as String),
        isFullTest: j['isFullTest'] as bool? ?? false,
        review: (j['review'] as List? ?? const [])
            .map((r) => ReviewItem.fromJson(r as Map<String, dynamic>))
            .toList(),
      );
}

/// KPSS puan tahmini (P3/P93/P94) — JS: computeKpssPoints
class KpssPoints {
  final double net;
  final int p3;
  final int p93;
  final int p94;
  const KpssPoints({required this.net, required this.p3, required this.p93, required this.p94});

  /// KPSS puan tahmini. Puanlar STANDARDİZE edildiği için basit bir doğrusal
  /// modelle YAKLAŞIK üretilir: performans ORANI (net / toplam soru, 0..1) bir
  /// puan aralığına eşlenir. Böylece 10 soruluk bir testte 0 doğru artık
  /// "P3 120" gibi saçma bir değer vermez; puan performansla orantılı ve
  /// gerçekçi bir aralıkta kalır.
  ///
  /// [toplam] verilmezse (dogru+yanlis) varsayılır. Negatif net 0'a kırpılır.
  factory KpssPoints.compute({
    required int dogru,
    required int yanlis,
    int? toplam,
  }) {
    final net = double.parse((dogru - yanlis * 0.25).toStringAsFixed(2));
    final total = toplam ?? (dogru + yanlis);
    final safeTotal = total <= 0 ? 1 : total;
    final oran = (net / safeTotal).clamp(0.0, 1.0);
    // 0 net -> taban, tam doğru -> tavan (KPSS puan aralıklarına yakın).
    final p3 = (55 + oran * 40).round();
    final p93 = (52 + oran * 40).round();
    final p94 = (50 + oran * 40).round();
    return KpssPoints(net: net, p3: p3, p93: p93, p94: p94);
  }
}
