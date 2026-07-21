import 'package:flutter/foundation.dart';

import '../models/subject.dart';
import 'storage_service.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Günlük Çalışma Planı — veri katmanı
/// ─────────────────────────────────────────────────────────────────────────
///
/// Kullanıcı haftanın hangi GÜNLERİNDE hangi SAAT ARALIĞINDA çalışacağını
/// belirler; bu servis o planı [StorageService] üzerinden kalıcı olarak saklar.
///
/// ÖNEMLİ: StorageService'in `_get`/`_set` yardımcıları private olduğu için
/// burada PUBLIC olan `getSettings()` / `saveSettings(Map)` API'si kullanılıyor
/// ve plan `settings['studyPlan']` altında JSON listesi olarak tutuluyor.
/// Böylece storage_service.dart'a hiç dokunulmadan yeni bir alan eklenmiş olur
/// (aynı desen: cloudBackupEnabled, hideStats vb.).
///
/// LİMİT: Ücretsiz kullanıcı EN FAZLA 1 gün planlayabilir; premium sınırsız.

/// Haftalık plandaki tek bir gün kaydı.
class StudyPlanEntry {
  /// 1 = Pazartesi ... 7 = Pazar (DateTime.weekday ile birebir aynı).
  final int gun;

  final int baslangicSaat;
  final int baslangicDakika;
  final int bitisSaat;
  final int bitisDakika;

  /// Kapalıysa plan listesinde durur ama bildirim kurulmaz.
  final bool aktif;

  const StudyPlanEntry({
    required this.gun,
    required this.baslangicSaat,
    required this.baslangicDakika,
    required this.bitisSaat,
    required this.bitisDakika,
    this.aktif = true,
  });

  StudyPlanEntry copyWith({
    int? gun,
    int? baslangicSaat,
    int? baslangicDakika,
    int? bitisSaat,
    int? bitisDakika,
    bool? aktif,
  }) {
    return StudyPlanEntry(
      gun: gun ?? this.gun,
      baslangicSaat: baslangicSaat ?? this.baslangicSaat,
      baslangicDakika: baslangicDakika ?? this.baslangicDakika,
      bitisSaat: bitisSaat ?? this.bitisSaat,
      bitisDakika: bitisDakika ?? this.bitisDakika,
      aktif: aktif ?? this.aktif,
    );
  }

  Map<String, dynamic> toJson() => {
        'gun': gun,
        'bs': baslangicSaat,
        'bd': baslangicDakika,
        'es': bitisSaat,
        'ed': bitisDakika,
        'aktif': aktif,
      };

  /// Bozuk/eksik JSON'da bile çökmez — makul varsayılanlara düşer.
  static StudyPlanEntry? fromJson(Map<String, dynamic> j) {
    try {
      final gun = ((j['gun'] as num?) ?? 0).toInt();
      if (gun < 1 || gun > 7) return null;
      return StudyPlanEntry(
        gun: gun,
        baslangicSaat: (((j['bs'] as num?) ?? 19).toInt()).clamp(0, 23),
        baslangicDakika: (((j['bd'] as num?) ?? 0).toInt()).clamp(0, 59),
        bitisSaat: (((j['es'] as num?) ?? 20).toInt()).clamp(0, 23),
        bitisDakika: (((j['ed'] as num?) ?? 0).toInt()).clamp(0, 59),
        aktif: j['aktif'] != false,
      );
    } catch (_) {
      return null;
    }
  }

  int get baslangicDakikaToplam => baslangicSaat * 60 + baslangicDakika;
  int get bitisDakikaToplam => bitisSaat * 60 + bitisDakika;

  /// Bitiş, başlangıçtan sonra mı? (Gece yarısını aşan aralık desteklenmiyor.)
  bool get gecerliMi => bitisDakikaToplam > baslangicDakikaToplam;

  /// Seansın dakika cinsinden uzunluğu.
  int get sureDakika => (bitisDakikaToplam - baslangicDakikaToplam).clamp(0, 24 * 60);

