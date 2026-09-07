import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../models/question.dart';
import '../models/subject.dart';

/// Soru havuzlarının kaynağını yöneten servis.
///
/// TASARIM (Firestore → GitHub geçişi sonrası):
///
/// 1. SORULAR VARSAYILAN OLARAK LOCALDE. Uygulamayla birlikte gelen
///    `assets/data/*.json` dosyaları (bkz. DataService) tüm soruları içerir.
///    Açılışta, konu ekranına girildiğinde, teste başlarken HİÇBİR ağ çağrısı
///    yapılmaz — [getPool] her zaman ANINDA döner, internet gerekmez.
/// 2. GÜNCELLEME İSTEĞE BAĞLI ve KULLANICI TETİKLİDİR. Ayarlar >
///    "Soruları Güncelle" butonu [checkAndUpdate] çağırır; sorular GitHub
///    deposundaki `assets/data/` klasöründen indirilir ve cihazda
///    (`<belgeler>/qcache/<konuId>.json`) önbelleklenir. Önbellek varsa
///    [getPool] gömülü sorular yerine onu döndürür.
/// 3. SÜRÜM KONTROLÜ ZORUNLUDUR. Hem uygulamanın içinde hem de GitHub'da
///    `version.json` bulunur; indirme YALNIZCA uzak `surum` yereldekinden
///    BÜYÜKSE yapılır. Aksi halde depodaki (belki daha eski) dosyalar
///    soruları geriye alırdı.
///
/// Kullanılmış soru takibi (tekrar etmeme, havuz bitince karışık tekrar)
/// StorageService.getUsedQuestions/addUsedQuestions + QuestionPicker içinde
/// zaten var — bu servis sadece HAVUZUN KAYNAĞINI belirler, o mantığa
/// dokunmaz.
///
/// KURAL: Buradaki hiçbir metod istisna fırlatmaz. Ağ hatası, 404, bozuk
/// JSON, dosya sistemi hatası — hepsi yakalanır ve güvenli varsayılana
/// (gömülü sorular / "zaten güncel") düşülür.

/// Soru dosyalarının çekildiği GitHub raw kök adresi (sonunda `/` var).
const String kGithubRawBase =
    'https://raw.githubusercontent.com/yunusemrecelikelll-cloud/Kpss_Android/master/assets/data/';

/// Uygulamayla gömülü gelen sürüm dosyası.
const String kLocalVersionAsset = 'assets/data/version.json';

/// Uzak/yerel sürüm bilgisini taşıyan basit kayıt.
class ContentVersion {
  final int surum;
  final DateTime? guncellemeTarihi;
  final int toplamSoru;

  const ContentVersion({
    required this.surum,
    this.guncellemeTarihi,
    this.toplamSoru = 0,
  });

