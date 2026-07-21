import 'dart:math';
import '../data/kategori_eslestirme_data.dart';
import '../models/subject.dart';
import '../models/topic.dart';

/// Kart Oyunu V2 — JS: src/js/cardgame.js `CardGameV2`.
/// Açık kartlar, 2 sütun (sol terim / sağ tanım), tek bir konuya özel.
class Match2Card {
  final int pairId;
  final String text;

  /// Çiftin palet sırası — eşleşen iki kart AYNI, farklı çiftler FARKLI renk alır.
  final int renkIndex;
  bool matched;
  Match2Card({
    required this.pairId,
    required this.text,
    required this.renkIndex,
    this.matched = false,
  });
}

class WrongPair {
  final int leftIdx;
  final int rightIdx;
  const WrongPair(this.leftIdx, this.rightIdx);
}

class Match2Result {
  final String status; // 'ignored' | 'partial' | 'match' | 'nomatch'
  final int? leftIdx;
  final int? rightIdx;
  const Match2Result(this.status, {this.leftIdx, this.rightIdx});
}

class PairTermDef {
  final int pairId;
  final String term;
  final String def;
  const PairTermDef({required this.pairId, required this.term, required this.def});
}

/// ── Ders havuzu ────────────────────────────────────────────────────────────
///
/// Kart Oyunu V2 artık TEK bir konuya değil, oyuncunun SEÇTİĞİ DERSLERİN tüm
/// konularından toplanan ortak bir çift havuzuna dayanır. Her çift hangi
/// ders/konudan geldiğini taşır; ders kartlarındaki ilerleme yüzdesi ve
/// "geçilen konu" kaydı bu bilgiden hesaplanır.
class HavuzCifti {
  final String dersId;
  final String konuId;
  final String sol;
  final String sag;
  const HavuzCifti({
    required this.dersId,
    required this.konuId,
    required this.sol,
    required this.sag,
  });

  /// Çiftin KALICI kimliği — kullanılmış çift takibi bu anahtarla saklanır,
  /// böylece uygulama kapanıp açılsa da aynı çift yakın turlarda tekrar gelmez.
  String get anahtar => '$sol|$sag';
}

/// Bir turluk çekimin sonucu.
///
/// [ciftler] o turda oynanacak çiftler (normalde tam 8),
/// [kullanilan] güncellenmiş "ders id → kullanılmış çift anahtarları" haritası,
/// [sifirlanan] ise havuzu tükendiği için takibi sıfırlanan (yüzdesi %0'a
/// dönen) derslerin id'leridir.
class HavuzCekimi {
  final List<HavuzCifti> ciftler;
  final Map<String, Set<String>> kullanilan;
  final Set<String> sifirlanan;
  const HavuzCekimi({
    required this.ciftler,
    required this.kullanilan,
    required this.sifirlanan,
  });
}

class CardGameV2Engine {
  final _rng = Random();

  List<Match2Card> left = [];
  List<Match2Card> right = [];
  int? selectedLeft;
  int? selectedRight;
  int mistakes = 0;
  int maxMistakes = 3;
  int pairsTotal = 0;
  int matchedCount = 0;
  WrongPair? lastWrong;

  static String _stripLeadingEmoji(String s) {
    final re = RegExp(r'^[^\p{L}\p{N}]+', unicode: true);
    return s.replaceFirst(re, '').trim();
  }

  /// Bir tahtada en fazla kaç çift gösterilir (kartların ekrana eşit boyda
  /// sığması için üst sınır).
  static const int maxCiftSayisi = 8;

  /// Her oyunda gösterilen SABİT çift sayısı — zorluk/ders fark etmeksizin
  /// tahtada her zaman tam bu kadar eşleştirme bulunur.
  static const int kSabitCiftSayisi = 8;

  /// Ders havuzları konu JSON'larından türetildiği için pahalıdır; ders id'sine
  /// göre bir kez hesaplanıp saklanır.
  static final Map<String, List<HavuzCifti>> _dersHavuzCache = {};

  /// Kart metinlerinin okunaklı kalması için uzunluk sınırları — konu
  /// JSON'undan gelen uzun cümleler oyuna alınmaz.
  static const int _maxTerimUzunluk = 30;
  static const int _maxTanimUzunluk = 42;