  String get baslangicMetni => _ss(baslangicSaat, baslangicDakika);
  String get bitisMetni => _ss(bitisSaat, bitisDakika);
  String get araliqMetni => '$baslangicMetni–$bitisMetni';

  static String _ss(int s, int d) =>
      '${s.toString().padLeft(2, '0')}:${d.toString().padLeft(2, '0')}';
}

/// Plan kaydetme sonucunun anlamlı karşılığı — UI buna göre mesaj gösterir.
enum StudyPlanSaveResult {
  /// Kaydedildi.
  basarili,

  /// Ücretsiz kullanıcı gün limitini aştı — premium'a yönlendirilmeli.
  premiumGerekli,

  /// Saat aralığı geçersiz (bitiş, başlangıçtan önce ya da aynı).
  gecersizSaat,

  /// Beklenmedik bir hata (disk/JSON) — kaydedilemedi.
  hata,
}

/// Bir sonraki çalışma seansının çözülmüş hali.
class NextStudySession {
  final StudyPlanEntry entry;

  /// Seansın başlangıç anı (takvimde ileriye doğru ilk denk gelen).
  final DateTime baslangic;

  /// Seansın bitiş anı.
  final DateTime bitis;

  /// Seans bugüne mi denk geliyor?
  final bool bugunMu;

  /// Şu an seansın tam ortasında mıyız?
  final bool suAnDevamEdiyor;

  const NextStudySession({
    required this.entry,
    required this.baslangic,
    required this.bitis,
    required this.bugunMu,
    required this.suAnDevamEdiyor,
  });
}

/// Zayıf ders önerisi — gerekçesiyle birlikte.
class SubjectSuggestion {
  final SubjectMeta ders;

  /// Bu dersteki ortalama yüzde (0-100).
  final int ortalama;

  const SubjectSuggestion({required this.ders, required this.ortalama});
}

class StudyPlanService {
  final StorageService storage;

  StudyPlanService(this.storage);

  /// settings içindeki alan adı.
  static const String kPlanKey = 'studyPlan';

  /// Ücretsiz kullanıcının planlayabileceği en fazla gün sayısı.
  static const int kFreeMaxDays = 1;

  static const List<String> kGunAdlari = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  static const List<String> kGunKisaAdlari = [
    'Pzt',
    'Sal',
    'Çar',
    'Per',
    'Cum',
    'Cmt',
    'Paz',
  ];

  /// 1-7 aralığındaki gün numarasını "Pazartesi" gibi bir metne çevirir.
  static String gunAdi(int gun) =>
      (gun >= 1 && gun <= 7) ? kGunAdlari[gun - 1] : '';

  static String gunKisaAdi(int gun) =>
      (gun >= 1 && gun <= 7) ? kGunKisaAdlari[gun - 1] : '';

  // ── Okuma ────────────────────────────────────────────────────────────────