  /// Bozuk/eksik alanlara karşı tamamen savunmacı ayrıştırma.
  static ContentVersion? tryParse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final surum = (json['surum'] as num?)?.toInt();
      if (surum == null) return null;
      DateTime? tarih;
      final t = json['guncellemeTarihi'];
      if (t is String) tarih = DateTime.tryParse(t);
      return ContentVersion(
        surum: surum,
        guncellemeTarihi: tarih,
        toplamSoru: (json['toplamSoru'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'surum': surum,
        'guncellemeTarihi':
            (guncellemeTarihi ?? DateTime.now()).toIso8601String().split('T').first,
        'toplamSoru': toplamSoru,
      };
}

/// "Soruları Güncelle" sonucunun kullanıcıya nasıl anlatılacağını belirler.
enum UpdateOutcome {
  /// Yeni sorular indirildi ([QuestionUpdateResult.yeniSoruSayisi] kadar).
  guncellendi,

  /// Uzak sürüm yereldekiyle aynı ya da daha eski — hiçbir şey yapılmadı.
  zatenGuncel,

  /// İnternet yok / sunucuya ulaşılamadı / veri bozuk — DÜRÜST hata mesajı.
  hata,
}

class QuestionUpdateResult {
  final UpdateOutcome sonuc;
  final int yeniSoruSayisi;
  final DateTime? guncellemeTarihi;

  const QuestionUpdateResult(
    this.sonuc, {
    this.yeniSoruSayisi = 0,
    this.guncellemeTarihi,
  });
}

class RemoteQuestionService {
  // ── Önbellek dosyaları ──────────────────────────────────────────────

  Future<Directory> _cacheDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final qdir = Directory("${dir.path}/qcache");
    if (!await qdir.exists()) {
      await qdir.create(recursive: true);
    }
    return qdir;
  }

  /// null dönerse (path_provider kanalı henüz kayıtlı değil, platform
  /// desteklemiyor, disk hatası vb.) önbellekleme tamamen devre dışı kalır —
  /// çağıran taraflar HER ZAMAN gömülü soruları kullanmaya devam eder.
  Future<File?> _cacheFileFor(String topicId) async {
    try {
      final dir = await _cacheDir();
      return File("${dir.path}/$topicId.json");
    } catch (_) {
      return null;
    }
  }

  /// İndirilmiş içeriğin sürümünü tutan dosya (uygulama içindeki
  /// `version.json`'ın önbellek karşılığı).
  Future<File?> _cachedVersionFile() async {
    try {
      final dir = await _cacheDir();
      return File("${dir.path}/version.json");
    } catch (_) {
      return null;
    }
  }

  // ── Soru havuzu (her zaman ANINDA, ağ YOK) ──────────────────────────

  /// Eskiden konu ekranı açılınca sessizce indirme başlatırdı. Sorular artık
  /// uygulamayla birlikte geldiği için ARTIK HİÇBİR ŞEY YAPMAZ (no-op) —
  /// çağıran ekranlar (topic_screen vb.) kırılmasın diye metod korunuyor.
  Future<void> prefetch(String topicId) async {
    // Bilinçli olarak boş: açılışta/konu girişinde ağa çıkılmaz.
  }

  /// Bir konu için o an kullanılabilecek soru havuzunu ANINDA döner:
  /// güncelleme ile indirilmiş bir önbellek varsa ondan, yoksa [fallback]
  /// (uygulamayla gömülü sorular). Ağ beklemez, istisna fırlatmaz.
  Future<List<Question>> getPool(String topicId, List<Question> fallback) async {
    try {
      final file = await _cacheFileFor(topicId);
      if (file != null && await file.exists()) {
        try {
          final raw = jsonDecode(await file.readAsString()) as List;
          final qs = raw
              .map((q) => Question.fromJson(Map<String, dynamic>.from(q as Map)))
              .toList();
          if (qs.isNotEmpty) return qs;
        } catch (_) {
          // Bozuk önbellek — gömülü sorulara düş.
        }
      }
    } catch (_) {
      // Beklenmeyen hata (ör. path_provider kanalı hazır değil) — gömülü
      // sorulara düş.
    }
    return fallback;
  }

  // ── Sürüm okuma ─────────────────────────────────────────────────────

  /// Uygulamayla GÖMÜLÜ gelen sürüm (`assets/data/version.json`).
  Future<ContentVersion> _embeddedVersion() async {
    try {
      final raw = await rootBundle.loadString(kLocalVersionAsset);
      return ContentVersion.tryParse(raw) ?? const ContentVersion(surum: 0);
    } catch (_) {
      return const ContentVersion(surum: 0);
    }
  }

  /// Daha önce indirilmiş içeriğin sürümü (yoksa null).
  Future<ContentVersion?> _downloadedVersion() async {
    try {
      final file = await _cachedVersionFile();
      if (file == null || !await file.exists()) return null;
      return ContentVersion.tryParse(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// Cihazda ŞU AN yüklü olan içerik sürümü: gömülü ile indirilmişten hangisi
  /// büyükse o.
  ///
  /// Uygulama güncellenip gömülü sürüm indirilmiş sürümü GEÇTİYSE, eski
  /// indirmenin önbelleği artık bayattır — silinir ki gömülü (daha yeni)
  /// sorular kullanılsın.
  Future<ContentVersion> yukluSurum() async {
    final embedded = await _embeddedVersion();
    final downloaded = await _downloadedVersion();
    if (downloaded == null) return embedded;
    if (embedded.surum >= downloaded.surum) {
      await _purgeCache();
      return embedded;
    }
    return downloaded;
  }

  /// İndirilmiş tüm soru önbelleğini siler (bayat içerik temizliği).
  Future<void> _purgeCache() async {
    try {
      final dir = await _cacheDir();
      await for (final f in dir.list()) {
        if (f is File) {
          try {
            await f.delete();
          } catch (_) {
            // Tek dosya silinemezse devam et.
          }
        }
      }
    } catch (_) {
      // Sessizce geç.
    }
  }

  // ── GitHub erişimi ──────────────────────────────────────────────────

  /// `http` paketi projede olmadığı için `dart:io HttpClient` kullanılır.
  /// Web'de çalışmaz — [kIsWeb] durumunda hiç denenmez, null döner
  /// (çağıranlar bunu "güncelleme yok" olarak yorumlar).
  Future<String?> _httpGet(String url) async {
    if (kIsWeb) return null;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) {
        // 404 dahil: dosya henüz depoda yok → "zaten güncel" sayılır.
        await res.drain<void>();
        return null;
      }
      return await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 25));
    } catch (_) {
      return null;
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {
        // Yoksay.
      }
    }
  }