  /// JS: CardGameV2.buildPairsForTopic
  ///
  /// Önce [kKonuEslestirmeleri] içindeki ELLE HAZIRLANMIŞ kısa çiftler alınır
  /// (birçok konuda — özellikle Tarih'te — konu metninden hiç çift üretilemiyor),
  /// ardından konu içeriğinden çıkarılan kısa "Terim: Tanım" satırları eklenir.
  /// Aynı metin iki kartta görünmesin diye hem terim hem tanım tarafında tekrar
  /// elenir; sonuç [maxCiftSayisi] ile sınırlanır.
  /// [limit] varsayılan olarak tahtaya sığan çift sayısıdır; ders havuzu
  /// kurulurken konudaki TÜM çiftler istendiğinden çok büyük verilir.
  static List<PairTermDef> buildPairsForTopic(Topic topic, {int limit = maxCiftSayisi}) {
    final pairs = <PairTermDef>[];
    final gorulen = <String>{};
    var sira = 0;

    void ekle(String term, String def) {
      if (term.isEmpty || def.isEmpty) return;
      if (gorulen.contains(term) || gorulen.contains(def)) return;
      gorulen.add(term);
      gorulen.add(def);
      pairs.add(PairTermDef(pairId: sira, term: term, def: def));
      sira++;
    }

    for (final c in kKonuEslestirmeleri[topic.id] ?? const <EslestirmeCifti>[]) {
      if (pairs.length >= limit) return pairs;
      ekle(c.sol, c.sag);
    }

    final pts = topic.anlatim.anahtarNoktalar;
    for (var i = 0; i < pts.length; i++) {
      if (pairs.length >= limit) break;
      final clean = _stripLeadingEmoji(pts[i]);
      final idx = clean.indexOf(':');
      if (idx > 3 && idx < clean.length - 3) {
        final term = clean.substring(0, idx).trim();
        final def = clean.substring(idx + 1).trim();
        if (term.length > _maxTerimUzunluk || def.length > _maxTanimUzunluk) continue;
        ekle(term, def);
      }
    }
    return pairs;
  }

  /// Bir dersin TÜM konularından toplanmış eşleştirme havuzu.
  ///
  /// Aynı metin iki farklı kartta görünmesin diye ders genelinde hem terim hem
  /// tanım tarafında tekrar elenir.
  static List<HavuzCifti> dersHavuzu(Subject ders) {
    final hazir = _dersHavuzCache[ders.id];
    if (hazir != null) return hazir;

    final havuz = <HavuzCifti>[];
    final gorulen = <String>{};
    for (final konu in ders.konular) {
      for (final c in buildPairsForTopic(konu, limit: 1 << 20)) {
        if (gorulen.contains(c.term) || gorulen.contains(c.def)) continue;
        gorulen.add(c.term);
        gorulen.add(c.def);
        havuz.add(HavuzCifti(dersId: ders.id, konuId: konu.id, sol: c.term, sag: c.def));
      }
    }
    _dersHavuzCache[ders.id] = havuz;
    return havuz;
  }

  /// Ders kartında gösterilen ilerleme (0→1): o dersin havuzunun ne kadarı
  /// kullanıldı? Havuz tamamen tükendiğinde 1.0 (%100), takip sıfırlandığında
  /// tekrar 0.0 olur. Havuz değişse bile eski/geçersiz anahtarların yüzdeyi
  /// şişirmemesi için kesişim alınır.
  static double dersIlerlemesi(Subject ders, Set<String>? kullanilan) {
    final havuz = dersHavuzu(ders);
    if (havuz.isEmpty || kullanilan == null || kullanilan.isEmpty) return 0;
    final anahtarlar = {for (final c in havuz) c.anahtar};
    final sayi = kullanilan.where(anahtarlar.contains).length;
    return (sayi / havuz.length).clamp(0.0, 1.0);
  }

