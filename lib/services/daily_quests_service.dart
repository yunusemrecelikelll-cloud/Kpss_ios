import 'dart:math';
import '../models/attempt.dart';
import 'storage_service.dart';

/// Bir günlük görev tanımı — `id` SABİT kalmalı (StorageService'te bugünkü
/// seçim bu id'lerle `daily_quests` anahtarı altında saklanıyor).
///
/// İlerleme (progress) MEVCUT veriden türetilir (attempts, oyun sayaçları
/// vb.) — ayrı bir "sayaç" TUTULMAZ. `questData` parametresi, seçim anında
/// StorageService'e kaydedilen ekstra alanlara (ör. 'topicsBaseline')
/// erişmek için verilir.
class DailyQuestDef {
  final String id;
  final String icon;
  final String title;
  final int target;
  final bool premiumOnly;
  final int Function(StorageService storage, Map<String, dynamic> questData) progress;

  const DailyQuestDef({
    required this.id,
    required this.icon,
    required this.title,
    required this.target,
    required this.progress,
    this.premiumOnly = false,
  });
}

/// Bir günlük görevin bugünkü durumu — UI'da doğrudan gösterilir.
class DailyQuestProgress {
  final DailyQuestDef def;
  final int current;
  final bool completed; // hedefe ulaşıldı mı
  final bool rewarded; // bu görev için XP ödülü bugün zaten verildi mi
  const DailyQuestProgress({
    required this.def,
    required this.current,
    required this.completed,
    required this.rewarded,
  });
}

String _todayStr() => DateTime.now().toString().split(' ')[0];

List<Attempt> _todaysAttempts(StorageService storage) {
  final today = _todayStr();
  return storage.getAttempts().where((a) => a.tarih.toString().split(' ')[0] == today).toList();
}

/// "Bugün en az bir oyun oynandı mı" — her oyunun kendi günlük oynama
/// sayacına bakılır (bkz. StorageService.getGamePlayState/getCardGameState,
/// bunlar zaten kendi içlerinde "tarih bugün değilse sıfır" mantığını
/// içeriyor, bu yüzden dolaylı ama güvenilir bir sinyal).
bool _anyGamePlayedToday(StorageService storage) {
  const gameIds = ['cardgame2', 'solitaire', 'haritaoyunu'];
  for (final id in gameIds) {
    final plays = (storage.getGamePlayState(id)['plays'] as num?)?.toInt() ?? 0;
    if (plays > 0) return true;
  }
  final v1Plays = (storage.getCardGameState()['plays'] as num?)?.toInt() ?? 0;
  return v1Plays > 0;
}

int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// Görev havuzu — 8 olası görev tanımı, her gün rastgele 3 tanesi seçilir
/// (bkz. DailyQuestsService.ensureTodaysSelection). Premium olmayan
/// kullanıcılar için `premiumOnly` işaretli görevler havuzdan çıkarılır.
final List<DailyQuestDef> kDailyQuestPool = [
  DailyQuestDef(
    id: 'solve-3',
    icon: '📝',
    title: '3 soru çöz',
    target: 3,
    progress: (s, d) => _todaysAttempts(s).fold<int>(0, (t, a) => t + a.toplam),
  ),
  DailyQuestDef(
    id: 'solve-5',
    icon: '📝',
    title: '5 soru çöz',
    target: 5,
    progress: (s, d) => _todaysAttempts(s).fold<int>(0, (t, a) => t + a.toplam),
  ),
  DailyQuestDef(
    id: 'finish-test',
    icon: '✅',
    title: 'Bir testi bitir',
    target: 1,
    progress: (s, d) => _todaysAttempts(s).length,
  ),
  DailyQuestDef(
    id: 'finish-2-tests',
    icon: '🧪',
    title: '2 test bitir',
    target: 2,
    progress: (s, d) => _todaysAttempts(s).length,
  ),
  DailyQuestDef(
    id: 'two-subjects',
    icon: '📚',
    title: '2 farklı dersten soru çöz',
    target: 2,
    progress: (s, d) => _todaysAttempts(s).map((a) => a.subjectId).toSet().length,
  ),
  DailyQuestDef(
    id: 'play-game',
    icon: '🎮',
    title: 'Bir oyun oyna (herhangi biri)',
    target: 1,
    progress: (s, d) => _anyGamePlayedToday(s) ? 1 : 0,
  ),
  DailyQuestDef(
    id: 'wrong-bank-1',
    icon: '🔍',
    title: 'Yanlışlarım bankasından 1 soru çöz',
    target: 1,
    premiumOnly: true,
    progress: (s, d) => _todaysAttempts(s)
        .where((a) => a.topicId == 'wrong-bank')
        .fold<int>(0, (t, a) => t + a.toplam),
  ),
  DailyQuestDef(
    id: 'topic-complete',
    icon: '📖',
    title: 'Bir konu anlatımını tamamla',
    target: 1,
    // Konu tamamlama (getCompletedTopics) tarih damgası TUTMUYOR, bu yüzden
    // "bugün mü tamamlandı" sorusunu doğrudan cevaplayamıyoruz. Bunun yerine
    // görev SEÇİLDİĞİ anda tamamlanmış konu sayısının bir "başlangıç" (baseline)
    // değerini saklıyoruz (questData['topicsBaseline']) ve ilerleme, o günden
    // bu yana artan konu sayısı kadar sayılıyor — makul ve yeterli bir yaklaşım.
    progress: (s, d) {
      final baseline = (d['topicsBaseline'] as num?)?.toInt() ?? 0;
      final now = s.getCompletedTopics().length;
      return _clampInt(now - baseline, 0, 1);
    },
  ),
];

