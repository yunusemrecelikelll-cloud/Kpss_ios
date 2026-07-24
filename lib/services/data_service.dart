import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/subject.dart';
import '../models/topic.dart';

/// Ders/konu/soru verisini assets/data/*.json içinden yükler.
/// JS tarafındaki loadAllSubjects()'in karşılığı.
class DataService {
  List<Subject>? _cache;
  Map<String, List<String>>? _mnemonicsCache;

  /// Splash ekranında loadAll() zaten çağrılmış olduğu için burada senkron
  /// olarak erişilebilen önbellek — henüz yüklenmediyse boş liste döner.
  List<Subject> get cachedSubjects => _cache ?? const [];

  /// Konu id'sine göre gerçek, araştırılmış akılda kalıcı kodlama teknikleri
  /// (assets/data/mnemonics.json) — sadece Tarih ve Coğrafya konularında var.
  /// Premium kilidi çağıran ekranda (topic_screen.dart) uygulanır.
  Future<Map<String, List<String>>> loadMnemonics() async {
    if (_mnemonicsCache != null) return _mnemonicsCache!;
    try {
      final raw = await rootBundle.loadString('assets/data/mnemonics.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _mnemonicsCache = json.map((k, v) => MapEntry(k, List<String>.from(v as List)));
    } catch (e) {
      _mnemonicsCache = const {};
    }
    return _mnemonicsCache!;
  }

  Future<List<Subject>> loadAll() async {
    if (_cache != null) return _cache!;
    final subjects = <Subject>[];
    for (final meta in kSubjects) {
      try {
        final raw = await rootBundle.loadString(meta.dosya);
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final konular = (json['konular'] as List? ?? const [])
            .map((k) => Topic.fromJson(k as Map<String, dynamic>))
            .toList();
        subjects.add(Subject(meta: meta, konular: konular));
      } catch (e) {
        // Bir ders yüklenemese bile uygulama diğerleriyle çalışmaya devam etsin.
        subjects.add(Subject(meta: meta, konular: const []));
      }
    }
    _cache = subjects;
    return subjects;
  }

  Subject? subjectById(List<Subject> subjects, String id) {
    for (final s in subjects) {
      if (s.id == id) return s;
    }
    return null;
  }

}
