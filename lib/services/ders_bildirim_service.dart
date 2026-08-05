import 'dart:math';

import 'storage_service.dart';
import 'study_plan_service.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Ders Bildirimleri — veri katmanı (kullanıcı isteği)
/// ─────────────────────────────────────────────────────────────────────────
///
/// Kullanıcı, İSTEDİĞİ DERSTEN, İSTEDİĞİ GÜN ve SAATTE bildirim alabilir.
/// Bildirim içeriği kısa akılda kalıcı kodlama / motivasyon / "bunu biliyor
/// musun?" metinleridir (bkz. lib/data/bildirim_icerik.dart). Bir güne İSTENEN
/// KADAR alarm eklenebilir; farklı günlere farklı ders/saat seçilebilir.
///
/// Depolama: Çalışma Planı ile aynı desen — `settings['dersBildirimleri']`
/// altında JSON listesi (storage_service.dart'a dokunmadan). Bildirimlerin
/// kurulması NotificationService.scheduleDersBildirimleri ile yapılır.

/// Tek bir ders bildirimi (gün + saat + ders + içerik türleri).
class DersBildirimi {
  final String id;

  /// 1 = Pazartesi ... 7 = Pazar (DateTime.weekday ile aynı).
  final int gun;
  final int saat;
  final int dakika;
  final String dersId;

  /// Kullanıcının seçtiği içerik türleri (bkz. DersBildirimService.turAnahtarlari):
  /// 'kodlama', 'motivasyon', 'biliyor', 'anlatim'. Boşsa tüm türler kullanılır.
  final List<String> turler;

  final bool aktif;

  const DersBildirimi({
    required this.id,
    required this.gun,
    required this.saat,
    required this.dakika,
    required this.dersId,
    this.turler = const [],
    this.aktif = true,
  });

  static final Random _rnd = Random();

  static String yeniId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_rnd.nextInt(1 << 20).toRadixString(36)}';

  int get dakikaToplam => saat * 60 + dakika;

  String get saatMetni =>
      '${saat.toString().padLeft(2, '0')}:${dakika.toString().padLeft(2, '0')}';

  DersBildirimi copyWith({
    String? id,
    int? gun,
    int? saat,
    int? dakika,
    String? dersId,
    List<String>? turler,
    bool? aktif,
  }) =>
      DersBildirimi(
        id: id ?? this.id,
        gun: gun ?? this.gun,
        saat: saat ?? this.saat,
        dakika: dakika ?? this.dakika,
        dersId: dersId ?? this.dersId,
        turler: turler ?? this.turler,
        aktif: aktif ?? this.aktif,
      );

  /// Etkin türler — boşsa tüm türler.
  List<String> get etkinTurler =>
      turler.isEmpty ? DersBildirimService.turAnahtarlari : turler;

  Map<String, dynamic> toJson() => {
        'id': id,
        'gun': gun,
        's': saat,
        'd': dakika,
        'ders': dersId,
        't': turler,
        'aktif': aktif,
      };

  /// Bozuk/eksik JSON'da bile çökmez.
  static DersBildirimi? fromJson(Map<String, dynamic> j) {
    try {
      final gun = ((j['gun'] as num?) ?? 0).toInt();
      if (gun < 1 || gun > 7) return null;
      final ders = (j['ders'] as String?)?.trim();
      if (ders == null || ders.isEmpty) return null;
      final ham = (j['id'] as String?)?.trim();
      final turHam = (j['t'] as List?)
              ?.whereType<String>()
              .where(DersBildirimService.turAnahtarlari.contains)
              .toList() ??
          const <String>[];
      return DersBildirimi(
        id: (ham == null || ham.isEmpty) ? yeniId() : ham,
        gun: gun,
        saat: (((j['s'] as num?) ?? 20).toInt()).clamp(0, 23),
        dakika: (((j['d'] as num?) ?? 0).toInt()).clamp(0, 59),
        dersId: ders,
        turler: turHam,
        aktif: j['aktif'] != false,
      );
    } catch (_) {
      return null;
    }
  }
}

class DersBildirimService {
  static const String _key = 'dersBildirimleri';