  /// Kayıtlı planı güne göre sıralı olarak döner. Hiç plan yoksa boş liste.
  List<StudyPlanEntry> getPlan() {
    try {
      final raw = storage.getSettings()[kPlanKey];
      if (raw is! List) return const [];
      final list = <StudyPlanEntry>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final e = StudyPlanEntry.fromJson(Map<String, dynamic>.from(item));
        if (e != null && list.every((x) => x.gun != e.gun)) list.add(e);
      }
      list.sort((a, b) => a.gun.compareTo(b.gun));
      return list;
    } catch (e) {
      debugPrint('StudyPlanService.getPlan hatası: $e');
      return const [];
    }
  }

  /// Sadece bildirim kurulacak (aktif) günler.
  List<StudyPlanEntry> getActivePlan() => getPlan().where((e) => e.aktif).toList();

  bool get isPremium {
    try {
      return storage.isPremiumUser();
    } catch (_) {
      return false;
    }
  }

  /// Ücretsiz kullanıcı için kalan gün hakkı (premium'da her zaman true).
  bool canAddDay(int gun) {
    if (isPremium) return true;
    final plan = getPlan();
    // Zaten planlı bir günü DÜZENLEMEK limit sayılmaz.
    if (plan.any((e) => e.gun == gun)) return true;
    return plan.length < kFreeMaxDays;
  }

  /// Ücretsiz kullanıcının hâlâ ekleyebileceği gün sayısı (premium'da -1 =
  /// sınırsız).
  int get kalanGunHakki => isPremium ? -1 : (kFreeMaxDays - getPlan().length).clamp(0, kFreeMaxDays);

  // ── Yazma ────────────────────────────────────────────────────────────────

  /// Tüm planı topluca kaydeder. Limit aşılırsa HİÇBİR ŞEY yazılmaz ve
  /// [StudyPlanSaveResult.premiumGerekli] döner.
  Future<StudyPlanSaveResult> savePlan(List<StudyPlanEntry> plan) async {
    try {
      // Aynı gün iki kez girilmişse sonuncusu kazanır.
      final benzersiz = <int, StudyPlanEntry>{};
      for (final e in plan) {
        if (e.gun < 1 || e.gun > 7) continue;
        if (!e.gecerliMi) return StudyPlanSaveResult.gecersizSaat;
        benzersiz[e.gun] = e;
      }
      if (!isPremium && benzersiz.length > kFreeMaxDays) {
        return StudyPlanSaveResult.premiumGerekli;
      }
      final sirali = benzersiz.values.toList()..sort((a, b) => a.gun.compareTo(b.gun));
      await storage.saveSettings({kPlanKey: sirali.map((e) => e.toJson()).toList()});
      return StudyPlanSaveResult.basarili;
    } catch (e) {
      debugPrint('StudyPlanService.savePlan hatası: $e');
      return StudyPlanSaveResult.hata;
    }
  }

  /// Tek bir günü ekler ya da (aynı gün varsa) günceller.
  Future<StudyPlanSaveResult> upsertEntry(StudyPlanEntry entry) async {
    if (!entry.gecerliMi) return StudyPlanSaveResult.gecersizSaat;
    if (!canAddDay(entry.gun)) return StudyPlanSaveResult.premiumGerekli;
    final plan = getPlan().where((e) => e.gun != entry.gun).toList()..add(entry);
    return savePlan(plan);
  }

  /// Bir günü plandan tamamen çıkarır.
  Future<StudyPlanSaveResult> removeEntry(int gun) async {
    final plan = getPlan().where((e) => e.gun != gun).toList();
    return savePlan(plan);
  }

  /// Bir günün aktif/pasif durumunu değiştirir.
  Future<StudyPlanSaveResult> toggleEntry(int gun, bool aktif) async {
    final plan = getPlan();
    final idx = plan.indexWhere((e) => e.gun == gun);
    if (idx == -1) return StudyPlanSaveResult.hata;
    plan[idx] = plan[idx].copyWith(aktif: aktif);
    return savePlan(plan);
  }

  /// Planı tamamen siler.
  Future<StudyPlanSaveResult> clearPlan() => savePlan(const []);

  // ── Bir sonraki seans ────────────────────────────────────────────────────

  /// [now] anından itibaren ilk denk gelen çalışma seansını bulur. Plan yoksa
  /// (ya da tüm günler pasifse) null döner.
  NextStudySession? nextSession([DateTime? now]) {
    try {
      final an = now ?? DateTime.now();
      NextStudySession? enYakin;
      for (final e in getActivePlan()) {
        if (!e.gecerliMi) continue;

        // Bugünden itibaren o güne kaç gün var (0-6).
        var fark = (e.gun - an.weekday) % 7;
        if (fark < 0) fark += 7;

        var baslangic = DateTime(an.year, an.month, an.day + fark,
            e.baslangicSaat, e.baslangicDakika);
        var bitis =
            DateTime(an.year, an.month, an.day + fark, e.bitisSaat, e.bitisDakika);

        // Bugüne denk geliyor ama seans çoktan bittiyse gelecek haftaya kaydır.
        if (bitis.isBefore(an)) {
          baslangic = baslangic.add(const Duration(days: 7));
          bitis = bitis.add(const Duration(days: 7));
        }

        if (enYakin == null || baslangic.isBefore(enYakin.baslangic)) {
          final bugun = baslangic.year == an.year &&
              baslangic.month == an.month &&
              baslangic.day == an.day;
          enYakin = NextStudySession(
            entry: e,
            baslangic: baslangic,
            bitis: bitis,
            bugunMu: bugun,
            suAnDevamEdiyor: !baslangic.isAfter(an) && bitis.isAfter(an),
          );
        }
      }
      return enYakin;
    } catch (e) {
      debugPrint('StudyPlanService.nextSession hatası: $e');
      return null;
    }
  }

  /// Kartta gösterilecek kısa zaman etiketi: "Bugün 19:00–20:30",
  /// "Yarın 09:00–10:00", "Cuma 19:00–20:30".
  String nextSessionLabel([DateTime? now]) {
    final s = nextSession(now);
    if (s == null) return '';
    final an = now ?? DateTime.now();
    final yarin = DateTime(an.year, an.month, an.day + 1);
    final ayniGun = s.baslangic.year == yarin.year &&
        s.baslangic.month == yarin.month &&
        s.baslangic.day == yarin.day;

    final gunEtiketi = s.bugunMu ? 'Bugün' : (ayniGun ? 'Yarın' : gunAdi(s.entry.gun));
    return '$gunEtiketi ${s.entry.araliqMetni}';
  }

  /// "2 saat 15 dakika sonra" / "Şu anda çalışma vaktin!" gibi ikinci satır.
  String nextSessionCountdown([DateTime? now]) {
    final s = nextSession(now);
    if (s == null) return '';
    if (s.suAnDevamEdiyor) return 'Şu anda çalışma vaktin! 🔥';

    final an = now ?? DateTime.now();
    final kalan = s.baslangic.difference(an);
    if (kalan.inMinutes < 1) return 'Birazdan başlıyor';
    if (kalan.inHours < 1) return '${kalan.inMinutes} dakika sonra';
    if (kalan.inHours < 24) {
      final saat = kalan.inHours;
      final dakika = kalan.inMinutes % 60;
      return dakika == 0 ? '$saat saat sonra' : '$saat saat $dakika dakika sonra';
    }
    return '${kalan.inDays} gün sonra';
  }

  // ── Ders önerisi ─────────────────────────────────────────────────────────

  /// Çözülen testlerin ortalamalarına bakıp EN DÜŞÜK ortalamalı dersi önerir.
  /// Hiç test çözülmemişse null döner.
  SubjectSuggestion? weakestSubject() {
    try {
      SubjectSuggestion? enZayif;
      for (final s in kSubjects) {
        final ort = storage.computeSubjectAvg(s.id);
        if (ort == null) continue; // Bu ders hiç çözülmemiş.
        if (enZayif == null || ort < enZayif.ortalama) {
          enZayif = SubjectSuggestion(ders: s, ortalama: ort);
        }
      }
      return enZayif;
    } catch (e) {
      debugPrint('StudyPlanService.weakestSubject hatası: $e');
      return null;
    }
  }

  /// Öneri cümlesi — veri yoksa kullanıcıyı test çözmeye davet eder.
  String suggestionText() {
    final z = weakestSubject();
    if (z == null) return 'Önce birkaç test çöz, sana özel öneri hazırlayayım.';
    return '${z.ders.ad} ortalaman %${z.ortalama} — en zayıf dersin. Planına bu dersi koy.';
  }

  /// Kart için tek satırlık kısa hâli.
  String shortSuggestionText() {
    final z = weakestSubject();
    if (z == null) return 'Birkaç test çöz, sana özel ders önerisi çıkaralım.';
    return '${z.ders.icon} Odaklan: ${z.ders.ad} (%${z.ortalama})';
  }
}
