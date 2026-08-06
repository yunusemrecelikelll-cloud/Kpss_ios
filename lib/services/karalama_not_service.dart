import 'dart:math';

import 'storage_service.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Karalama Notları — veri katmanı (kullanıcı isteği)
/// ─────────────────────────────────────────────────────────────────────────
///
/// Testlerdeki KARALAMA katmanında (bkz. widgets/karalama_katmani.dart)
/// kullanıcının yazdığı/karaladığı içerik "Kaydet" ile burada saklanır ve
/// anasayfadaki "Notlar" bölümünde (önizlemeli) listelenir.
///
/// Depolama: Çalışma planı/ders bildirimleriyle aynı desen —
/// `settings['karalamaNotlari']` altında JSON listesi.

/// Tek bir çizgi: renk + kalınlık + düz [x0,y0,x1,y1,...] nokta dizisi
/// (kaydı küçük tutmak için noktalar flat double listesi olarak saklanır).
class KaralamaCizgi {
  final int renk; // ARGB
  final double kalinlik;
  final List<double> noktalar;

  const KaralamaCizgi(
      {required this.renk, required this.kalinlik, required this.noktalar});

  Map<String, dynamic> toJson() =>
      {'c': renk, 'k': kalinlik, 'p': noktalar};

  static KaralamaCizgi? fromJson(Map<String, dynamic> j) {
    try {
      final p = (j['p'] as List? ?? const [])
          .map((e) => (e as num).toDouble())
          .toList();
      if (p.length < 2) return null;
      return KaralamaCizgi(
        renk: (j['c'] as num?)?.toInt() ?? 0xFF000000,
        kalinlik: (j['k'] as num?)?.toDouble() ?? 3,
        noktalar: p,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Kaydedilmiş tek bir karalama notu: yazı + çizim + oluşturma anındaki tuval
/// boyutu (önizlemeyi orantılı ölçekleyebilmek için).
class KaralamaNot {
  final String id;
  final String metin;
  final int metinRenk; // ARGB
  final List<KaralamaCizgi> cizgiler;
  final double w;
  final double h;
  final int createdAt; // ms epoch

  const KaralamaNot({
    required this.id,
    required this.metin,
    required this.metinRenk,
    required this.cizgiler,
    required this.w,
    required this.h,
    required this.createdAt,
  });

  static final Random _rnd = Random();
  static String yeniId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_rnd.nextInt(1 << 20).toRadixString(36)}';

  bool get cizimVar => cizgiler.isNotEmpty;
  bool get metinVar => metin.trim().isNotEmpty;
  bool get bos => !cizimVar && !metinVar;

  /// Kısa başlık: yazının ilk satırı; yoksa "Karalama".
  String get baslik {
    final ilk = metin.trim().split('\n').first.trim();
    if (ilk.isNotEmpty) return ilk.length > 40 ? '${ilk.substring(0, 40)}…' : ilk;
    return cizimVar ? 'Karalama çizimi' : 'Boş not';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'metin': metin,
        'mr': metinRenk,
        'w': w,
        'h': h,
        't': createdAt,
        'ciz': cizgiler.map((e) => e.toJson()).toList(),
      };

  static KaralamaNot? fromJson(Map<String, dynamic> j) {
    try {
      final ciz = (j['ciz'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => KaralamaCizgi.fromJson(Map<String, dynamic>.from(m)))
          .whereType<KaralamaCizgi>()
          .toList();
      return KaralamaNot(
        id: (j['id'] as String?)?.trim().isNotEmpty == true
            ? j['id'] as String
            : yeniId(),
        metin: j['metin'] as String? ?? '',
        metinRenk: (j['mr'] as num?)?.toInt() ?? 0xFF241C33,
        cizgiler: ciz,
        w: (j['w'] as num?)?.toDouble() ?? 300,
        h: (j['h'] as num?)?.toDouble() ?? 200,
        createdAt: (j['t'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

class KaralamaNotService {
  static const String _key = 'karalamaNotlari';

  /// Aşırı büyümeyi önlemek için tutulan en fazla not sayısı.
  static const int _maxNot = 60;

  /// En yeni önce sıralı kayıtlı notlar.
  List<KaralamaNot> getir(StorageService storage) {
    final raw = storage.getSettings()[_key];
    if (raw is! List) return [];
    final list = raw
        .whereType<Map>()
        .map((m) => KaralamaNot.fromJson(Map<String, dynamic>.from(m)))
        .whereType<KaralamaNot>()
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> ekle(StorageService storage, KaralamaNot not) async {
    final list = getir(storage);
    list.insert(0, not);
    final kirpik = list.take(_maxNot).toList();
    await storage.saveSettings({_key: kirpik.map((e) => e.toJson()).toList()});
  }

  Future<void> sil(StorageService storage, String id) async {
    final list = getir(storage).where((n) => n.id != id).toList();
    await storage.saveSettings({_key: list.map((e) => e.toJson()).toList()});
  }
}
