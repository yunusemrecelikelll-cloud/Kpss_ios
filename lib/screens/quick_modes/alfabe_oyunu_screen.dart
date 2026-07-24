import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/alfabe_sorulari.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/design_system.dart';
import '../../theme/theme_provider.dart';
import '../tools_hub_screen.dart';
import 'quick_modes_shared.dart';

/// Mini oyun — "KPSS Tarih Alfabetik" (Passaparola/Bil Bakalım tarzı):
/// A'dan Z'ye her harf için, cevabı o harfle başlayan bir soru sorulur.
/// Üstteki çemberde her harf bir düğme: mavi = sıradaki, yeşil = doğru,
/// kırmızı = yanlış, sarı = pas geçilen, gri = henüz gelmedi. Üstte turu
/// bitirene kadar İŞLEYEN bir kronometre vardır; en iyi (en kısa) süre
/// [StorageService.getBestTimeSeconds] ile kaydedilir.
///
/// AKIŞ: Şıkka basınca kısa bir renk geri bildiriminden sonra OTOMATİK olarak
/// sonraki harfe geçilir; açıklamalar tek tek DEĞİL, tur sonundaki "Cevap
/// Anahtarı" bölümünde toplu gösterilir.
///
/// Bu Faz 1 sürümüdür: tek kişilik, 5 şıklı. (Premium 2 kişilik SESLİ mod
/// sonraki fazda eklenecek — bkz. plan.) Sorular [kAlfabeSorulari] içinde,
/// Desktop/Kpss.pdf'ten çıkarılan veri setinden gelir; her sorunun harfi
/// DOĞRU CEVABIN ilk harfinden türetildiği için "cevabı X ile başlayan soru"
/// vaadi her zaman doğrudur.
const String kAlfabeOyunuGameId = 'alfabe-oyunu';

/// Şıkka basıldıktan sonra doğru/yanlış rengi görünsün diye beklenen kısa süre.
const Duration kAlfabeGecisSuresi = Duration(milliseconds: 850);

/// Türk alfabesi sıralaması — çemberdeki harfleri doğru sırada dizmek için.
const List<String> _kTurkAlfabe = [
  'A', 'B', 'C', 'Ç', 'D', 'E', 'F', 'G', 'Ğ', 'H', 'I', 'İ', 'J', 'K', 'L',
  'M', 'N', 'O', 'Ö', 'P', 'R', 'S', 'Ş', 'T', 'U', 'Ü', 'V', 'Y', 'Z',
];

int _harfSira(String h) {
  final i = _kTurkAlfabe.indexOf(h);
  return i < 0 ? 999 : i;
}

/// Baştaki sıra öneki: Roma rakamı ("I. ", "II. ", "IV. "...) ya da Arap
/// rakamı ("1. ") — bunlar SAYI, harf değil ("I. İnönü" → İ, "II. Mahmut" → M).
final RegExp _kSiraOnek = RegExp(r'^(?:[IVXLCDM]{1,5}|\d+)\.\s+');

/// Türkçe kurallı ilk harf (büyük). Baştaki sıra öneki atlanır; 'i' → 'İ'
/// özel olarak ele alınır. (Veri üreticisindeki `ilk()` ile aynı mantık.)
String _ilkHarf(String s) {
  s = s.trim();
  final m = _kSiraOnek.matchAsPrefix(s);
  if (m != null) s = s.substring(m.end).trim();
  if (s.isEmpty) return '?';
  var ch = s[0];
  if (ch == 'i') ch = 'İ';
  return ch.toUpperCase();
}

