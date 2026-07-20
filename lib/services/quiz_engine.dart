import 'package:flutter/foundation.dart';
import '../models/attempt.dart';
import '../models/question.dart';
import 'storage_service.dart';

/// quiz.js'nin Dart karşılığı: aktif test oturumunu yönetir.
class QuizEngine extends ChangeNotifier {
  final StorageService storage;
  QuizEngine(this.storage);

  String? subjectId;
  String? subjectAd;
  String? topicId;
  String? topicBaslik;
  List<Question> questions = [];
  int currentIndex = 0;
  List<int?> answers = [];
  int durationSec = 0;
  bool isFullTest = false;
  /// Bu oturum Yanlışlarım ("Yanlışlar Testi") pratik oturumu mu? — evetse
  /// finish() burada doğru çözülen soruları yanlış bankasından kalıcı olarak
  /// siler VE quiz_screen.dart._finish() genel istatistik sayaçlarını
  /// (addAttempt/markTopicCompleted/addUsedQuestions) ATLAR (bkz. Fix 1).
  bool isWrongBankMode = false;
  // "Beni Sına" teşhis (yerleştirme) sınavı mı? bkz. placement_exam_screen.dart
  // / placement_result_screen.dart — quiz_screen.dart _finish() bu bayrağa
  // bakıp normal ResultScreen yerine ders bazlı zayıf/güçlü analiz ekranına
  // yönlendirir.
  bool isPlacementExam = false;
  DateTime? startedAt;

  bool get isActive => questions.isNotEmpty;

  void start({
    required String subjectId,
    required String subjectAd,
    required String topicId,
    required String topicBaslik,
    required List<Question> questions,
    required int durationSec,
    bool isFullTest = false,
    bool isWrongBankMode = false,
    bool isPlacementExam = false,
  }) {
    this.subjectId = subjectId;
    this.subjectAd = subjectAd;
    this.topicId = topicId;
    this.topicBaslik = topicBaslik;
    this.questions = questions;
    currentIndex = 0;
    answers = List<int?>.filled(questions.length, null);
    this.durationSec = durationSec;
    this.isFullTest = isFullTest;
    this.isWrongBankMode = isWrongBankMode;
    this.isPlacementExam = isPlacementExam;
    startedAt = DateTime.now();
    _saveDraft();
    notifyListeners();
  }

  void restoreFromDraft(Map<String, dynamic> draft) {
    subjectId = draft['subjectId'] as String?;
    subjectAd = draft['subjectAd'] as String?;
    topicId = draft['topicId'] as String?;
    topicBaslik = draft['topicBaslik'] as String?;
    questions = (draft['questions'] as List)
        .map((q) => Question.fromJson(Map<String, dynamic>.from(q as Map)))
        .toList();
    currentIndex = draft['currentIndex'] as int? ?? 0;
    answers = List<int?>.from(draft['answers'] as List? ?? []);
    durationSec = draft['durationSec'] as int? ?? 0;
    isFullTest = draft['isFullTest'] as bool? ?? false;
    isWrongBankMode = draft['isWrongBankMode'] as bool? ?? false;
    isPlacementExam = draft['isPlacementExam'] as bool? ?? false;
    startedAt = draft['startedAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(draft['startedAt'] as int)
        : DateTime.now();
    notifyListeners();
  }

  void _saveDraft() {
    if (!isActive) return;
    storage.saveDraft(topicId ?? '', {
      'subjectId': subjectId,
      'subjectAd': subjectAd,
      'topicId': topicId,
      'topicBaslik': topicBaslik,
      'questions': questions
          .map((q) => {
                'soru': q.soru,
                'secenekler': q.secenekler,
                'dogruIndex': q.dogruIndex,
                'aciklama': q.aciklama,
                'distractorAciklama': q.distractorAciklama,
                'kaynak': q.kaynak,
              })
          .toList(),
      'currentIndex': currentIndex,
      'answers': answers,
      'durationSec': durationSec,
      'isFullTest': isFullTest,
      'isWrongBankMode': isWrongBankMode,
      'isPlacementExam': isPlacementExam,
      'startedAt': startedAt?.millisecondsSinceEpoch,
    });
  }

  void answer(int? idx) {
    if (!isActive) return;
    answers[currentIndex] = idx;
    _saveDraft();
    notifyListeners();
  }

  void goTo(int i) {
    if (i < 0 || i >= questions.length) return;
    currentIndex = i;
    notifyListeners();
  }

  void next() {
    if (currentIndex < questions.length - 1) {
      currentIndex++;
      notifyListeners();
    }
  }

  void prev() {
    if (currentIndex > 0) {
      currentIndex--;
      notifyListeners();
    }
  }

  Future<Attempt> finish(int elapsedSec) async {
    int dogru = 0, yanlis = 0, bos = 0;
    final wrongQs = <Question>[];
    final review = <ReviewItem>[];
    // Fix 1: Yanlışlarım oturumunda doğru çözülen soruların anahtarları —
    // testten sonra bankadan kalıcı olarak silinecekler (bir daha çıkmasınlar).
    final resolvedWrongBankKeys = <String>[];

    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      final given = answers[i];
      String status;
      if (given == null) {
        bos++;
        status = 'bos';
      } else if (given == q.dogruIndex) {
        dogru++;
        status = 'dogru';
        if (isWrongBankMode) {
          resolvedWrongBankKeys.add(storage.wrongBankKeyFor(q.soru));
        }
      } else {
        yanlis++;
        status = 'yanlis';
        wrongQs.add(q);
      }
      review.add(ReviewItem(
        soru: q.soru,
        secenekler: q.secenekler,
        dogruIndex: q.dogruIndex,
        verilenIndex: given,
        aciklama: q.aciklama,
        distractorAciklama: q.distractorAciklama,
        kaynak: q.kaynak,
        status: status,
      ));
    }

    final skor = questions.isEmpty ? 0 : ((dogru / questions.length) * 100).round();
    final result = Attempt(
      subjectId: subjectId ?? '',
      subjectAd: subjectAd ?? '',
      topicId: topicId ?? '',
      topicBaslik: topicBaslik ?? '',
      toplam: questions.length,
      dogru: dogru,
      yanlis: yanlis,
      bos: bos,
      skor: skor,
      sureSn: elapsedSec,
      tarih: DateTime.now(),
      isFullTest: isFullTest,
      review: review,
    );

    if (wrongQs.isNotEmpty) {
      await storage.addWrongQuestions(wrongQs, subjectId ?? '', subjectAd ?? '');
    }
    // Fix 1: Yanlışlarım'dan doğru çözülen sorular bankadan kalıcı olarak
    // çıkar — bir daha karşımıza çıkmasın (bkz. wrong_bank_screen.dart).
    for (final key in resolvedWrongBankKeys) {
      await storage.removeFromWrongBank(key);
    }
    // Haftalık lig puanı: her doğru cevap 10 puan (bkz. LeagueService).
    await storage.addWeeklyPoints(dogru * 10);
    // Toplam XP (kalıcı, seviye sistemi için) + Sezon XP (aylık, ay değişince
    // sıfırlanır) — ikisi de aynı katsayıyla (doğru başına 5 XP) beslenir ama
    // haftalık lig puanından TAMAMEN AYRI iki alandır.
    await storage.addXp(dogru * 5);
    await storage.addSeasonXp(dogru * 5);

    await storage.clearDraft(topicId ?? '');
    questions = [];
    answers = [];
    notifyListeners();
    return result;
  }

  void abandon() {
    storage.clearDraft(topicId ?? '');
    questions = [];
    answers = [];
    notifyListeners();
  }
}
