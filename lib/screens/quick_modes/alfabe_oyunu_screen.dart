import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/alfabe_sorulari.dart';
import '../../services/sound_service.dart';
import '../../services/ad_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/design_system.dart';
import '../../theme/theme_provider.dart';
import '../tools_hub_screen.dart';

/// Mini oyun — "KPSS Tarih Alfabetik" (yazmalı sürüm).
/// A'dan Z'ye her harf için, cevabı o harfle başlayan bir soru sorulur.
/// Kullanıcı cevabı KLAVYE ile YAZAR (şık yok). Cevap %100 birebir değil,
/// ~%70 benzerlik/anahtar-kelime ile geçerli sayılır (ör. "Ertuğrul Gazi"
/// için "ertuğrul", "eryurul" da kabul). İpucu istedikçe o sorudan alınacak
/// puan düşer. Pas yok; önceki/sonraki sorulara serbestçe geçilebilir.
///
/// Soru metni, üstteki alfabe çemberinin İÇİNDE tatlı renkli, gerekiyorsa
/// dikey kaydırılabilen bir kartta gösterilir; oyun ekranı tek ekrana sığar.
const String kAlfabeOyunuGameId = 'alfabe-oyunu';

/// Doğru cevaptan sonra sonraki soruya otomatik geçişten önce beklenen süre.
const Duration kAlfabeGecisSuresi = Duration(milliseconds: 650);

/// Bir sorunun ipuçsuz tam puanı ve her ipucunun puan düşüşü.
const int kAlfabeTamPuan = 10;
const int kAlfabeIpucuDusus = 2;
const int kAlfabeMinPuan = 2;

/// Türk alfabesi sıralaması — çemberdeki harfleri doğru sırada dizmek için.
const List<String> _kTurkAlfabe = [
  'A', 'B', 'C', 'Ç', 'D', 'E', 'F', 'G', 'Ğ', 'H', 'I', 'İ', 'J', 'K', 'L',
  'M', 'N', 'O', 'Ö', 'P', 'R', 'S', 'Ş', 'T', 'U', 'Ü', 'V', 'Y', 'Z',
];

int _harfSira(String h) {
  final i = _kTurkAlfabe.indexOf(h);
  return i < 0 ? 999 : i;
}

/// Türkçe harfleri ASCII'ye indirger, küçük harfe çevirir, noktalama atar.
/// "Ertuğrul Gazi" → "ertugrul gazi"; "Mustafa Kemal ATATÜRK" → "mustafa
/// kemal ataturk". Böylece ğ/g, ı/i farkları ve büyük/küçük harf takılmaz.
String _sadelestir(String s) {
  const harita = {
    'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u',
    'â': 'a', 'î': 'i', 'û': 'u', 'ê': 'e', 'ô': 'o',
    'Ç': 'c', 'Ğ': 'g', 'I': 'i', 'İ': 'i', 'Ö': 'o', 'Ş': 's', 'Ü': 'u',
    'Â': 'a', 'Î': 'i', 'Û': 'u',
  };
  final sb = StringBuffer();
  for (final ch in s.trim().split('')) {
    sb.write(harita[ch] ?? ch.toLowerCase());
  }
  return sb
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// İki dizge arasındaki Levenshtein düzenleme uzaklığı.
int _duzenlemeUzakligi(String a, String b) {
  final m = a.length, n = b.length;
  if (m == 0) return n;
  if (n == 0) return m;
  var onceki = List<int>.generate(n + 1, (i) => i);
  var simdi = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= m; i++) {
    simdi[0] = i;
    for (var j = 1; j <= n; j++) {
      final maliyet = a[i - 1] == b[j - 1] ? 0 : 1;
      simdi[j] = min(min(simdi[j - 1] + 1, onceki[j] + 1), onceki[j - 1] + maliyet);
    }
    final t = onceki;
    onceki = simdi;
    simdi = t;
  }
  return onceki[n];
}

