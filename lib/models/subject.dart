import 'topic.dart';

class SubjectMeta {
  final String id;
  final String ad;
  final String icon; // emoji
  final String dosya; // assets/data/<dosya>.json

  const SubjectMeta({required this.id, required this.ad, required this.icon, required this.dosya});
}

/// JS tarafındaki SUBJECTS sabitinin birebir karşılığı.
const List<SubjectMeta> kSubjects = [
  SubjectMeta(id: 'guncel', ad: 'Güncel Bilgiler', icon: '📰', dosya: 'assets/data/guncel.json'),
  SubjectMeta(id: 'vatandaslik', ad: 'Vatandaşlık', icon: '⚖️', dosya: 'assets/data/vatandaslik.json'),
  SubjectMeta(id: 'cografya', ad: 'Coğrafya', icon: '🗺️', dosya: 'assets/data/cografya.json'),
  SubjectMeta(id: 'tarih', ad: 'Tarih', icon: '🏛️', dosya: 'assets/data/tarih.json'),
  SubjectMeta(id: 'matematik', ad: 'Matematik-Geometri', icon: '🔢', dosya: 'assets/data/matematik.json'),
  SubjectMeta(id: 'turkce', ad: 'Türkçe', icon: '📖', dosya: 'assets/data/turkce.json'),
];

/// Tam deneme sınavı dağılımı (toplam 120 soru) — gerçek KPSS Genel Yetenek/
/// Genel Kültür soru dağılımına göre (Lisans/Önlisans/Ortaöğretim'de bu
/// dağılım pratikte birebir aynıdır, sınav türüne göre değişmez).
const Map<String, int> kFullTestDist = {
  'turkce': 30,
  'matematik': 30,
  'tarih': 27,
  'cografya': 18,
  'vatandaslik': 9,
  'guncel': 6,
};

const int kSubjectExamQPerTopic = 3;

class Subject {
  final SubjectMeta meta;
  final List<Topic> konular;

  const Subject({required this.meta, required this.konular});

  String get id => meta.id;
  String get ad => meta.ad;
  String get icon => meta.icon;
}
