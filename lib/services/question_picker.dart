import 'dart:math';
import '../models/question.dart';
import 'storage_service.dart';

/// pickQuestions (app.js) karşılığı: tekrarsız rastgele soru seçimi.
/// Kullanılmamış sorular önce, tükenirse kullanılmışlar karıştırılıp eklenir.
class QuestionPicker {
  final StorageService storage;
  final _rng = Random();

  QuestionPicker(this.storage);

  static const int freeTopicPoolSize = 20; // ücretsiz: 2x10 soruluk farklı test
  static const int premiumTopicPoolSize = 100;

  List<Question> pickForTopic(List<Question> all, int count, String? topicId, {required bool premium}) {
    // Sınav türüne özel etiketlenmiş sorular (examType != null) sadece
    // kullanıcının Profil'de seçtiği sınav türüyle eşleşirse gösterilir;
    // etiketsiz sorular (examType == null) her sınav türü için uygundur ve
    // her zaman dahil edilir. Kullanıcı henüz bir sınav türü seçmediyse
    // (examType boşsa) hiçbir filtre uygulanmaz, tüm sorular gösterilir.
    final examType = storage.getExamType();
    final filtered = examType.isEmpty
        ? all
        : all.where((q) => q.examType == null || q.examType == examType).toList();

    // Ücretsiz kullanıcılar konunun sadece ilk N sorusunu görür (havuz sınırlaması),
    // premium kullanıcılar tüm havuza (≈100) erişir.
    final pool0 = premium ? filtered : filtered.take(freeTopicPoolSize).toList();
    return pick(pool0, count, topicId);
  }

  List<Question> pick(List<Question> allQuestions, int count, String? topicId) {
    final usedKeys = topicId != null ? storage.getUsedQuestions(topicId) : <String>[];
    final unused = allQuestions.where((q) => !usedKeys.contains(q.key)).toList();

    List<Question> pool;
    if (unused.length >= count) {
      pool = unused;
    } else if (unused.isNotEmpty) {
      final used = allQuestions.where((q) => usedKeys.contains(q.key)).toList()..shuffle(_rng);
      pool = [...unused, ...used];
    } else {
      pool = List.of(allQuestions);
    }

    pool = List.of(pool)..shuffle(_rng);
    return pool.take(count).toList();
  }
}