/// 0..1 benzerlik oranı (1 = birebir).
double _benzerlik(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  final enUzun = max(a.length, b.length);
  if (enUzun == 0) return 1;
  return 1 - _duzenlemeUzakligi(a, b) / enUzun;
}

/// Kullanıcının yazdığı cevap "yeterince doğru" mu? (~%70 tolerans + anahtar
/// kelime kabulü — çok kelimeli cevapta ayırt edici tek kelime de geçerli.)
bool _cevapGecerli(String girilen, String dogru) {
  final g = _sadelestir(girilen);
  final d = _sadelestir(dogru);
  if (g.isEmpty) return false;
  if (g == d) return true;
  if (_benzerlik(g, d) >= 0.7) return true;
  // Cevabın ayırt edici (>=4 harf) bir kelimesini yazdıysa kabul.
  final dKelime = d.split(' ').where((w) => w.length >= 4).toList();
  for (final w in dKelime) {
    if (_benzerlik(g, w) >= 0.7) return true;
  }
  // Kullanıcı birden çok kelime yazdıysa: cevabın kelimelerinin %70'ini tuttur.
  final gKelime = g.split(' ').where((w) => w.length >= 3).toList();
  if (dKelime.isNotEmpty && gKelime.isNotEmpty) {
    var isabet = 0;
    for (final w in dKelime) {
      if (gKelime.any((x) => _benzerlik(x, w) >= 0.7)) isabet++;
    }
    if (isabet / dKelime.length >= 0.7) return true;
  }
  return false;
}

/// Bir sorunun doğru cevap metni (şık harfi → metin).
String _dogruCevapMetni(AlfabeSorusu s) => s.siklar[s.dogru] ?? '';

/// Cevaptan kademeli ipuçları üretir (her biri istenince puan düşürür).
List<String> _ipuclariUret(AlfabeSorusu s) {
  final cevap = _dogruCevapMetni(s).trim();
  final kelimeler = cevap.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final harfSayisi = cevap.replaceAll(' ', '').length;
  final maskeli = kelimeler
      .map((w) => w.length <= 1 ? w : '${w[0]}${'_' * (w.length - 1)}')
      .join('  ');
  return [
    'Cevap "${s.harf}" harfi ile başlıyor.',
    '${kelimeler.length} kelime · $harfSayisi harf.',
    'Şablon:  $maskeli',
    if (kelimeler.isNotEmpty) 'İlk kelime: ${kelimeler.first}',
  ];
}

/// Oyun kartına basınca AÇILAN tanıtım/başlangıç ekranı; rekor puanı gösterir.
class AlfabeOyunuTanitimScreen extends StatelessWidget {
  const AlfabeOyunuTanitimScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final storage = context.watch<StorageService>();
    final premium = storage.isPremiumUser();
    final rekorPuan = storage.getHighScore(kAlfabeOyunuGameId);
    final son = storage.getLastRoundStats(kAlfabeOyunuGameId);
    final gp = storage.getGamePlayState(kAlfabeOyunuGameId);
    final kalan = (kFreeGameDailyLimit +
            storage.getExtraPlays(kAlfabeOyunuGameId) -
            (gp['plays'] as int))
        .clamp(0, 99);

