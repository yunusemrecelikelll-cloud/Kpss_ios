import 'dart:math';
import 'dart:ui' show Color;
import '../data/kategori_eslestirme_data.dart';
import '../models/subject.dart';

/// ─────────────────────────── ORTAK RENK PALETİ ───────────────────────────
/// Her iki kart oyununda (v1 + V2) EŞLEŞEN ÇİFTLERİ birbirinden ayırmak için
/// kullanılır: 1. çift yeşil, 2. çift mor, 3. çift turuncu... şeklinde sırayla
/// dağıtılır. Renkler orta doygunlukta seçildi; kart zemininde düşük alfa ile
/// (kenarlık + ok tam renkle) kullanıldığından hem koyu hem açık temada metin
/// kontrastı korunur.
const List<Color> kCiftRenkleri = [
  Color(0xFF2E9E5B), // yeşil
  Color(0xFF7C4DFF), // mor
  Color(0xFFF57C00), // turuncu
  Color(0xFF1E88E5), // mavi
  Color(0xFFE91E63), // pembe
  Color(0xFF00897B), // turkuaz
  Color(0xFFC9A227), // amber
  Color(0xFF3F51B5), // indigo
  Color(0xFFD84315), // kiremit
  Color(0xFF558B2F), // zeytin
];

/// Yanlış eşleşmede kartların geçici olarak aldığı renk.
const Color kYanlisRengi = Color(0xFFE53935);

/// Çift sırasına göre paletten renk seçer (palet biterse başa döner).
Color ciftRengi(int index) => kCiftRenkleri[index.abs() % kCiftRenkleri.length];

/// Kart Eşleştirme Oyunu (v1) — JS: src/js/cardgame.js `CardGame`.
/// Kapalı kartlar, hafıza/eşleştirme oyunu. Tüm derslerin konu anlatımlarındaki
/// "Terim: Tanım" biçimindeki anahtar noktalarından rastgele bir kart havuzu kurar.
class MatchCard {
  final int pairId;
  final String type; // 'term' | 'def'
  final String text;
  bool matched;

  MatchCard({required this.pairId, required this.type, required this.text, this.matched = false});
}

class CardFlipResult {
  final String status; // 'ignored' | 'flipped' | 'match' | 'pending-nomatch'
  const CardFlipResult(this.status);
}

class _TermDef {
  final String term;
  final String def;
  const _TermDef(this.term, this.def);
}

class CardGameEngine {
  final _rng = Random();

  List<MatchCard> cards = [];
  List<int> flipped = [];
  int moves = 0;
  int matchedCount = 0;

  String _stripLeadingEmoji(String s) {
    // JS: s.replace(/^[^\p{L}\p{N}]+/u, '').trim()
    final re = RegExp(r'^[^\p{L}\p{N}]+', unicode: true);
    return s.replaceFirst(re, '').trim();
  }

  /// Kartlara sığması ve akılda kalıcı olması için kabul edilen en uzun metin
  /// sınırları — bunlardan uzun "Terim: Tanım" satırları havuza alınmaz.
  static const int _maxTerimUzunluk = 24;
  static const int _maxTanimUzunluk = 28;

  List<_TermDef> _buildPairs(List<Subject> subjects, int count) {
    // 1) Elle hazırlanmış KISA çiftler (Tarih dâhil tüm konular) — asıl havuz.
    final pool = <_TermDef>[
      for (final c in kTumKisaEslestirmeler) _TermDef(c.sol, c.sag),
    ];

    // 2) Ders içeriklerinden gelen "Terim: Tanım" satırları — yalnızca yeterince
    //    KISA olanlar eklenir ki kart üzerinde uzun cümle görünmesin.
    for (final s in subjects) {
      for (final t in s.konular) {
        for (final raw in t.anlatim.anahtarNoktalar) {
          final clean = _stripLeadingEmoji(raw);
          final idx = clean.indexOf(':');
          if (idx > 3 && idx < clean.length - 3) {
            final term = clean.substring(0, idx).trim();
            final def = clean.substring(idx + 1).trim();
            if (term.isEmpty || def.isEmpty) continue;
            if (term.length > _maxTerimUzunluk || def.length > _maxTanimUzunluk) continue;
            pool.add(_TermDef(term, def));
          }
        }
      }
    }

    final shuffled = List<_TermDef>.of(pool)..shuffle(_rng);
    final picked = <_TermDef>[];
    // Aynı metin iki kartta görünürse oyun belirsizleşir: hem terim hem tanım
    // tarafında tekrarları eliyoruz.
    final gorulen = <String>{};
    for (final p in shuffled) {
      if (gorulen.contains(p.term) || gorulen.contains(p.def)) continue;
      gorulen.add(p.term);
      gorulen.add(p.def);
      picked.add(p);
      if (picked.length >= count) break;
    }
    return picked;
  }

  void start(List<Subject> subjects, {int pairCount = 6}) {
    final pairs = _buildPairs(subjects, pairCount);
    final newCards = <MatchCard>[];
    for (var i = 0; i < pairs.length; i++) {
      newCards.add(MatchCard(pairId: i, type: 'term', text: pairs[i].term));
      newCards.add(MatchCard(pairId: i, type: 'def', text: pairs[i].def));
    }
    newCards.shuffle(_rng);
    cards = newCards;
    flipped = [];
    moves = 0;
    matchedCount = 0;
  }

  CardFlipResult flip(int cardIndex) {
    if (cardIndex < 0 || cardIndex >= cards.length) return const CardFlipResult('ignored');
    final card = cards[cardIndex];
    if (card.matched || flipped.contains(cardIndex) || flipped.length >= 2) {
      return const CardFlipResult('ignored');
    }
    flipped.add(cardIndex);
    if (flipped.length == 2) {
      moves++;
      final i1 = flipped[0], i2 = flipped[1];
      final c1 = cards[i1], c2 = cards[i2];
      if (c1.pairId == c2.pairId && c1.type != c2.type) {
        c1.matched = true;
        c2.matched = true;
        matchedCount++;
        flipped = [];
        return const CardFlipResult('match');
      }
      return const CardFlipResult('pending-nomatch');
    }
    return const CardFlipResult('flipped');
  }

  void clearPending() => flipped = [];

  bool get isComplete => cards.isNotEmpty && matchedCount == cards.length ~/ 2;
}
