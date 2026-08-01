import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase_bootstrap.dart';
import 'storage_service.dart';

/// Lig kademesi — kullanıcının bu haftaki lig puanına göre diğer kullanıcılara
/// kıyasla bulunduğu kademe.
enum LeagueTier { bronz, gumus, altin, platin, elmas, efsane }

extension LeagueTierLabel on LeagueTier {
  String get label => switch (this) {
        LeagueTier.bronz => 'Bronz',
        LeagueTier.gumus => 'Gümüş',
        LeagueTier.altin => 'Altın',
        LeagueTier.platin => 'Platin',
        LeagueTier.elmas => 'Elmas',
        LeagueTier.efsane => 'Efsane',
      };

  String get icon => switch (this) {
        LeagueTier.bronz => '🥉',
        LeagueTier.gumus => '🥈',
        LeagueTier.altin => '🥇',
        LeagueTier.platin => '💠',
        LeagueTier.elmas => '💎',
        LeagueTier.efsane => '👑',
      };
}

/// Gerçek zamanlı Firestore skorlarına göre hesaplanan lig sonucu.
class LeagueResult {
  final LeagueTier tier;
  /// 0-100 arası: katılımcıların yüzde kaçından daha iyi (ya da eşit)
  /// olduğu.
  final double percentile;
  final int totalParticipants;
  final int myRate;
  /// Bu haftaki (Pazartesi'den bugüne) lig puanı — bkz. StorageService.getWeeklyPoints.
  final int myWeeklyPoints;

  /// Her kademede bu hafta kaç kişi yer aldığı (kullanıcı isteği: "lig başına
  /// kişi sayısı görünsün"). Her katılımcının puanı kendi yüzdelik dilimine,
  /// o da bir kademeye eşlenip sayılır. Boş harita olabilir (offline).
  final Map<LeagueTier, int> tierCounts;

  /// Bu haftanın BİRİNCİSİ — en yüksek lig puanına sahip kullanıcının adı ve
  /// puanı (kullanıcı isteği: "ligde 1. olan kişinin ismi lig bölümünün üstünde
  /// 'haftanın birincisi' gibi yazsın"). Katılımcı yoksa/offline ise null.
  final String? leaderName;
  final int leaderPoints;

  /// Birinci BEN miyim? (vitrinde "sensin!" vurgusu için.)
  final bool leaderIsMe;

  const LeagueResult({
    required this.tier,
    required this.percentile,
    required this.totalParticipants,
    required this.myRate,
    required this.myWeeklyPoints,
    this.tierCounts = const {},
    this.leaderName,
    this.leaderPoints = 0,
    this.leaderIsMe = false,
  });
}

/// Başka bir kullanıcının PROFİL EKRANINDA (sohbet/DM'den erişilen) gösterilen
/// herkese-açık (publish edilmiş) istatistik/rozet özeti — 'league_scores/{uid}'
/// dokümanından okunur (bkz. [LeagueService.publishMyScore] / [LeagueService.fetchUserProfile]).
class PublicUserProfile {
  final String displayName;
  final int rate;
  final int solved;
  final int weeklyPoints;
  final int streakCount;
  final int badgeCount;
  final List<String> unlockedBadgeIds;
  /// Kullanıcı kendi profilinde "İstatistiklerimi Gizle" ayarını açtıysa true —
  /// bu durumda istatistik/rozet alanları GÖSTERİLMEMELİDİR (bkz.
  /// PublicProfileScreen: sadece "gizli tutuyor" yer tutucusu gösterilir).
  final bool hideStats;
  final DateTime? updatedAt;

  const PublicUserProfile({
    required this.displayName,
    required this.rate,
    required this.solved,
    required this.weeklyPoints,
    required this.streakCount,
    required this.badgeCount,
    required this.unlockedBadgeIds,
    required this.hideStats,
    required this.updatedAt,
  });
}

