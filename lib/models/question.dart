class Question {
  final String soru;
  final List<String> secenekler;
  final int dogruIndex;
  final String aciklama;
  final String? distractorAciklama;
  final String? kaynak;
  // Tam deneme / ders sınavı gibi karma testlerde sorunun hangi konudan geldiğini
  // hatırlamak için kullanılır (JS tarafındaki q._topicBaslik / q._sid karşılığı).
  final String? topicBaslik;
  final String? subjectId;
  final String? subjectAd;
  /// Sorunun hangi sınav türüne özel olduğu: 'lisans' | 'onlisans' | 'ortaogretim'.
  /// null ise soru TÜM sınav türleri için uygundur (ör. daha önce üretilmiş genel
  /// sorular). QuestionPicker, kullanıcının Profil'de seçtiği sınav türüne göre
  /// bu alanı filtreler — null olanlar her zaman dahil edilir.
  final String? examType;

  const Question({
    required this.soru,
    required this.secenekler,
    required this.dogruIndex,
    required this.aciklama,
    this.distractorAciklama,
    this.kaynak,
    this.topicBaslik,
    this.subjectId,
    this.subjectAd,
    this.examType,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      soru: json['soru'] as String,
      secenekler: List<String>.from(json['secenekler'] as List),
      dogruIndex: json['dogruIndex'] as int,
      aciklama: json['aciklama'] as String? ?? '',
      distractorAciklama: json['distractorAciklama'] as String?,
      kaynak: json['kaynak'] as String?,
      examType: json['examType'] as String?,
    );
  }

  Question copyWith({String? topicBaslik, String? subjectId, String? subjectAd}) {
    return Question(
      soru: soru,
      secenekler: secenekler,
      dogruIndex: dogruIndex,
      aciklama: aciklama,
      distractorAciklama: distractorAciklama,
      kaynak: kaynak,
      topicBaslik: topicBaslik ?? this.topicBaslik,
      subjectId: subjectId ?? this.subjectId,
      subjectAd: subjectAd ?? this.subjectAd,
      examType: examType,
    );
  }

  /// Kullanılmış-soru takibi için kısa, kararlı bir anahtar (JS: soru.slice(0,50)).
  String get key => soru.length > 50 ? soru.substring(0, 50) : soru;
}