    return Scaffold(
      appBar: AppBar(title: const Text('🔤 Alfabe Oyunu')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          children: [
            Center(child: DsIllustration(emoji: '🔤', size: 88, glowColor: c.violet)),
            const SizedBox(height: 12),
            Text('KPSS Tarih Alfabet',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c.text)),
            const SizedBox(height: 6),
            Text(
              "A'dan Z'ye her harf için, cevabı o harfle başlayan bir tarih "
              'sorusu gelir. Cevabı KLAVYE ile yaz — şık yok! Emin değilsen '
              'ipucu iste (ama her ipucu puanını düşürür). Yakın/eksik yazımlar '
              'da geçerli sayılır. Her oyunda farklı sorular gelir.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: c.textDim),
            ),
            const SizedBox(height: 18),
            DsCard(
              accent: c.violet,
              child: Row(
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Rekor puan',
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w800, color: c.text)),
                  ),
                  Text(
                    '$rekorPuan',
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900, color: c.violet),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            DsStatStrip(
              items: [
                DsStatItem(
                  visual: Text('${son['correct'] ?? 0}',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c.success)),
                  value: '',
                  label: '✅ Doğru',
                ),
                DsStatItem(
                  visual: Text('${son['wrong'] ?? 0}',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c.danger)),
                  value: '',
                  label: '❌ Boş/Yanlış',
                ),
                DsStatItem(
                  visual: Text('$rekorPuan',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c.gold)),
                  value: '',
                  label: '🎯 Rekor puan',
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (!premium)
              Center(
                child: DsChip(
                    label: kalan > 0 ? 'Bugün $kalan hak' : 'Bugünkü hakkın bitti',
                    color: kalan > 0 ? c.violet : c.warn),
              )
            else
              Center(child: DsChip(label: 'Premium • Sınırsız', color: c.gold)),
            const SizedBox(height: 16),
            DsPillButton(
              label: 'Oyna',
              leadingIcon: Icons.play_arrow_rounded,
              color: c.violet,
              onPressed: () {
                context.read<SoundService>().click();
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AlfabeOyunuScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class AlfabeOyunuScreen extends StatefulWidget {
  const AlfabeOyunuScreen({super.key});

  @override
  State<AlfabeOyunuScreen> createState() => _AlfabeOyunuScreenState();
}

class _AlfabeOyunuScreenState extends State<AlfabeOyunuScreen> {
  final Random _rnd = Random();
  final TextEditingController _controller = TextEditingController();

  bool _locked = false;
  bool _booted = false;
  bool _finished = false;

  /// Bu turda oynanan harfler, Türk alfabesi sırasında.
  final List<String> _harfler = [];

  /// Her harf için seçilmiş soru.
  final Map<String, AlfabeSorusu> _soru = {};

  /// Harf durumu: 'bekliyor' | 'dogru'.
  final Map<String, String> _durum = {};

  /// Harf başına açılan ipucu sayısı.
  final Map<String, int> _ipucu = {};

  /// Harf başına kazanılan puan (doğru bilindiğinde yazılır).
  final Map<String, int> _puan = {};

  /// Harf başına kullanıcının son yazdığı metin (gezinince korunur).
  final Map<String, String> _yazilan = {};

  int _aktifIndex = 0;
  int _dogruSayi = 0;
  bool _yanlisTitre = false; // yanlış cevapta kısa kırmızı geri bildirim

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final storage = context.read<StorageService>();
    final premium = storage.isPremiumUser();
    if (!premium) {
      final gp = storage.getGamePlayState(kAlfabeOyunuGameId);
      if ((gp['plays'] as int) >=
          kFreeGameDailyLimit + storage.getExtraPlays(kAlfabeOyunuGameId)) {
        if (!mounted) return;
        setState(() => _locked = true);
        return;
      }
      await storage.useGamePlay(kAlfabeOyunuGameId);
    }
    if (!mounted) return;

    // Harf başına soruları grupla; her açılışta harf başına RASTGELE bir soru
    // seç (her giriş farklı sorular gelsin).
    final byLetter = <String, List<AlfabeSorusu>>{};
    for (final q in kAlfabeSorulari) {
      byLetter.putIfAbsent(q.harf, () => []).add(q);
    }
    final harfler = byLetter.keys.toList()
      ..sort((a, b) => _harfSira(a).compareTo(_harfSira(b)));

    _harfler
      ..clear()
      ..addAll(harfler);
    _soru.clear();
    _durum.clear();
    _ipucu.clear();
    _puan.clear();
    _yazilan.clear();
    for (final h in harfler) {
      final liste = byLetter[h]!;
      _soru[h] = liste[_rnd.nextInt(liste.length)];
      _durum[h] = 'bekliyor';
      _ipucu[h] = 0;
    }

    setState(() {
      _aktifIndex = 0;
      _dogruSayi = 0;
      _finished = false;
      _yanlisTitre = false;
      _booted = true;
    });
    _controller.text = '';
  }

  String get _aktifHarf => _harfler[_aktifIndex];
  AlfabeSorusu get _aktifSoru => _soru[_aktifHarf]!;

  /// Aktif sorudan şu an alınabilecek puan (ipucu başına düşer).
  int _guncelPuan(String harf) =>
      max(kAlfabeMinPuan, kAlfabeTamPuan - kAlfabeIpucuDusus * (_ipucu[harf] ?? 0));

  int get _toplamPuan =>
      _puan.values.fold(0, (a, b) => a + b);

  void _gezin(int yon) {
    final yeni = (_aktifIndex + yon).clamp(0, _harfler.length - 1);
    if (yeni == _aktifIndex) return;
    context.read<SoundService>().click();
    setState(() {
      _aktifIndex = yeni;
      _yanlisTitre = false;
    });
    final h = _aktifHarf;
    _controller.text = _durum[h] == 'dogru' ? '' : (_yazilan[h] ?? '');
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
  }

  void _sonrakiBekleyene() {
    // Aktiften sonra ilk 'bekliyor' harfe geç; yoksa başa dön ve ara; yoksa bitir.
    for (var off = 1; off <= _harfler.length; off++) {
      final i = (_aktifIndex + off) % _harfler.length;
      if (_durum[_harfler[i]] == 'bekliyor') {
        setState(() {
          _aktifIndex = i;
          _yanlisTitre = false;
        });
        _controller.text = '';
        return;
      }
    }
    _finish();
  }

  void _cevapla() {
    final h = _aktifHarf;
    if (_durum[h] == 'dogru') return;
    final girilen = _controller.text;
    if (girilen.trim().isEmpty) return;
    _yazilan[h] = girilen;
    context.read<SoundService>().click();
    if (_cevapGecerli(girilen, _dogruCevapMetni(_aktifSoru))) {
      setState(() {
        _durum[h] = 'dogru';
        _puan[h] = _guncelPuan(h);
        _dogruSayi = _durum.values.where((d) => d == 'dogru').length;
        _yanlisTitre = false;
      });
      if (_dogruSayi >= _harfler.length) {
        Future.delayed(kAlfabeGecisSuresi, () {
          if (mounted) _finish();
        });
      } else {
        Future.delayed(kAlfabeGecisSuresi, () {
          if (mounted) _sonrakiBekleyene();
        });
      }
    } else {
      setState(() => _yanlisTitre = true);
    }
  }

  void _ipucuIste() {
    final h = _aktifHarf;
    if (_durum[h] == 'dogru') return;
    final toplam = _ipuclariUret(_aktifSoru).length;
    final acik = _ipucu[h] ?? 0;
    if (acik >= toplam) return;
    context.read<SoundService>().click();
    setState(() => _ipucu[h] = acik + 1);
  }

  Future<void> _finish() async {
    if (_finished) return;
    setState(() => _finished = true);
    final storage = context.read<StorageService>();
    // ignore: unawaited_futures
    AdService.instance.gecisReklamiGoster(premium: storage.isPremiumUser());
    final bos = _harfler.length - _dogruSayi;
    await storage.setLastRoundStats(kAlfabeOyunuGameId,
        correct: _dogruSayi, wrong: bos);
    final yeniRekor = await storage.submitHighScore(kAlfabeOyunuGameId, _toplamPuan);
    if (!mounted) return;
    setState(() => _yeniRekor = yeniRekor);
  }

  bool _yeniRekor = false;

  void _retry() {
    setState(() {
      _locked = false;
      _booted = false;
      _finished = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return LockedFeatureCard(
        gameId: kAlfabeOyunuGameId,
        oyunAdi: 'Alfabe Oyunu',
        onUnlocked: () => setState(() => _locked = false),
        title: 'Alfabe Oyunu',
        desc: "Bugünkü ücretsiz Alfabe Oyunu hakkını kullandın. Yarın tekrar "
            "oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return Scaffold(
        appBar: AppBar(title: const Text('🔤 Alfabe Oyunu')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_finished) return _buildResult(context);
    return _buildBoard(context);
  }

  // ── Oyun tahtası (tek ekrana sığar, kaydırmasız) ─────────────────────────
  Widget _buildBoard(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final h = _aktifHarf;
    final cozuldu = _durum[h] == 'dogru';
    final acikIpucu = _ipucu[h] ?? 0;
    final ipucuListe = _ipuclariUret(_aktifSoru);

    return Scaffold(
      appBar: AppBar(
        title: const Text('🔤 Alfabe Oyunu'),
        actions: [
          TextButton(
            onPressed: () {
              context.read<SoundService>().click();
              _finish();
            },
            child: Text('Bitir',
                style: TextStyle(color: c.violet, fontWeight: FontWeight.w900)),
          ),
          const HowToPlayButton(
            title: 'Alfabe Oyunu nasıl oynanır?',
            body:
                'Her harf için, cevabı o harfle başlayan bir soru sorulur. '
                'Cevabı klavyeyle YAZ ve "Cevapla"ya bas. Yakın/eksik yazımlar '
                '(ör. "ertuğrul" ↔ "Ertuğrul Gazi") da geçerli sayılır.\n\n'
                'Emin değilsen "İpucu İste" — ama her ipucu o sorudan alacağın '
                'puanı düşürür. Pas yok; ◀ ▶ ile önceki/sonraki sorulara '
                'geçebilir, sonra geri dönebilirsin. "Bitir" ile turu bitir.',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            children: [
              // Puan şeridi.
              Row(
                children: [
                  DsChip(label: '🏆 Toplam: $_toplamPuan', color: c.gold),
                  const Spacer(),
                  DsChip(
                    label: cozuldu
                        ? '✅ ${_puan[h]} puan'
                        : '🎯 Alacağın: ${_guncelPuan(h)}',
                    color: cozuldu ? c.success : c.violet,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Çember + içinde soru kartı — kalan dikey alanı kaplar.
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, cons) {
                      final boyut = min(cons.maxWidth, cons.maxHeight)
                          .clamp(190.0, 340.0);
                      return _buildWheel(c, boyut, cozuldu);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Cevap alanı.
              if (cozuldu)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: c.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.success.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: c.success, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_dogruCevapMetni(_aktifSoru),
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: c.success)),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (v) => _yazilan[h] = v,
                        onSubmitted: (_) => _cevapla(),
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: c.text),
                        decoration: InputDecoration(
                          hintText: 'Cevabı yaz…',
                          hintStyle: TextStyle(color: c.textFaint),
                          filled: true,
                          fillColor: c.glass2,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color: _yanlisTitre ? c.danger : c.border,
                                width: _yanlisTitre ? 2 : 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color: _yanlisTitre ? c.danger : c.violet, width: 2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _cevapla,
                        child: Container(
                          width: 50,
                          height: 50,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [c.violet, c.rose]),
                          ),
                          child: const Icon(Icons.check_rounded,
                              color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                  ],
                ),
              if (_yanlisTitre && !cozuldu) ...[
                const SizedBox(height: 6),
                Text('Tam olmadı, tekrar dene ya da ipucu iste 👇',
                    style: TextStyle(
                        fontSize: 11.5, color: c.danger, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 8),
              // İpucu alanı.
              if (!cozuldu)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: acikIpucu >= ipucuListe.length ? null : _ipucuIste,
                        icon: Icon(Icons.lightbulb_outline_rounded,
                            size: 18, color: c.warn),
                        label: Text(
                          acikIpucu >= ipucuListe.length
                              ? 'İpucu kalmadı'
                              : 'İpucu İste (−$kAlfabeIpucuDusus puan)',
                          style: TextStyle(
                              color: c.warn, fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: c.warn.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              if (acikIpucu > 0) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.warn.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.warn.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < acikIpucu && i < ipucuListe.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text('💡 ${ipucuListe[i]}',
                              style: TextStyle(
                                  fontSize: 12.5, height: 1.3, color: c.textDim)),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              // Gezinme: önceki / durum / sonraki.
              Row(
                children: [
                  _navButton(c, Icons.chevron_left_rounded, 'Önceki',
                      _aktifIndex > 0 ? () => _gezin(-1) : null),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_aktifIndex + 1}/${_harfler.length}  ·  ✅ $_dogruSayi',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: c.textDim),
                      ),
                    ),
                  ),
                  _navButton(c, Icons.chevron_right_rounded, 'Sonraki',
                      _aktifIndex < _harfler.length - 1 ? () => _gezin(1) : null),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navButton(KpssColors c, IconData icon, String label, VoidCallback? onTap) {
    final aktif = onTap != null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: aktif ? c.violet.withValues(alpha: 0.5) : c.border),
        ),
        child: Icon(icon, color: aktif ? c.violet : c.textFaint, size: 24),
      ),
    );
  }

  /// Alfabe çemberi — ortada tatlı renkli, kaydırılabilir SORU kartı.
  Widget _buildWheel(KpssColors colors, double boyut, bool cozuldu) {
    final harfCap = boyut < 240 ? 22.0 : 26.0;
    final yaricap = (boyut - harfCap) / 2 - 2;
    final merkez = boyut / 2;
    final n = _harfler.length;

    final cocuklar = <Widget>[];
    for (var i = 0; i < n; i++) {
      final harf = _harfler[i];
      final aci = -pi / 2 + (2 * pi * i / n);
      final x = merkez + yaricap * cos(aci) - harfCap / 2;
      final y = merkez + yaricap * sin(aci) - harfCap / 2;
      final durum = _durum[harf];
      final aktif = i == _aktifIndex;

      Color renk;
      Color yazi = Colors.white;
      if (durum == 'dogru') {
        renk = colors.success;
      } else if (aktif) {
        renk = colors.violet;
      } else {
        renk = colors.glass2;
        yazi = colors.textFaint;
      }
      cocuklar.add(Positioned(
        left: x,
        top: y,
        child: Container(
          width: harfCap,
          height: harfCap,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: renk,
            shape: BoxShape.circle,
            border: Border.all(
              color: aktif ? colors.violet : colors.border,
              width: aktif ? 2.5 : 1,
            ),
            boxShadow: aktif
                ? [BoxShadow(color: colors.violet.withValues(alpha: 0.5), blurRadius: 10)]
                : null,
          ),
          child: Text(harf,
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: harfCap < 24 ? 11 : 13,
                  color: yazi)),
        ),
      ));
    }

    // Ortadaki soru kartı (çemberin içine sığan en büyük kare).
    final ic = ((merkez - harfCap - 6) * 1.30).clamp(120.0, boyut);
    cocuklar.add(Positioned(
      left: (boyut - ic) / 2,
      top: (boyut - ic) / 2,
      width: ic,
      height: ic,
      child: _soruKarti(colors, cozuldu),
    ));

    return SizedBox(width: boyut, height: boyut, child: Stack(children: cocuklar));
  }

  /// Tatlı renkli, gerekirse dikey kaydırılabilen soru kartı.
  Widget _soruKarti(KpssColors colors, bool cozuldu) {
    final soru = _aktifSoru;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bg2,
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.violet.withValues(alpha: 0.16),
            colors.rose.withValues(alpha: 0.16),
          ],
        ),
        border: Border.all(color: colors.violet.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: colors.violet.withValues(alpha: 0.18),
            blurRadius: 16,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cozuldu ? colors.success : colors.violet,
              shape: BoxShape.circle,
            ),
            child: Text(_aktifHarf,
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
          ),
          const SizedBox(height: 8),
          // Uzun soru: dikey kaydırılır; kelimeler normal (boşlukta) bölünür.
          Flexible(
            child: SingleChildScrollView(
              child: Text(
                soru.soru,
                textAlign: TextAlign.center,
                softWrap: true,
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.32,
                    fontWeight: FontWeight.w700,
                    color: colors.text),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tur sonu: özet + Cevap Anahtarı ──────────────────────────────────────
  Widget _buildResult(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final storage = context.watch<StorageService>();
    final toplam = _harfler.length;
    final basari = _dogruSayi >= (toplam * 0.7);
    final emoji =
        _yeniRekor ? '🏆' : (basari ? '🎉' : (_dogruSayi >= toplam * 0.4 ? '💪' : '📚'));
    final isimaRengi = _yeniRekor ? c.gold : c.violet;

    final incelenecek = List<String>.from(_harfler)
      ..sort((a, b) => _harfSira(a).compareTo(_harfSira(b)));

    return Scaffold(
      appBar: AppBar(title: const Text('🔤 Alfabe Oyunu')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          children: [
            Center(child: DsIllustration(emoji: emoji, size: 92, glowColor: isimaRengi)),
            const SizedBox(height: 10),
            Text(
              _yeniRekor ? 'Yeni puan rekoru!' : 'Tur bitti',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c.text),
            ),
            const SizedBox(height: 6),
            Text(
              '$toplam sorudan $_dogruSayi tanesini bildin.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textDim),
            ),
            const SizedBox(height: 16),
            DsStatStrip(
              items: [
                DsStatItem(
                  visual: Text('$_dogruSayi',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: c.success)),
                  value: '',
                  label: '✅ Doğru',
                ),
                DsStatItem(
                  visual: Text('${toplam - _dogruSayi}',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: c.danger)),
                  value: '',
                  label: '❌ Boş/Yanlış',
                ),
                DsStatItem(
                  visual: Text('$_toplamPuan',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: c.violet)),
                  value: '',
                  label: '🏆 Puan',
                ),
              ],
            ),
            const SizedBox(height: kDsGap),
            DsCard(
              accent: _yeniRekor ? c.gold : null,
              child: Row(
                children: [
                  const Text('🎯', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _yeniRekor ? 'Yeni rekor puanın!' : 'Rekor puan',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.textDim),
                    ),
                  ),
                  Text(
                    '${storage.getHighScore(kAlfabeOyunuGameId)}',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _yeniRekor ? c.gold : c.text),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text('📖', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text('Cevap Anahtarı',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: c.text)),
              ],
            ),
            const SizedBox(height: 10),
            for (final h in incelenecek) _buildReviewItem(h, c),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                DsPillButton(
                  label: 'Tekrar Oyna',
                  leadingIcon: Icons.refresh,
                  color: c.violet,
                  onPressed: () {
                    context.read<SoundService>().click();
                    _retry();
                  },
                ),
                DsPillButton(
                  label: 'Oyunlara Dön',
                  filled: false,
                  color: c.violet,
                  onPressed: () {
                    context.read<SoundService>().click();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewItem(String harf, KpssColors c) {
    final soru = _soru[harf]!;
    final dogruMu = _durum[harf] == 'dogru';
    final Color renk = dogruMu ? c.success : c.danger;
    final String rozet = dogruMu ? '✅' : '❌';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: c.glass2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: renk.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
                child: Text(harf,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(soru.soru,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, height: 1.3, color: c.text)),
              ),
              const SizedBox(width: 6),
              Text(rozet, style: const TextStyle(fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          Text('✔ Cevap: ${_dogruCevapMetni(soru)}',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: c.success)),
          const SizedBox(height: 3),
          Text(soru.aciklama,
              style: TextStyle(fontSize: 12, height: 1.4, color: c.textDim)),
        ],
      ),
    );
  }
}