/// Firestore'daki gerçek kullanıcı skorlarına göre Lig yüzdelik dilimini
/// hesaplayan servis.
///
/// GİZLİ İSTATİSTİK — KATILIM: Kullanıcı "İstatistiklerimi Gizle"yi açsa bile
/// lige DAHİL olur (skoru [publishMyScore] ile yayınlanır ve karşılaştırmaya
/// katılır). `hideStats` yalnızca BAŞKALARININ profil ekranında istatistik
/// görünürlüğünü etkiler; lig sıralamasındaki VARLIĞINI değil (kullanıcı
/// isteği: "gizli tutsa da lige katılsın").
///
/// Firebase yapılandırılmamışsa, kullanıcı giriş yapmamışsa ya da ağ
/// hatası/offline durum varsa [computeMyLeagueTier] `null` döner — hiçbir
/// zaman istisna fırlatıp uygulamayı çökertmez.
class LeagueService {
  static const String scoresCollection = 'league_scores';

  bool get isConfigured => isFirebaseConfigured;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String? get _currentUid => isConfigured ? FirebaseAuth.instance.currentUser?.uid : null;

  /// StorageService._mondayOf ile birebir aynı hesap — o hafta Pazartesi'nin
  /// tarihini "YYYY-MM-DD" olarak döner, haftalık karşılaştırmanın anahtarı budur.
  String _mondayOf(DateTime d) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    final day = DateTime(monday.year, monday.month, monday.day);
    return day.toIso8601String().split('T')[0];
  }

  /// Kendi güncel skorunu VE bu haftaki lig puanını Firestore'daki toplu
  /// havuza yayınlar, böylece diğer kullanıcılar da bu kullanıcıyla
  /// karşılaştırılabilir. computeMyLeagueTier() bunu otomatik çağırır.
  ///
  /// AYRICA: sohbet/DM üzerinden başka kullanıcıların görüntülediği
  /// "kullanıcı profili" ekranının (bkz. PublicProfileScreen,
  /// [fetchUserProfile]) veri kaynağı da AYNI belgedir — bu yüzden rozet
  /// sayısı/kimlikleri, günlük seri ve "istatistiklerimi gizle" tercihi de
  /// buraya eklendi (yeni bir koleksiyon/kural gerektirmeden, mevcut
  /// 'league_scores' okuma kuralını — bkz. FIREBASE_SETUP.md, herkes
  /// okuyabilir/sadece sahibi yazabilir — yeniden kullanarak).
  Future<void> publishMyScore(StorageService storage) async {
    final uid = _currentUid;
    if (!isConfigured || uid == null) return;
    try {
      final overall = storage.computeOverall();
      final streak = storage.getStreak();
      final unlockedBadges = storage.getUnlockedBadges();
      await _db.collection(scoresCollection).doc(uid).set({
        'displayName': storage.getUserName(),
        'rate': overall.rate,
        'solved': overall.solved,
        'correct': overall.correct,
        'tests': overall.tests,
        'weeklyPoints': storage.getWeeklyPoints(),
        'weekStart': _mondayOf(DateTime.now()),
        'streakCount': (streak['count'] as num?)?.toInt() ?? 0,
        'badgeCount': unlockedBadges.length,
        'unlockedBadgeIds': unlockedBadges,
        'hideStats': storage.getHideStatsEnabled(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('LeagueService.publishMyScore başarısız: $e');
    }
  }

  /// Başka bir kullanıcının (verilen [uid]) 'league_scores' dokümanından
  /// herkese-açık profil özetini okur — sohbet/DM'de bir kullanıcının
  /// avatarına dokunulduğunda açılan PublicProfileScreen için kullanılır.
  /// Doküman hiç yayınlanmamışsa (o kullanıcı henüz kendi profilini/ligini
  /// hiç açmadıysa), Firebase yapılandırılmamışsa ya da bir ağ hatası
  /// oluşursa `null` döner — çağıran taraf uygun bir boş durum gösterir.
  Future<PublicUserProfile?> fetchUserProfile(String uid) async {
    if (!isConfigured) return null;
    try {
      final doc = await _db.collection(scoresCollection).doc(uid).get();
      final data = doc.data();
      if (data == null) return null;
      final ts = data['updatedAt'];
      return PublicUserProfile(
        displayName: data['displayName'] as String? ?? 'Kullanıcı',
        rate: (data['rate'] as num?)?.toInt() ?? 0,
        solved: (data['solved'] as num?)?.toInt() ?? 0,
        weeklyPoints: (data['weeklyPoints'] as num?)?.toInt() ?? 0,
        streakCount: (data['streakCount'] as num?)?.toInt() ?? 0,
        badgeCount: (data['badgeCount'] as num?)?.toInt() ?? 0,
        unlockedBadgeIds: List<String>.from(data['unlockedBadgeIds'] as List? ?? const []),
        hideStats: data['hideStats'] == true,
        updatedAt: ts is Timestamp ? ts.toDate() : null,
      );
    } catch (e) {
      debugPrint('LeagueService.fetchUserProfile başarısız: $e');
      return null;
    }
  }

  /// Kendi skorunu yayınlar ve Firestore'daki BU HAFTA puan yayınlamış tüm
  /// katılımcılarla karşılaştırıp bir [LeagueResult] (yüzdelik dilim +
  /// Bronz/Gümüş/Altın/Platin/Elmas/Efsane kademesi) döner. Geçen haftalardan
  /// kalma eski kayıtlar (farklı `weekStart`) karşılaştırmaya dahil edilmez.
  ///
  /// Firebase yapılandırılmamışsa, kullanıcı giriş yapmamışsa ya da bir ağ
  /// hatası oluşursa (offline) `null` döner.
  Future<LeagueResult?> computeMyLeagueTier(StorageService storage) async {
    final uid = _currentUid;
    if (!isConfigured || uid == null) return null;

    try {
      await publishMyScore(storage);
      final myOverall = storage.computeOverall();
      final myPoints = storage.getWeeklyPoints();
      final thisWeek = _mondayOf(DateTime.now());

      final snap = await _db
          .collection(scoresCollection)
          .where('weekStart', isEqualTo: thisWeek)
          .get();
      final points = snap.docs
          .map((d) => (d.data()['weeklyPoints'] as num?)?.toInt() ?? 0)
          .toList();

      // Haftanın birincisi: en yüksek lig puanlı doküman (0 puanlılar da olsa
      // en tepedeki alınır; hepsi 0 ise yine ilk sıradaki gösterilir).
      String? leaderName;
      int leaderPoints = 0;
      bool leaderIsMe = false;
      for (final d in snap.docs) {
        final p = (d.data()['weeklyPoints'] as num?)?.toInt() ?? 0;
        if (leaderName == null || p > leaderPoints) {
          leaderPoints = p;
          final ad = (d.data()['displayName'] as String?)?.trim();
          leaderName = (ad == null || ad.isEmpty) ? 'Bir aday' : ad;
          leaderIsMe = d.id == uid;
        }
      }

      if (points.isEmpty) {
        return LeagueResult(
          tier: _tierFor(0),
          percentile: 0,
          totalParticipants: 1,
          myRate: myOverall.rate,
          myWeeklyPoints: myPoints,
          tierCounts: {_tierFor(0): 1},
          leaderName: leaderName,
          leaderPoints: leaderPoints,
          leaderIsMe: leaderIsMe,
        );
      }

      final below = points.where((p) => p < myPoints).length;
      final percentile = (below / points.length) * 100;

      // Kademe dağılımı: her katılımcının puanını kendi yüzdelik dilimine, o
      // dilimi de bir kademeye eşleyip say. Böylece "her ligde kaç kişi var"
      // gösterilebilir (kullanıcı isteği).
      final tierCounts = {for (final t in LeagueTier.values) t: 0};
      for (final p in points) {
        final altta = points.where((x) => x < p).length;
        final pct = (altta / points.length) * 100;
        final t = _tierFor(pct);
        tierCounts[t] = tierCounts[t]! + 1;
      }

      return LeagueResult(
        tier: _tierFor(percentile),
        percentile: percentile,
        totalParticipants: points.length,
        myRate: myOverall.rate,
        myWeeklyPoints: myPoints,
        tierCounts: tierCounts,
        leaderName: leaderName,
        leaderPoints: leaderPoints,
        leaderIsMe: leaderIsMe,
      );
    } catch (e) {
      debugPrint('LeagueService.computeMyLeagueTier başarısız (offline olabilir): $e');
      return null;
    }
  }

  LeagueTier _tierFor(double percentile) {
    if (percentile >= 95) return LeagueTier.efsane;
    if (percentile >= 85) return LeagueTier.elmas;
    if (percentile >= 70) return LeagueTier.platin;
    if (percentile >= 50) return LeagueTier.altin;
    if (percentile >= 25) return LeagueTier.gumus;
    return LeagueTier.bronz;
  }
}