  /// GitHub'daki `version.json`. Ulaşılamazsa / 404 ise / bozuksa null.
  Future<ContentVersion?> _remoteVersion() async {
    final raw = await _httpGet('$kGithubRawBase' 'version.json');
    if (raw == null) return null;
    return ContentVersion.tryParse(raw);
  }

  // ── Güncelleme akışı ────────────────────────────────────────────────

  /// Ayarlar > "Soruları Güncelle" — tek adımda kontrol eder ve gerekiyorsa
  /// indirir.
  ///
  /// • Uzak `surum` > yerel `surum` ise tüm ders dosyaları GitHub'dan çekilip
  ///   konu bazında önbelleğe yazılır → [UpdateOutcome.guncellendi].
  /// • Uzak sürüm aynı/daha eski ya da `version.json` depoda yoksa hiçbir şey
  ///   yapılmaz → [UpdateOutcome.zatenGuncel]. (KRİTİK: sürüm kontrolü
  ///   olmadan indirmek soruları GERİYE ALABİLİR.)
  /// • İnternet yok / indirme yarıda kaldıysa → [UpdateOutcome.hata].
  Future<QuestionUpdateResult> checkAndUpdate() async {
    if (kIsWeb) return const QuestionUpdateResult(UpdateOutcome.zatenGuncel);
    try {
      final local = await yukluSurum();
      // Önce ağ erişimi var mı anla: version.json okunamazsa bunun nedeni
      // internet yokluğu da olabilir, dosyanın depoda olmaması da. Ayırt
      // etmek için bir kez daha denemek yerine, ders dosyalarından birine
      // bakmadan "zaten güncel" demek yanıltıcı olurdu → bağlantıyı bir HEAD
      // yerine aynı istekle test ediyoruz.
      final remoteRaw = await _httpGet('$kGithubRawBase' 'version.json');
      if (remoteRaw == null) {
        // Depoda dosya yoksa da, internet yoksa da buraya düşülür. Kullanıcıya
        // dürüst olmak için bağlantıyı ayrıca doğrula.
        final baglanti = await _internetVarMi();
        return QuestionUpdateResult(
          baglanti ? UpdateOutcome.zatenGuncel : UpdateOutcome.hata,
        );
      }
      final remote = ContentVersion.tryParse(remoteRaw);
      if (remote == null || remote.surum <= local.surum) {
        return const QuestionUpdateResult(UpdateOutcome.zatenGuncel);
      }

      final indirilen = await _downloadAllSubjects();
      if (indirilen == null) {
        return const QuestionUpdateResult(UpdateOutcome.hata);
      }

      // Yeni sürümü kaydet — bir sonraki kontrol buna göre karşılaştırır.
      await _saveDownloadedVersion(remote);

      // "N yeni soru": önce sürüm dosyalarındaki toplamlar, o alanlar yoksa
      // gerçekten indirilen soru sayısı ile yereldeki farkı kullan.
      var yeni = remote.toplamSoru - local.toplamSoru;
      if (remote.toplamSoru <= 0 || local.toplamSoru <= 0) {
        yeni = indirilen - local.toplamSoru;
      }
      if (yeni < 0) yeni = 0;
      return QuestionUpdateResult(
        UpdateOutcome.guncellendi,
        yeniSoruSayisi: yeni,
        guncellemeTarihi: remote.guncellemeTarihi,
      );
    } catch (_) {
      return const QuestionUpdateResult(UpdateOutcome.hata);
    }
  }