/// Saniyeyi "01:29" biçimine çevirir.
String _mmss(int saniye) {
  final m = (saniye ~/ 60).toString().padLeft(2, '0');
  final s = (saniye % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Saniyeyi "1 dk 49 sn" / "45 sn" / "2 dk" biçiminde uzun Türkçe metne çevirir
/// (kart kapağında ve tanıtım ekranında rekor süre böyle gösterilir).
String alfabeSureMetni(int saniye) {
  if (saniye < 60) return '$saniye sn';
  final dk = saniye ~/ 60;
  final sn = saniye % 60;
  return sn == 0 ? '$dk dk' : '$dk dk $sn sn';
}

/// Oyun kartına basınca AÇILAN tanıtım/başlangıç ekranı (kullanıcı isteği:
/// "karta basınca direkt oyun başlamasın, önce oyunu tanıtan, rekoru gösteren
/// bir ekran gelsin"). Rekor süre, rekor doğru ve son tur doğru/yanlış
/// gösterir; "Oyna" ile asıl oyuna ([AlfabeOyunuScreen]) geçer.
///
/// StorageService [context.watch] ile dinlendiği için, oyundan dönünce
/// (rekorlar submitHighScore/submitBestTime ile güncellendiğinde) ekran
/// kendiliğinden tazelenir.
class AlfabeOyunuTanitimScreen extends StatelessWidget {
  const AlfabeOyunuTanitimScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final storage = context.watch<StorageService>();
    final premium = storage.isPremiumUser();
    final best = storage.getBestTimeSeconds(kAlfabeOyunuGameId);
    final rekorDogru = storage.getHighScore(kAlfabeOyunuGameId);
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
              'sorusu. Doğru şıkkı seç; süreyle yarış, tüm alfabeyi en kısa '
              'sürede bitirmeye çalış. Emin olmadığın harfi "Pas" ile sona '
              'atabilirsin.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: c.textDim),
            ),
            const SizedBox(height: 18),
            // Rekor süre — büyük vurgulu kart.
            DsCard(
              accent: c.violet,
              child: Row(
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Rekor süre',
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w800, color: c.text)),
                  ),
                  Text(
                    best != null ? alfabeSureMetni(best) : '—',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900, color: c.violet),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Doğru / Yanlış (son tur) + Rekor doğru.
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
                  label: '❌ Yanlış',
                ),
                DsStatItem(
                  visual: Text('$rekorDogru',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c.gold)),
                  value: '',
                  label: '🎯 Rekor doğru',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                son['correct'] == 0 && son['wrong'] == 0
                    ? 'Doğru/Yanlış: son oynadığın tur'
                    : 'Doğru/Yanlış: son tur',
                style: TextStyle(fontSize: 10.5, color: c.textFaint),
              ),
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

  bool _locked = false;
  bool _booted = false;
  bool _finished = false;
  bool _tamamlandi = false; // tur bittiğinde TÜM harfler cevaplandı mı
  bool _yeniRekor = false; // yeni SÜRE rekoru
  bool _yeniDogruRekor = false; // yeni DOĞRU sayısı rekoru

  /// Bu turda oynanan harfler, Türk alfabesi sırasında.
  final List<String> _harfler = [];

  /// Her harf için seçilmiş soru.
  final Map<String, AlfabeSorusu> _soru = {};

  /// Harf durumu: 'bekliyor' | 'dogru' | 'yanlis' | 'pas'.
  final Map<String, String> _durum = {};

  /// Kullanıcının o harfte seçtiği şık (A-E). Pas geçilenlerde yer almaz.
  final Map<String, String> _secim = {};

  /// Henüz cevaplanmamış harflerin sırası (pas geçilen sona atılır).
  final List<String> _kuyruk = [];

  int _dogruSayi = 0;
  int _yanlisSayi = 0;

  int _saniye = 0;
  Timer? _ticker;
  Timer? _autoNext;

  /// Şıkka basıldıktan sonra geçiş bekleme anında seçilen şık (input kilitli).
  /// null ise yeni cevap kabul edilir.
  String? _secilenSik;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _autoNext?.cancel();
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

    // Harf başına soruları grupla.
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
    _secim.clear();
    _kuyruk.clear();
    for (final h in harfler) {
      final liste = byLetter[h]!;
      // Mümkünse 5 şıkkın TAMAMI aynı harfle başlayan "temiz" soruyu tercih et
      // (şıklar karışık görünmesin); yoksa harfteki herhangi bir soruyu al.
      final temizler = liste
          .where((q) => q.siklar.values.map(_ilkHarf).toSet().length == 1)
          .toList();
      final havuz = temizler.isNotEmpty ? temizler : liste;
      _soru[h] = havuz[_rnd.nextInt(havuz.length)];
      _durum[h] = 'bekliyor';
      _kuyruk.add(h);
    }

    setState(() {
      _dogruSayi = 0;
      _yanlisSayi = 0;
      _saniye = 0;
      _finished = false;
      _tamamlandi = false;
      _yeniRekor = false;
      _yeniDogruRekor = false;
      _secilenSik = null;
      _booted = true;
    });
    _baslatKronometre();
  }

  void _baslatKronometre() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _saniye++);
    });
  }

  String get _aktifHarf => _kuyruk.first;
  AlfabeSorusu get _aktifSoru => _soru[_aktifHarf]!;

  void _cevapla(String sik) {
    if (_secilenSik != null) return; // geçiş bekleniyor, yeni cevap alma
    context.read<SoundService>().click();
    final harf = _aktifHarf;
    final dogruMu = sik == _aktifSoru.dogru;
    setState(() {
      _secilenSik = sik;
      _secim[harf] = sik;
      _durum[harf] = dogruMu ? 'dogru' : 'yanlis';
      if (dogruMu) {
        _dogruSayi++;
      } else {
        _yanlisSayi++;
      }
    });
    // Kronometre çalışmaya devam eder; kısa geri bildirimden sonra otomatik geç.
    _autoNext?.cancel();
    _autoNext = Timer(kAlfabeGecisSuresi, () {
      if (!mounted) return;
      _ilerle();
    });
  }

  void _ilerle() {
    _kuyruk.removeAt(0); // cevaplanan harf kuyruktan çıkar
    setState(() => _secilenSik = null);
    if (_kuyruk.isEmpty) {
      _tamamlandi = true;
      _finish();
    }
  }

  void _pas() {
    if (_secilenSik != null) return;
    context.read<SoundService>().click();
    final h = _kuyruk.removeAt(0);
    _durum[h] = 'pas';
    _kuyruk.add(h);
    // Kalan herkes pas geçildiyse tur biter (sonsuz döngü olmasın).
    if (_kuyruk.every((x) => _durum[x] == 'pas')) {
      _tamamlandi = false;
      _finish();
      return;
    }
    setState(() {});
  }

  Future<void> _finish() async {
    _ticker?.cancel();
    _autoNext?.cancel();
    setState(() => _finished = true);
    final storage = context.read<StorageService>();
    await storage.setLastRoundStats(kAlfabeOyunuGameId,
        correct: _dogruSayi, wrong: _yanlisSayi);
    // Rekor DOĞRU sayısı (oyun-içi sağ üstteki rekor + tanıtım ekranı bunu
    // kullanır; eskiden hiç yazılmadığı için "hep sıfır" görünüyordu).
    final yeniDogruRekor = await storage.submitHighScore(kAlfabeOyunuGameId, _dogruSayi);
    // Rekor SÜRE yalnızca tüm harfler cevaplandıysa (tam tur).
    var yeni = false;
    if (_tamamlandi) {
      yeni = await storage.submitBestTime(kAlfabeOyunuGameId, _saniye);
    }
    if (!mounted) return;
    setState(() {
      _yeniRekor = yeni;
      _yeniDogruRekor = yeniDogruRekor;
    });
  }

  void _retry() {
    _autoNext?.cancel();
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

  // ── Tur sonu: özet + Cevap Anahtarı ──────────────────────────────────────
  Widget _buildResult(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final storage = context.watch<StorageService>();
    final best = storage.getBestTimeSeconds(kAlfabeOyunuGameId);
    final toplam = _harfler.length;
    final basari = _dogruSayi >= (toplam * 0.7);
    final emoji =
        _yeniRekor ? '🏆' : (basari ? '🎉' : (_dogruSayi >= toplam * 0.4 ? '💪' : '📚'));
    final isimaRengi = _yeniRekor ? c.gold : c.violet;

    // Cevap anahtarına yalnızca gerçekten karşılaşılan harfler (cevaplanan +
    // pas geçilen) girer; sıra Türk alfabesi sırasında.
    final incelenecek = _harfler
        .where((h) => _durum[h] != 'bekliyor')
        .toList()
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
              _yeniRekor
                  ? 'Yeni süre rekoru!'
                  : (_tamamlandi ? 'Alfabeyi bitirdin!' : 'Tur bitti'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c.text),
            ),
            const SizedBox(height: 6),
            Text(
              '$toplam harften $_dogruSayi tanesini doğru bildin.',
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
                  visual: Text('$_yanlisSayi',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: c.danger)),
                  value: '',
                  label: '❌ Yanlış',
                ),
                DsStatItem(
                  visual: Text(_mmss(_saniye),
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: c.violet)),
                  value: '',
                  label: '⏱️ Süre',
                ),
              ],
            ),
            const SizedBox(height: kDsGap),
            DsCard(
              accent: _yeniRekor ? c.gold : null,
              child: Row(
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _tamamlandi
                          ? 'En iyi süren'
                          : 'Süre rekoru için tüm harfleri cevapla',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.textDim),
                    ),
                  ),
                  Text(
                    best != null ? alfabeSureMetni(best) : '—',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _yeniRekor ? c.gold : c.text),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            DsCard(
              accent: _yeniDogruRekor ? c.gold : null,
              child: Row(
                children: [
                  const Text('🎯', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _yeniDogruRekor ? 'Yeni doğru rekoru!' : 'Rekor doğru',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.textDim),
                    ),
                  ),
                  Text(
                    '${storage.getHighScore(kAlfabeOyunuGameId)}',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _yeniDogruRekor ? c.gold : c.text),
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
    final durum = _durum[harf];
    final secilen = _secim[harf];
    final Color renk = durum == 'dogru'
        ? c.success
        : durum == 'yanlis'
            ? c.danger
            : c.warn;
    final String rozet = durum == 'dogru'
        ? '✅'
        : durum == 'yanlis'
            ? '❌'
            : '⏭️';
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
          Text('✔ Doğru cevap: ${soru.dogru}) ${soru.siklar[soru.dogru]}',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: c.success)),
          const SizedBox(height: 3),
          Text(soru.aciklama,
              style: TextStyle(fontSize: 12, height: 1.4, color: c.textDim)),
          // Yanlış cevap verildiyse: kullanıcının seçtiği şık + çeldirici analizi.
          if (durum == 'yanlis' && secilen != null) ...[
            const SizedBox(height: 6),
            Text('Senin cevabın: $secilen) ${soru.siklar[secilen]}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.danger)),
            if (soru.celdiriciler[secilen] != null) ...[
              const SizedBox(height: 2),
              Text(soru.celdiriciler[secilen]!,
                  style: TextStyle(fontSize: 11.5, height: 1.4, color: c.textFaint)),
            ],
          ],
        ],
      ),
    );
  }

  // ── Oyun tahtası ─────────────────────────────────────────────────────────
  Widget _buildBoard(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final soru = _aktifSoru;
    final kalan = _kuyruk.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔤 Alfabe Oyunu'),
        actions: const [
          HowToPlayButton(
            title: 'Alfabe Oyunu nasıl oynanır?',
            body:
                'Her harf için, cevabı o harfle başlayan bir soru sorulur. '
                'Doğru şıkkı seç; şıkka basınca kısa bir geri bildirimden sonra '
                'otomatik olarak sonraki harfe geçilir. Emin değilsen "Pas" ile '
                'harfi sona atabilirsin; tur sonunda pas geçtiklerine dönülür.\n\n'
                'Üstteki çemberde: 🔵 sıradaki harf, 🟢 doğru, 🔴 yanlış, '
                '🟡 pas. Kronometre turu bitirene kadar işler; tüm harfleri '
                'cevaplarsan en iyi (en kısa) süren kaydedilir. Tüm açıklamalar '
                'tur sonundaki "Cevap Anahtarı" bölümünde toplu gösterilir.',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            QuickModeScoreBar(
              gameId: kAlfabeOyunuGameId, // rekor tutmuyor ama şerit ortak
              correct: _dogruSayi,
              wrong: _yanlisSayi,
              leading: '⏱️ ${_mmss(_saniye)}',
              leadingColor: colors.violet,
            ),
            const SizedBox(height: 14),
            Center(child: _buildWheel(colors)),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.glass2,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _harfRozet(_aktifHarf, colors.violet),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Cevabı "$_aktifHarf" ile başlıyor',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700, color: colors.textFaint),
                        ),
                      ),
                      Text('Kalan $kalan',
                          style: TextStyle(fontSize: 11.5, color: colors.textFaint)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    soru.soru,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (final harf in const ['A', 'B', 'C', 'D', 'E'])
              _buildSik(harf, soru, colors),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _secilenSik == null ? _pas : null,
                icon: Icon(Icons.skip_next_rounded, color: colors.warn),
                label: Text('Pas geç',
                    style: TextStyle(color: colors.warn, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Çemberdeki A-Z harf halkası — ortada sıradaki harf + kronometre.
  Widget _buildWheel(KpssColors colors) {
    const double boyut = 300;
    const double harfCap = 30;
    final double yaricap = (boyut - harfCap) / 2 - 2;
    const double merkez = boyut / 2;
    final n = _harfler.length;

    final cocuklar = <Widget>[];
    for (var i = 0; i < n; i++) {
      final harf = _harfler[i];
      final aci = -pi / 2 + (2 * pi * i / n); // tepeden başla, saat yönünde
      final x = merkez + yaricap * cos(aci) - harfCap / 2;
      final y = merkez + yaricap * sin(aci) - harfCap / 2;
      final durum = _durum[harf];
      final sirada = _kuyruk.isNotEmpty && harf == _aktifHarf;

      Color renk;
      Color yazi = Colors.white;
      switch (durum) {
        case 'dogru':
          renk = colors.success;
          break;
        case 'yanlis':
          renk = colors.danger;
          break;
        case 'pas':
          renk = sirada ? colors.violet : colors.warn;
          break;
        default:
          renk = sirada ? colors.violet : colors.glass2;
          yazi = sirada ? Colors.white : colors.textFaint;
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
              color: sirada ? colors.violet : colors.border,
              width: sirada ? 2.5 : 1,
            ),
            boxShadow: sirada
                ? [BoxShadow(color: colors.violet.withValues(alpha: 0.5), blurRadius: 10)]
                : null,
          ),
          child: Text(harf,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: yazi)),
        ),
      ));
    }

    cocuklar.add(Positioned(
      left: 0,
      top: 0,
      width: boyut,
      height: boyut,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _kuyruk.isEmpty ? '✓' : _aktifHarf,
              style: TextStyle(
                  fontSize: 64, fontWeight: FontWeight.w900, color: colors.violet, height: 1.0),
            ),
            const SizedBox(height: 2),
            Text('⏱️ ${_mmss(_saniye)}',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: colors.textDim)),
          ],
        ),
      ),
    ));

    return SizedBox(width: boyut, height: boyut, child: Stack(children: cocuklar));
  }

  Widget _harfRozet(String harf, Color renk) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
      child: Text(harf,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white)),
    );
  }

  Widget _buildSik(String harf, AlfabeSorusu soru, KpssColors colors) {
    Color? borderColor;
    Color? bgColor;
    // Yalnızca cevaplandıktan sonra (geçiş beklerken) doğru/yanlış boyanır.
    if (_secilenSik != null) {
      if (harf == soru.dogru) {
        borderColor = colors.success;
        bgColor = colors.success.withValues(alpha: 0.12);
      } else if (harf == _secilenSik) {
        borderColor = colors.danger;
        bgColor = colors.danger.withValues(alpha: 0.12);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _secilenSik == null ? () => _cevapla(harf) : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor ?? colors.border),
            color: bgColor,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$harf) ',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 14.5, color: colors.textDim)),
              Expanded(
                child: Text(soru.siklar[harf] ?? '',
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.3)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
