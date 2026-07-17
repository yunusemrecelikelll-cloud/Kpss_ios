import 'package:flutter/material.dart';
import 'subject.dart';
import '../services/storage_service.dart';

/// Rozet tanımı — JS karşılığı: src/js/badges.js (Badges.DEFS)
class BadgeDef {
  final String id;
  final String icon;
  final String name;
  final String desc;
  final Color color;
  final bool Function(StorageService storage, List<Subject> subjects) check;

  const BadgeDef({
    required this.id,
    required this.icon,
    required this.name,
    required this.desc,
    required this.color,
    required this.check,
  });
}

bool _allTopicsDone(StorageService storage, List<Subject> subjects, String subjectId) {
  final subject = subjects.where((s) => s.id == subjectId).firstOrNull;
  if (subject == null || subject.konular.isEmpty) return false;
  final completed = storage.getCompletedTopics();
  return subject.konular.every((t) => completed[t.id] == true);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Tüm rozet tanımlarının listesi — her rozetin `check` kapatması,
/// StorageService (ve konu tamamlama kontrolü gereken "Ders Ustalıkları"
/// rozetleri için ayrıca konu listesi) üzerinden canlı olarak değerlendirilir.
/// Kazanılmış olup olmadığı StorageService.isBadgeUnlocked ile ayrıca takip
/// edilir; check sadece "şu an koşul sağlanıyor mu" sorusuna cevap verir —
/// bkz. checkAndUnlockBadges() (bu dosyanın altında).
///
/// Renkler kategoriye göre gruplanmış (Başlangıç=yeşil, Başarı=mor/altın,
/// Seri&Çalışma=turuncu/kırmızı, Soru Sayısı=mavi/pembe, Çeşitlilik=camgöbeği,
/// Ders Ustalıkları=derse özel renkler).
final List<BadgeDef> kBadgeDefs = [
  // — Başlangıç (yeşil) —
  BadgeDef(
    id: 'ilk-adim', icon: '🌱', name: 'İlk Adım', desc: 'İlk testini çözdün!', color: const Color(0xFF22C55E),
    check: (s, subjects) => s.getAttempts().isNotEmpty,
  ),
  BadgeDef(
    id: 'hizli-basla', icon: '🚀', name: 'Hızlı Başla', desc: '3 farklı konu testi çözdün', color: const Color(0xFF16A34A),
    check: (s, subjects) => s.getAttempts().map((a) => a.topicId).toSet().length >= 3,
  ),
  BadgeDef(
    id: 'pratisyen', icon: '📝', name: 'Pratisyen', desc: '10 farklı konu testi çözdün', color: const Color(0xFF15803D),
    check: (s, subjects) => s.getAttempts().map((a) => a.topicId).toSet().length >= 10,
  ),
  BadgeDef(
    id: 'uzman', icon: '🧠', name: 'Uzman', desc: '20 test çözdün', color: const Color(0xFF166534),
    check: (s, subjects) => s.getAttempts().length >= 20,
  ),

  // — Başarı (mor & altın) —
  BadgeDef(
    id: 'yukselen', icon: '⭐', name: 'Yükselen Yıldız', desc: 'Bir konuda %70+ aldın', color: const Color(0xFFFBBF24),
    check: (s, subjects) => s.getAttempts().any((a) => a.skor >= 70),
  ),
  BadgeDef(
    id: 'ustun', icon: '👑', name: 'Üstün Performans', desc: 'Bir testde %90+ aldın', color: const Color(0xFFEAB308),
    check: (s, subjects) => s.getAttempts().any((a) => a.skor >= 90),
  ),
  BadgeDef(
    id: 'mukemmel', icon: '✨', name: 'Mükemmel', desc: 'Bir testde hiç yanlış yapmadın', color: const Color(0xFFA855F7),
    check: (s, subjects) => s.getAttempts().any((a) => a.toplam > 0 && a.yanlis == 0 && a.dogru == a.toplam),
  ),
  BadgeDef(
    id: 'mukemmeliyetci', icon: '💫', name: 'Mükemmeliyetçi', desc: '3 farklı konuda %90+ aldın', color: const Color(0xFF9333EA),
    check: (s, subjects) =>
        s.getAttempts().where((a) => a.skor >= 90).map((a) => a.topicId).toSet().length >= 3,
  ),
  BadgeDef(
    id: 'genel-uzman', icon: '🎓', name: 'Genel Uzman', desc: 'Genel başarı oranın %70 üzeri', color: const Color(0xFF7E22CE),
    check: (s, subjects) => s.getAttempts().isNotEmpty && s.computeOverall().rate >= 70,
  ),
  BadgeDef(
    id: 'surekli-gelisim', icon: '📈', name: 'Sürekli Gelişim', desc: 'Aynı konuda skoru %10+ artırdın', color: const Color(0xFF6D28D9),
    check: (s, subjects) {
      final byTopic = <String, List<int>>{};
      for (final a in (s.getAttempts()..sort((a, b) => a.tarih.compareTo(b.tarih)))) {
        (byTopic[a.topicId] ??= []).add(a.skor);
      }
      return byTopic.values.any((scores) {
        if (scores.length < 2) return false;
        var minSoFar = scores.first;
        for (final sc in scores.skip(1)) {
          if (sc - minSoFar >= 10) return true;
          if (sc < minSoFar) minSoFar = sc;
        }
        return false;
      });
    },
  ),

  // — Seri & Çalışma (turuncu/kırmızı/mavi tonları) —
  BadgeDef(
    id: 'devam-et', icon: '🔥', name: 'Devam Et!', desc: '3 günlük seri yaptın', color: const Color(0xFFF97316),
    check: (s, subjects) => ((s.getStreak()['count'] as num?) ?? 0) >= 3,
  ),
  BadgeDef(
    id: 'seri-5', icon: '🌋', name: 'Ateş Halkası', desc: '5 günlük seri yaptın', color: const Color(0xFFEA580C),
    check: (s, subjects) => ((s.getStreak()['count'] as num?) ?? 0) >= 5,
  ),
  BadgeDef(
    id: 'azimli', icon: '💎', name: 'Azimli', desc: '7 günlük seri yaptın', color: const Color(0xFF06B6D4),
    check: (s, subjects) => ((s.getStreak()['count'] as num?) ?? 0) >= 7,
  ),
  BadgeDef(
    id: 'sabahci', icon: '🌅', name: 'Sabahçı', desc: 'Sabah 6-10 arası test çözdün', color: const Color(0xFFFB923C),
    check: (s, subjects) => s.getAttempts().any((a) => a.tarih.hour >= 6 && a.tarih.hour < 10),
  ),
  BadgeDef(
    id: 'gece-kusu', icon: '🌙', name: 'Gece Kuşu', desc: 'Gece 22-02 arası test çözdün', color: const Color(0xFF4338CA),
    check: (s, subjects) => s.getAttempts().any((a) => a.tarih.hour >= 22 || a.tarih.hour < 2),
  ),

  // — Soru Sayısı (mavi/pembe/kırmızı) —
  BadgeDef(
    id: 'toplam-50', icon: '🌸', name: '50 Soru', desc: 'Toplamda 50 soru çözdün', color: const Color(0xFFEC4899),
    check: (s, subjects) => s.getAttempts().fold<int>(0, (t, a) => t + a.toplam) >= 50,
  ),
  BadgeDef(
    id: 'toplam-100', icon: '💯', name: '100 Soru', desc: 'Toplamda 100 soru çözdün', color: const Color(0xFF3B82F6),
    check: (s, subjects) => s.getAttempts().fold<int>(0, (t, a) => t + a.toplam) >= 100,
  ),
  BadgeDef(
    id: 'toplam-500', icon: '🌟', name: '500 Soru', desc: 'Toplamda 500 soru çözdün', color: const Color(0xFFF59E0B),
    check: (s, subjects) => s.getAttempts().fold<int>(0, (t, a) => t + a.toplam) >= 500,
  ),
  BadgeDef(
    id: 'toplam-1000', icon: '🏆', name: 'Efsane', desc: 'Toplamda 1000 soru çözdün', color: const Color(0xFFCA8A04),
    check: (s, subjects) => s.getAttempts().fold<int>(0, (t, a) => t + a.toplam) >= 1000,
  ),
  BadgeDef(
    id: 'dogru-100', icon: '🎯', name: '100 Doğru', desc: 'Toplamda 100 doğru cevap verdin', color: const Color(0xFFDC2626),
    check: (s, subjects) => s.getAttempts().fold<int>(0, (t, a) => t + a.dogru) >= 100,
  ),

  // — Çeşitlilik (camgöbeği/sarı/turuncu) —
  BadgeDef(
    id: 'koleksiyoncu', icon: '🗂️', name: 'Koleksiyoncu', desc: '5 farklı derste test çözdün', color: const Color(0xFF14B8A6),
    check: (s, subjects) => s.getAttempts().map((a) => a.subjectId).toSet().length >= 5,
  ),
  BadgeDef(
    id: 'hizli', icon: '⚡', name: 'Hızlı Düşünen', desc: "Bir testi 2 dk'dan kısa sürede tamamladın", color: const Color(0xFFFACC15),
    check: (s, subjects) => s.getAttempts().any((a) => a.sureSn > 0 && a.sureSn < 120),
  ),
  BadgeDef(
    id: 'mucadeleci', icon: '🏅', name: 'Mücadeleci', desc: 'Yanlış sorular bankasından 20+ soru çözdün', color: const Color(0xFFDB2777),
    check: (s, subjects) => s.getAttempts().where((a) => a.topicId == 'wrong-bank').fold<int>(0, (t, a) => t + a.toplam) >= 20,
  ),
  BadgeDef(
    id: 'deneme-sav', icon: '🎯', name: 'Deneme Savaşçısı', desc: 'İlk 120 soruluk deneme testini tamamladın', color: const Color(0xFFB91C1C),
    check: (s, subjects) => s.getAttempts().any((a) => a.isFullTest && a.toplam >= 120),
  ),

  // — Ders Ustalıkları (derse özel renkler) —
  BadgeDef(
    id: 'turkce-uzm', icon: '📖', name: 'Türkçe Ustası', desc: "Türkçe'nin tüm konularını tamamladın", color: const Color(0xFF6366F1),
    check: (s, subjects) => _allTopicsDone(s, subjects, 'turkce'),
  ),
  BadgeDef(
    id: 'mat-uzm', icon: '🔢', name: 'Matematik Ustası', desc: 'Matematiğin tüm konularını tamamladın', color: const Color(0xFF0EA5E9),
    check: (s, subjects) => _allTopicsDone(s, subjects, 'matematik'),
  ),
  BadgeDef(
    id: 'tarih-uzm', icon: '🏛️', name: 'Tarihçi', desc: 'Tarihin tüm konularını tamamladın', color: const Color(0xFF92400E),
    check: (s, subjects) => _allTopicsDone(s, subjects, 'tarih'),
  ),
  BadgeDef(
    id: 'cog-uzm', icon: '🗺️', name: 'Gezgin', desc: 'Coğrafyanın tüm konularını tamamladın', color: const Color(0xFF059669),
    check: (s, subjects) => _allTopicsDone(s, subjects, 'cografya'),
  ),
  BadgeDef(
    id: 'vat-uzm', icon: '⚖️', name: 'Vatandaş', desc: 'Vatandaşlığın tüm konularını tamamladın', color: const Color(0xFF475569),
    check: (s, subjects) => _allTopicsDone(s, subjects, 'vatandaslik'),
  ),
  BadgeDef(
    id: 'gk-uzm', icon: '📰', name: 'Güncel Takip', desc: 'Güncel Bilgiler konularını tamamladın', color: const Color(0xFFE11D48),
    check: (s, subjects) => _allTopicsDone(s, subjects, 'guncel'),
  ),
  BadgeDef(
    id: 'tam-kpss', icon: '👑', name: 'KPSS Ustası', desc: 'Tüm ders konularını tamamladın!', color: const Color(0xFFD4AF37),
    check: (s, subjects) => subjects.isNotEmpty && subjects.every((subj) => _allTopicsDone(s, subjects, subj.id)),
  ),

  // — Çalışma Süresi (turuncu/kahve tonları) —
  BadgeDef(
    id: 'calisan-ari', icon: '🐝', name: 'Çalışkan Arı', desc: 'Toplamda 1 saat çalıştın', color: const Color(0xFFF59E0B),
    check: (s, subjects) => s.getTotalStudyTime() >= 60,
  ),
  BadgeDef(
    id: 'maratoncu', icon: '🏃', name: 'Maratoncu', desc: 'Toplamda 5 saat çalıştın', color: const Color(0xFFB45309),
    check: (s, subjects) => s.getTotalStudyTime() >= 300,
  ),

  // — Oyunlar (yeşil/turkuaz) —
  BadgeDef(
    id: 'kart-ustasi', icon: '🃏', name: 'Kart Ustası', desc: "Solitaire'de 5 farklı konu tamamladın", color: const Color(0xFF0D9488),
    check: (s, subjects) => s.getGamePassedTopics('solitaire').length >= 5,
  ),
  BadgeDef(
    id: 'hafiza-sampiyonu', icon: '🧩', name: 'Hafıza Şampiyonu', desc: 'Eşleştirme oyununda 5 farklı konu tamamladın', color: const Color(0xFF0891B2),
    check: (s, subjects) => s.getGamePassedTopics('cardgame2').length >= 5,
  ),
  BadgeDef(
    id: 'oyun-tutkunu', icon: '🎮', name: 'Oyun Tutkunu', desc: 'Her iki oyunda da en az bir konu tamamladın', color: const Color(0xFF16A34A),
    check: (s, subjects) =>
        s.getGamePassedTopics('solitaire').isNotEmpty && s.getGamePassedTopics('cardgame2').isNotEmpty,
  ),

  // — Seri (devamı) —
  BadgeDef(
    id: 'seri-14', icon: '🏔️', name: 'Zirvedeki', desc: '14 günlük seri yaptın', color: const Color(0xFF0369A1),
    check: (s, subjects) => ((s.getStreak()['count'] as num?) ?? 0) >= 14,
  ),
  BadgeDef(
    id: 'seri-30', icon: '🌠', name: 'Efsanevi Seri', desc: '30 günlük seri yaptın', color: const Color(0xFF7C2D12),
    check: (s, subjects) => ((s.getStreak()['count'] as num?) ?? 0) >= 30,
  ),

  // — Diğer —
  BadgeDef(
    id: 'yanlis-avcisi', icon: '🔍', name: 'Yanlış Avcısı', desc: "Yanlışlarım bankasından 50+ soru çözdün", color: const Color(0xFFBE185D),
    check: (s, subjects) =>
        s.getAttempts().where((a) => a.topicId == 'wrong-bank').fold<int>(0, (t, a) => t + a.toplam) >= 50,
  ),
  BadgeDef(
    id: 'vip-uye', icon: '💎', name: 'VIP Üye', desc: "Premium'a geçtin", color: const Color(0xFFD4AF37),
    check: (s, subjects) => s.isPremiumUser(),
  ),

  // — Harita Oyunu —
  BadgeDef(
    id: 'harita-fatihi', icon: '🗺️', name: 'Harita Fatihi', desc: "Türkiye haritasındaki tüm 81 ili fethettin!", color: const Color(0xFFB91C1C),
    check: (s, subjects) => s.getGamePassedTopics('haritaoyunu').length >= 81,
  ),

  // — Hızlı Modlar —
  // Günün Patronu günde sadece 1 kez oynanabildiği için 7 tamamlama gerçekte
  // bir hafta boyunca (art arda olması şart değil) her gün gelip oynamak
  // anlamına gelir — bu yüzden eşik 7 olarak seçildi.
  BadgeDef(
    id: 'gunun-patronu', icon: '👑', name: 'Günün Patronu', desc: "Günün Patronu modunu 7 kez tamamladın", color: const Color(0xFF7C3AED),
    check: (s, subjects) => s.getGununPatronuCompletedCount() >= 7,
  ),

  // — Sezon —
  // Basitleştirme: geçmiş sezonların ayrı bir kaydı tutulmuyor (karmaşık
  // olurdu), bu yüzden check sadece "İÇİNDE BULUNULAN sezonda 500+ XP topladın
  // mı" sorusuna bakar (bkz. StorageService.getSeasonXp — ay değişince sıfırlanır).
  BadgeDef(
    id: 'sezon-savascisi', icon: '🏆', name: 'Sezon Savaşçısı', desc: 'Bu sezon (ay) 500+ XP topladın', color: const Color(0xFF9333EA),
    check: (s, subjects) => s.getSeasonXp() >= 500,
  ),
];

/// Henüz kazanılmamış tüm rozetleri kontrol eder, koşulu sağlananları kalıcı
/// olarak açar ve yeni açılanların listesini döner (UI kutlama göstermek
/// için). Testi bittikten sonra (result_screen.dart) ve ana sayfa açılışında
/// çağrılır.
Future<List<BadgeDef>> checkAndUnlockBadges(StorageService storage, List<Subject> subjects) async {
  final newlyUnlocked = <BadgeDef>[];
  for (final b in kBadgeDefs) {
    if (!storage.isBadgeUnlocked(b.id) && b.check(storage, subjects)) {
      final unlocked = await storage.unlockBadge(b.id);
      if (unlocked) newlyUnlocked.add(b);
    }
  }
  return newlyUnlocked;
}
