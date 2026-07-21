import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/subject.dart';
import 'storage_service.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Günlük Çalışma Planı — veri katmanı
/// ─────────────────────────────────────────────────────────────────────────
///
/// Kullanıcı haftanın hangi GÜNLERİNDE hangi SAAT ARALIKLARINDA çalışacağını
/// belirler; bu servis o planı [StorageService] üzerinden kalıcı olarak saklar.
///
/// ÇOKLU SEANS: Aynı gün için BİRDEN FAZLA çalışma aralığı (seans) tanımlanır.
/// Örn. Pazartesi 09:00–11:00 ve 19:00–21:00. Her seansın kendine ait bir [id]
/// değeri vardır; düzenleme/silme/aç-kapa işlemleri bu id üzerinden yürür.
///
/// ÖNEMLİ: StorageService'in `_get`/`_set` yardımcıları private olduğu için
/// burada PUBLIC olan `getSettings()` / `saveSettings(Map)` API'si kullanılıyor
/// ve plan `settings['studyPlan']` altında JSON listesi olarak tutuluyor.
/// Böylece storage_service.dart'a hiç dokunulmadan yeni bir alan eklenmiş olur
/// (aynı desen: cloudBackupEnabled, hideStats vb.).
///
/// LİMİT: Ücretsiz kullanıcı EN FAZLA 1 GÜN planlayabilir (o güne istediği
/// kadar seans ekleyebilir); premium sınırsız gün.

/// Haftalık plandaki tek bir çalışma seansı.
class StudyPlanEntry {
  /// Seansın benzersiz kimliği — aynı güne birden fazla seans eklenebildiği
  /// için düzenleme/silme bu değere göre yapılır.
  final String id;

  /// 1 = Pazartesi ... 7 = Pazar (DateTime.weekday ile birebir aynı).
  final int gun;

  final int baslangicSaat;
  final int baslangicDakika;
  final int bitisSaat;
  final int bitisDakika;

  /// Kapalıysa plan listesinde durur ama bildirim kurulmaz.
  final bool aktif;

  const StudyPlanEntry({
    required this.id,
    required this.gun,
    required this.baslangicSaat,
    required this.baslangicDakika,
    required this.bitisSaat,
    required this.bitisDakika,
    this.aktif = true,
  });

  static final Random _rnd = Random();