  /// Seçilen derslerin havuzundan bir turluk (varsayılan 8) çift çeker.
  ///
  /// Kural: önce HENÜZ KULLANILMAMIŞ çiftler karıştırılıp alınır; bir dersin
  /// kullanılmamış çifti kalmadıysa o dersin takibi sıfırlanır ve havuzu
  /// yeniden karıştırılarak baştan verilir. Böylece oyun hiç bitmez ama yakın
  /// turlarda aynı çiftler tekrar etmez.
  static HavuzCekimi cek({
    required List<Subject> dersler,
    required Map<String, Set<String>> kullanilan,
    int adet = kSabitCiftSayisi,
    Random? rng,
  }) {
    final r = rng ?? Random();
    final takip = {for (final e in kullanilan.entries) e.key: <String>{...e.value}};
    final sifirlanan = <String>{};
    final taze = <HavuzCifti>[]; // hiç kullanılmamış çiftler
    final tumu = <HavuzCifti>[]; // seçili derslerin tüm çiftleri (dolgu için)

    for (final ders in dersler) {
      final havuz = dersHavuzu(ders);
      if (havuz.isEmpty) continue;
      tumu.addAll(havuz);

      var used = takip[ders.id] ?? <String>{};
      var kalan = havuz.where((c) => !used.contains(c.anahtar)).toList();
      if (kalan.isEmpty) {
        // Havuz tükendi → takibi sıfırla, yüzde %0'a dönsün, havuzu baştan ver.
        takip[ders.id] = <String>{};
        sifirlanan.add(ders.id);
        kalan = [...havuz];
      }
      taze.addAll(kalan);
    }

    taze.shuffle(r);
    final secilen = taze.take(adet).toList();
    for (final c in secilen) {
      (takip[c.dersId] ??= <String>{}).add(c.anahtar);
    }

    // Seçili derslerin toplam havuzu 8'den küçükse tahtayı yine de 8'e
    // tamamlamak için kullanılmış çiftlerden dolgu yapılır; dolgu çiftleri
    // yüzdeyi etkilemez (zaten kullanılmış sayılıyorlar).
    if (secilen.length < adet) {
      final metinler = <String>{for (final c in secilen) ...[c.sol, c.sag]};
      final dolgu = tumu.where((c) => !metinler.contains(c.sol) && !metinler.contains(c.sag)).toList()
        ..shuffle(r);
      for (final c in dolgu) {
        if (secilen.length >= adet) break;
        if (metinler.contains(c.sol) || metinler.contains(c.sag)) continue;
        metinler.add(c.sol);
        metinler.add(c.sag);
        secilen.add(c);
      }
    }

    secilen.shuffle(r);
    return HavuzCekimi(ciftler: secilen, kullanilan: takip, sifirlanan: sifirlanan);
  }

  /// Havuzdan çekilmiş çiftlerle tahtayı kurar (Kart Oyunu V2'nin asıl girişi).
  void startCiftlerle(List<HavuzCifti> ciftler, {int maxMistakes = 3}) {
    // renkIndex = çiftin sırası; sol ve sağ kart aynı rengi paylaşır.
    left = [
      for (var i = 0; i < ciftler.length; i++)
        Match2Card(pairId: i, text: ciftler[i].sol, renkIndex: i)
    ]..shuffle(_rng);
    right = [
      for (var i = 0; i < ciftler.length; i++)
        Match2Card(pairId: i, text: ciftler[i].sag, renkIndex: i)
    ]..shuffle(_rng);
    selectedLeft = null;
    selectedRight = null;
    mistakes = 0;
    this.maxMistakes = maxMistakes;
    pairsTotal = ciftler.length;
    matchedCount = 0;
    lastWrong = null;
  }

  void start(Topic topic, {int maxMistakes = 3}) {
    final pairs = buildPairsForTopic(topic);
    // renkIndex = çiftin sırası; sol ve sağ kart aynı rengi paylaşır.
    left = [
      for (var i = 0; i < pairs.length; i++)
        Match2Card(pairId: pairs[i].pairId, text: pairs[i].term, renkIndex: i)
    ]..shuffle(_rng);
    right = [
      for (var i = 0; i < pairs.length; i++)
        Match2Card(pairId: pairs[i].pairId, text: pairs[i].def, renkIndex: i)
    ]..shuffle(_rng);
    selectedLeft = null;
    selectedRight = null;
    mistakes = 0;
    this.maxMistakes = maxMistakes;
    pairsTotal = pairs.length;
    matchedCount = 0;
    lastWrong = null;
  }

  Match2Result _tryResolve() {
    if (selectedLeft == null || selectedRight == null) return const Match2Result('partial');
    final li = selectedLeft!, ri = selectedRight!;
    final l = left[li], r = right[ri];
    if (l.pairId == r.pairId) {
      l.matched = true;
      r.matched = true;
      matchedCount++;
      selectedLeft = null;
      selectedRight = null;
      return Match2Result('match', leftIdx: li, rightIdx: ri);
    }
    mistakes++;
    lastWrong = WrongPair(li, ri);
    selectedLeft = null;
    selectedRight = null;
    return Match2Result('nomatch', leftIdx: li, rightIdx: ri);
  }

  Match2Result selectLeft(int i) {
    if (i < 0 || i >= left.length || left[i].matched) return const Match2Result('ignored');
    selectedLeft = i;
    lastWrong = null;
    return _tryResolve();
  }

  Match2Result selectRight(int i) {
    if (i < 0 || i >= right.length || right[i].matched) return const Match2Result('ignored');
    selectedRight = i;
    lastWrong = null;
    return _tryResolve();
  }

  void clearLastWrong() => lastWrong = null;

  bool get isComplete => pairsTotal > 0 && matchedCount == pairsTotal;
  bool get isFailed => mistakes >= maxMistakes;
}