  /// İçerik türleri: (anahtar, emoji, kısa ad). Kullanıcı bildirimde hangi
  /// içerik türlerini istediğini seçer (bkz. kBildirimIcerikleri).
  static const List<(String, String, String)> turler = [
    ('kodlama', '🧠', 'Kodlama'),
    ('motivasyon', '💪', 'Motivasyon'),
    ('biliyor', '💡', 'Bunu biliyor musun?'),
    ('anlatim', '📌', 'Kısa bilgi'),
  ];

  static const List<String> turAnahtarlari = [
    'kodlama', 'motivasyon', 'biliyor', 'anlatim'
  ];

  static String turAd(String anahtar) => turler
      .firstWhere((t) => t.$1 == anahtar, orElse: () => (anahtar, '•', anahtar))
      .$3;
  static String turEmoji(String anahtar) => turler
      .firstWhere((t) => t.$1 == anahtar, orElse: () => (anahtar, '•', anahtar))
      .$2;

  static const List<String> _gunKisa = [
    'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'
  ];
  static const List<String> _gunUzun = [
    'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'
  ];

  static String gunKisa(int g) => _gunKisa[(g - 1).clamp(0, 6)];
  static String gunUzun(int g) => _gunUzun[(g - 1).clamp(0, 6)];

  /// Kayıtlı ders bildirimlerini gün ve saate göre sıralı döndürür.
  List<DersBildirimi> getir(StorageService storage) {
    final raw = storage.getSettings()[_key];
    if (raw is! List) return [];
    final list = raw
        .whereType<Map>()
        .map((m) => DersBildirimi.fromJson(Map<String, dynamic>.from(m)))
        .whereType<DersBildirimi>()
        .toList();
    list.sort((a, b) {
      final g = a.gun.compareTo(b.gun);
      if (g != 0) return g;
      return a.dakikaToplam.compareTo(b.dakikaToplam);
    });
    return list;
  }

  Future<void> kaydet(StorageService storage, List<DersBildirimi> list) async {
    await storage.saveSettings({_key: list.map((e) => e.toJson()).toList()});
  }
}

/// Alarm ÇAKIŞMA yardımcısı (kullanıcı isteği): aynı gün + aynı saat + aynı
/// dakikaya iki alarm kurulamaz. Kural HEM ders bildirimleri HEM de çalışma
/// planı başlangıç saatleri için ORTAK geçerlidir; çakışırsa 1'er dakika ileri
/// kaydırılıp ilk boş dakika bulunur.
class AlarmCakisma {
  const AlarmCakisma._();

  /// [gun]'e ait DOLU alarm dakikaları: çalışma planı BAŞLANGIÇLARI + ders
  /// bildirimleri. Düzenlenen kaydı hariç tutmak için [haricPlanId] /
  /// [haricDersId] verilebilir.
  static Set<int> doluDakikalar(
    StorageService storage,
    int gun, {
    String? haricPlanId,
    String? haricDersId,
  }) {
    final set = <int>{};
    for (final e in StudyPlanService(storage).getPlan()) {
      if (e.id == haricPlanId) continue;
      if (e.gun == gun) set.add(e.baslangicDakikaToplam);
    }
    for (final e in DersBildirimService().getir(storage)) {
      if (e.id == haricDersId) continue;
      if (e.gun == gun) set.add(e.dakikaToplam);
    }
    return set;
  }

  /// (gün, saat, dakika) DOLU ise 1'er dakika ileri kaydırıp İLK BOŞ dakikayı
  /// döndürür. `kaydirildi` true ise çakışma nedeniyle saat değişmiştir.
  /// `adim` kaç dakika ileri alındığını verir (bitiş saatini de kaydırmak için).
  static ({int saat, int dakika, bool kaydirildi, int adim}) bosDakika(
    StorageService storage,
    int gun,
    int saat,
    int dakika, {
    String? haricPlanId,
    String? haricDersId,
  }) {
    final dolu = doluDakikalar(storage, gun,
        haricPlanId: haricPlanId, haricDersId: haricDersId);
    final baslangic = saat * 60 + dakika;
    var toplam = baslangic;
    var guvenlik = 0;
    while (dolu.contains(toplam) && guvenlik < 1440) {
      toplam = (toplam + 1) % 1440;
      guvenlik++;
    }
    final adim = (toplam - baslangic + 1440) % 1440;
    return (
      saat: toplam ~/ 60,
      dakika: toplam % 60,
      kaydirildi: adim != 0,
      adim: adim,
    );
  }
}