  /// Yeni bir seans kimliği üretir (zaman damgası + rastgele son ek).
  static String yeniId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_rnd.nextInt(1 << 20).toRadixString(36)}';

  StudyPlanEntry copyWith({
    String? id,
    int? gun,
    int? baslangicSaat,
    int? baslangicDakika,
    int? bitisSaat,
    int? bitisDakika,
    bool? aktif,
  }) {
    return StudyPlanEntry(
      id: id ?? this.id,
      gun: gun ?? this.gun,
      baslangicSaat: baslangicSaat ?? this.baslangicSaat,
      baslangicDakika: baslangicDakika ?? this.baslangicDakika,
      bitisSaat: bitisSaat ?? this.bitisSaat,
      bitisDakika: bitisDakika ?? this.bitisDakika,
      aktif: aktif ?? this.aktif,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'gun': gun,
        'bs': baslangicSaat,
        'bd': baslangicDakika,
        'es': bitisSaat,
        'ed': bitisDakika,
        'aktif': aktif,
      };

  /// Bozuk/eksik JSON'da bile çökmez — makul varsayılanlara düşer.
  /// ESKİ KAYITLAR: `id` alanı olmayan (tek seanslı dönemden kalma) kayıtlara
  /// otomatik olarak yeni bir kimlik verilir; veri kaybı olmaz.
  static StudyPlanEntry? fromJson(Map<String, dynamic> j) {
    try {
      final gun = ((j['gun'] as num?) ?? 0).toInt();
      if (gun < 1 || gun > 7) return null;
      final ham = (j['id'] as String?)?.trim();
      return StudyPlanEntry(
        id: (ham == null || ham.isEmpty) ? yeniId() : ham,
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

  /// İki seans aynı gün içinde zaman olarak üst üste biniyor mu?
  bool cakisiyorMu(StudyPlanEntry other) {
    if (other.gun != gun) return false;
    return baslangicDakikaToplam < other.bitisDakikaToplam &&
        other.baslangicDakikaToplam < bitisDakikaToplam;
  }

  /// 24 saat biçiminde başlangıç saati ("09:00").
  String get baslangicMetni => _ss(baslangicSaat, baslangicDakika);

  /// 24 saat biçiminde bitiş saati ("20:30").
  String get bitisMetni => _ss(bitisSaat, bitisDakika);

  /// "19:00–20:30" — her zaman 24 saat biçimi (Türkiye standardı).
  String get araliqMetni => '$baslangicMetni–$bitisMetni';

  static String _ss(int s, int d) =>
      '${s.toString().padLeft(2, '0')}:${d.toString().padLeft(2, '0')}';
}

/// Plan kaydetme sonucunun anlamlı karşılığı — UI buna göre mesaj gösterir.
enum StudyPlanSaveResult {
  /// Kaydedildi.
  basarili,

  /// Ücretsiz kullanıcı GÜN limitini aştı — premium'a yönlendirilmeli.
  premiumGerekli,

  /// Saat aralığı geçersiz (bitiş, başlangıçtan önce ya da aynı).
  gecersizSaat,

  /// Aynı gün içindeki başka bir seansla zaman çakışması var.
  cakisma,

  /// Bir güne eklenebilecek en fazla seans sayısı aşıldı.
  seansLimiti,

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

  /// Ücretsiz kullanıcının planlayabileceği en fazla GÜN sayısı.
  /// (O güne eklenebilecek seans sayısı sınırsızdır — bkz. [kMaxSeansPerGun].)
  static const int kFreeMaxDays = 1;

  /// Tek bir güne eklenebilecek en fazla seans sayısı. Bildirim kimlik şeması
  /// bu sayıya göre bölmelendiği için (bkz. NotificationService) sabit tutulur.
  static const int kMaxSeansPerGun = 12;

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

  /// Kayıtlı planı gün ve başlangıç saatine göre sıralı döner. Plan yoksa boş
  /// liste. Aynı gün için birden fazla seans dönebilir.
  List<StudyPlanEntry> getPlan() {
    try {
      final raw = storage.getSettings()[kPlanKey];
      if (raw is! List) return const [];
      final list = <StudyPlanEntry>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final e = StudyPlanEntry.fromJson(Map<String, dynamic>.from(item));
        // Aynı kimlik iki kez geldiyse ilki geçerli sayılır.
        if (e != null && list.every((x) => x.id != e.id)) list.add(e);
      }
      list.sort(_sirala);
      return list;
    } catch (e) {
      debugPrint('StudyPlanService.getPlan hatası: $e');
      return const [];
    }
  }

  /// Önce güne, sonra başlangıç saatine göre sıralama.
  static int _sirala(StudyPlanEntry a, StudyPlanEntry b) {
    final g = a.gun.compareTo(b.gun);
    if (g != 0) return g;
    return a.baslangicDakikaToplam.compareTo(b.baslangicDakikaToplam);
  }

  /// Sadece bildirim kurulacak (aktif) seanslar.
  List<StudyPlanEntry> getActivePlan() => getPlan().where((e) => e.aktif).toList();

  /// Verilen günün seansları (saate göre sıralı).
  List<StudyPlanEntry> getGunSeanslari(int gun) =>
      getPlan().where((e) => e.gun == gun).toList();

  /// Planda en az bir seansı olan günlerin kümesi.
  Set<int> get planlananGunler => getPlan().map((e) => e.gun).toSet();

  bool get isPremium {
    try {
      return storage.isPremiumUser();
    } catch (_) {
      return false;
    }
  }

  /// Bu güne yeni seans eklenebilir mi? Ücretsiz kullanıcı yalnızca
  /// [kFreeMaxDays] farklı GÜN planlayabilir; zaten planlı bir güne seans
  /// eklemek limite takılmaz.
  bool canAddDay(int gun) {
    if (isPremium) return true;
    final gunler = planlananGunler;
    if (gunler.contains(gun)) return true;
    return gunler.length < kFreeMaxDays;
  }

  /// Ücretsiz kullanıcının hâlâ ekleyebileceği GÜN sayısı (premium'da -1 =
  /// sınırsız).
  int get kalanGunHakki => isPremium
      ? -1
      : (kFreeMaxDays - planlananGunler.length).clamp(0, kFreeMaxDays);

  // ── Yazma ────────────────────────────────────────────────────────────────

  /// Tüm planı topluca kaydeder. Doğrulamaların herhangi biri başarısız olursa
  /// HİÇBİR ŞEY yazılmaz ve ilgili sonuç döner.
  Future<StudyPlanSaveResult> savePlan(List<StudyPlanEntry> plan) async {
    try {
      final temiz = <StudyPlanEntry>[];
      final gorulenId = <String>{};
      for (final e in plan) {
        if (e.gun < 1 || e.gun > 7) continue;
        if (!e.gecerliMi) return StudyPlanSaveResult.gecersizSaat;
        if (!gorulenId.add(e.id)) continue; // Aynı kimlik iki kez gelmesin.
        temiz.add(e);
      }

      // Gün bazlı doğrulamalar: seans sayısı + çakışma.
      final gunBazli = <int, List<StudyPlanEntry>>{};
      for (final e in temiz) {
        (gunBazli[e.gun] ??= <StudyPlanEntry>[]).add(e);
      }
      for (final seanslar in gunBazli.values) {
        if (seanslar.length > kMaxSeansPerGun) {
          return StudyPlanSaveResult.seansLimiti;
        }
        for (var i = 0; i < seanslar.length; i++) {
          for (var j = i + 1; j < seanslar.length; j++) {
            if (seanslar[i].cakisiyorMu(seanslar[j])) {
              return StudyPlanSaveResult.cakisma;
            }
          }
        }
      }

      if (!isPremium && gunBazli.length > kFreeMaxDays) {
        return StudyPlanSaveResult.premiumGerekli;
      }

      temiz.sort(_sirala);
      await storage.saveSettings({kPlanKey: temiz.map((e) => e.toJson()).toList()});
      return StudyPlanSaveResult.basarili;
    } catch (e) {
      debugPrint('StudyPlanService.savePlan hatası: $e');
      return StudyPlanSaveResult.hata;
    }
  }

  /// Tek bir seansı ekler ya da (aynı [StudyPlanEntry.id] varsa) günceller.
  Future<StudyPlanSaveResult> upsertSession(StudyPlanEntry entry) async {
    if (!entry.gecerliMi) return StudyPlanSaveResult.gecersizSaat;
    if (!canAddDay(entry.gun)) return StudyPlanSaveResult.premiumGerekli;

    final digerleri = getPlan().where((e) => e.id != entry.id).toList();

    // Aynı gündeki başka bir seansla çakışıyor mu? (Kullanıcıya net mesaj
    // verebilmek için savePlan'a gitmeden önce burada da kontrol ediliyor.)
    if (digerleri.any((e) => e.cakisiyorMu(entry))) {
      return StudyPlanSaveResult.cakisma;
    }
    final ayniGun = digerleri.where((e) => e.gun == entry.gun).length;
    if (ayniGun + 1 > kMaxSeansPerGun) return StudyPlanSaveResult.seansLimiti;

    return savePlan(digerleri..add(entry));
  }

  /// Tek bir seansı plandan çıkarır.
  Future<StudyPlanSaveResult> removeSession(String id) async {
    final plan = getPlan().where((e) => e.id != id).toList();
    return savePlan(plan);
  }

  /// Bir günün TÜM seanslarını plandan çıkarır.
  Future<StudyPlanSaveResult> removeDay(int gun) async {
    final plan = getPlan().where((e) => e.gun != gun).toList();
    return savePlan(plan);
  }

  /// Bir seansın aktif/pasif durumunu değiştirir.
  Future<StudyPlanSaveResult> toggleSession(String id, bool aktif) async {
    final plan = getPlan();
    final idx = plan.indexWhere((e) => e.id == id);
    if (idx == -1) return StudyPlanSaveResult.hata;
    plan[idx] = plan[idx].copyWith(aktif: aktif);
    return savePlan(plan);
  }

  /// Bir günün tüm seanslarını topluca açar/kapatır.
  Future<StudyPlanSaveResult> toggleDay(int gun, bool aktif) async {
    final plan = getPlan()
        .map((e) => e.gun == gun ? e.copyWith(aktif: aktif) : e)
        .toList();
    return savePlan(plan);
  }

  /// Planı tamamen siler.
  Future<StudyPlanSaveResult> clearPlan() => savePlan(const []);

  // ── Bir sonraki seans ────────────────────────────────────────────────────

  /// [now] anından itibaren ilk denk gelen çalışma seansını bulur. Plan yoksa
  /// (ya da tüm seanslar pasifse) null döner.
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
  /// "Yarın 09:00–10:00", "Cuma 19:00–20:30" (her zaman 24 saat biçimi).
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