  /// version.json çekilemediğinde "internet yok" ile "dosya depoda yok"u
  /// ayırmak için küçük bir yoklama.
  Future<bool> _internetVarMi() async {
    try {
      final r = await InternetAddress.lookup('raw.githubusercontent.com')
          .timeout(const Duration(seconds: 8));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Tüm ders dosyalarını GitHub'dan çekip konu bazında önbelleğe yazar.
  /// Başarılıysa indirilen TOPLAM soru sayısını, herhangi bir ders
  /// alınamazsa null döner (yarım güncelleme uygulanmaz).
  Future<int?> _downloadAllSubjects() async {
    // Önce hepsini indir + ayrıştır, hepsi tamamsa diske yaz — böylece ağ
    // ortada koparsa yarım/karışık bir soru bankası oluşmaz.
    final yazilacak = <String, List<dynamic>>{};
    var toplam = 0;
    for (final meta in kSubjects) {
      final dosyaAdi = meta.dosya.split('/').last;
      final raw = await _httpGet('$kGithubRawBase$dosyaAdi');
      if (raw == null) return null;
      try {
        final json = jsonDecode(raw);
        if (json is! Map) return null;
        final konular = json['konular'] as List? ?? const [];
        for (final k in konular) {
          if (k is! Map) continue;
          final id = k['id'] as String?;
          if (id == null) continue;
          final sorular = k['sorular'] as List? ?? const [];
          yazilacak[id] = sorular;
          toplam += sorular.length;
        }
      } catch (_) {
        return null;
      }
    }
    if (yazilacak.isEmpty) return null;

    try {
      for (final entry in yazilacak.entries) {
        final file = await _cacheFileFor(entry.key);
        if (file == null) return null;
        await file.writeAsString(jsonEncode(entry.value));
      }
    } catch (_) {
      return null;
    }
    return toplam;
  }

  Future<void> _saveDownloadedVersion(ContentVersion v) async {
    try {
      final file = await _cachedVersionFile();
      if (file == null) return;
      await file.writeAsString(jsonEncode(v.toJson()));
    } catch (_) {
      // Sessizce geç: en kötü ihtimalle bir sonraki kontrolde aynı sürüm
      // yeniden indirilir.
    }
  }

  // ── Anasayfa banner'ı ───────────────────────────────────────────────

  /// Anasayfadaki "Yeni sorular eklendi" banner'ı için (bkz. home_screen.dart
  /// → _checkContentUpdate). GitHub'daki `version.json` yereldekinden yeniyse
  /// o güncellemenin tarihini, değilse null döner.
  ///
  /// İmza korunuyor (DateTime?); artık Firestore değil GitHub sürüm dosyası
  /// okunur. İnternet yoksa, dosya yoksa (404) veya JSON bozuksa null döner —
  /// banner gösterilmez, asla istisna fırlatmaz.
  Future<DateTime?> getServerContentUpdatedAt() async {
    if (kIsWeb) return null;
    try {
      final local = await yukluSurum();
      final remote = await _remoteVersion();
      if (remote == null || remote.surum <= local.surum) return null;
      // Tarih alanı yoksa/bozuksa da banner çıkabilsin diye "şimdi" kullanılır.
      return remote.guncellemeTarihi ?? DateTime.now();
    } catch (_) {
      return null;
    }
  }
}
