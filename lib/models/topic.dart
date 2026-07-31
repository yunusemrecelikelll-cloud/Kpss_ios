import 'question.dart';

class Anlatim {
  final String? ozet;
  final List<String> icerik;
  final List<String> anahtarNoktalar;

  const Anlatim({this.ozet, this.icerik = const [], this.anahtarNoktalar = const []});

  factory Anlatim.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const Anlatim();
    return Anlatim(
      ozet: json['ozet'] as String?,
      icerik: List<String>.from(json['icerik'] as List? ?? const []),
      anahtarNoktalar: List<String>.from(json['anahtarNoktalar'] as List? ?? const []),
    );
  }
}

class Topic {
  final String id;
  final String baslik;
  final Anlatim anlatim;
  final List<Question> sorular;

  /// İsteğe bağlı GRUP kimliği. Aynı grup kimliğine sahip konular, ders
  /// ekranında ayrı bir alt sayfada (ör. "Paragraf") toplanır — böylece Türkçe
  /// altındaki tüm paragraf konuları tek bir "Paragraf" başlığının içine
  /// taşınabilir (kullanıcı isteği). null ise konu, ders listesinde doğrudan
  /// görünür.
  final String? grup;

  const Topic({
    required this.id,
    required this.baslik,
    required this.anlatim,
    required this.sorular,
    this.grup,
  });

  factory Topic.fromJson(Map<String, dynamic> json) {
    return Topic(
      id: json['id'] as String,
      baslik: json['baslik'] as String,
      grup: json['grup'] as String?,
      anlatim: Anlatim.fromJson(json['anlatim'] as Map<String, dynamic>?),
      sorular: (json['sorular'] as List? ?? const [])
          .map((q) => Question.fromJson(q as Map<String, dynamic>))
          .toList(),
    );
  }
}