/// Bir görev tamamlandığında verilen tek seferlik XP ödülü.
const int kDailyQuestRewardXp = 20;

extension _FirstOrNullDQ<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Günlük görevlerin seçimini, ilerleme hesaplamasını ve tamamlanan görevler
/// için XP ödüllendirmesini yöneten yardımcı sınıf.
class DailyQuestsService {
  DailyQuestsService._();

  /// Bugünün görev seçimini döner; gün değiştiyse (ya da hiç seçim yoksa)
  /// havuzdan rastgele 3 görev seçip StorageService'e kaydeder — Günün
  /// Patronu'ndaki "bugün mü" tarih karşılaştırma deseniyle aynı mantık.
  static Future<Map<String, dynamic>> ensureTodaysSelection(StorageService storage) async {
    final today = _todayStr();
    final data = storage.getDailyQuestsData();
    final existingIds = List<String>.from(data['questIds'] as List? ?? const []);
    if (data['date'] == today && existingIds.isNotEmpty) {
      return data;
    }

    final premium = storage.isPremiumUser();
    final pool = kDailyQuestPool.where((q) => premium || !q.premiumOnly).toList();
    pool.shuffle(Random(today.hashCode));
    final selectedIds = pool.take(3).map((q) => q.id).toList();

    final newData = {
      'date': today,
      'questIds': selectedIds,
      'completedIds': <String>[],
      // "Bir konu anlatımını tamamla" görevi için başlangıç noktası.
      'topicsBaseline': storage.getCompletedTopics().length,
    };
    await storage.saveDailyQuestsData(newData);
    return newData;
  }

  /// Verilen seçim verisine göre bugünün 3 görevinin GÜNCEL ilerlemesini
  /// (salt-okunur, yan etkisiz) hesaplar.
  static List<DailyQuestProgress> computeProgress(StorageService storage, Map<String, dynamic> data) {
    final ids = List<String>.from(data['questIds'] as List? ?? const []);
    final completedIds = List<String>.from(data['completedIds'] as List? ?? const []);
    final result = <DailyQuestProgress>[];
    for (final id in ids) {
      final def = kDailyQuestPool.where((q) => q.id == id).firstOrNull;
      if (def == null) continue;
      final raw = def.progress(storage, data);
      final current = _clampInt(raw, 0, def.target);
      final completed = current >= def.target;
      result.add(DailyQuestProgress(def: def, current: current, completed: completed, rewarded: completedIds.contains(id)));
    }
    return result;
  }

  /// Yeni tamamlanan (hedefe ulaşmış ama henüz ödüllendirilmemiş) görevleri
  /// bulur, her biri için tek seferlik XP verir ve `completedIds` listesine
  /// işaretler — aynı gün için tekrar ödül VERİLMEZ. Idempotent'tir: hiçbir
  /// yeni tamamlanan görev yoksa depoya yazma yapmaz.
  static Future<List<DailyQuestDef>> rewardNewlyCompleted(StorageService storage) async {
    final data = await ensureTodaysSelection(storage);
    final progresses = computeProgress(storage, data);
    final completedIds = List<String>.from(data['completedIds'] as List? ?? const []);
    final newlyCompleted = <DailyQuestDef>[];
    for (final p in progresses) {
      if (p.completed && !p.rewarded) {
        completedIds.add(p.def.id);
        newlyCompleted.add(p.def);
      }
    }
    if (newlyCompleted.isNotEmpty) {
      final updated = Map<String, dynamic>.from(data)..['completedIds'] = completedIds;
      await storage.saveDailyQuestsData(updated);
      await storage.addXp(kDailyQuestRewardXp * newlyCompleted.length);
    }
    return newlyCompleted;
  }
}
