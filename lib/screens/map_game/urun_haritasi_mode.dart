import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/turkey_map_data.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_provider.dart';
import '../tools_hub_screen.dart';
import 'map_shared.dart';

const int kUrunRounds = 8;

const String _kHowToPlay =
    'Ekranda bir ürün/konu adı yazar (ör. fındık, bor, otomotiv). O ürün ya da '
    'konuyla en çok özdeşleşen ili haritada işaretle. Yanlış dokunursan 3 '
    'hakkın vardır.';

/// Konu haritalarının kategorileri. Her kategori, harita hub\'ında AYRI bir
/// oyun olarak açılır; oyun o kategorinin öğelerinden sorar (kullanıcı isteği:
/// "ayrı ayrı harita değil; tarım oyununda soruya göre şehir çıksın").
enum HaritaKategori { tarim, hayvancilik, yoresel, madenler, enerji, sanayi, cografya, ulasimTurizm }

/// Hub\'da bir kategori oyununu tanıtan meta bilgi (emoji + başlık + açıklama).
class HaritaKategoriBilgi {
  final HaritaKategori kategori;
  final String emoji;
  final String ad;
  final String aciklama;
  const HaritaKategoriBilgi(this.kategori, this.emoji, this.ad, this.aciklama);
}

/// Hub bu listeyi gezerek kategori oyunlarını çizer (bkz. map_game_screen.dart).
const List<HaritaKategoriBilgi> kHaritaKategorileri = [
  HaritaKategoriBilgi(HaritaKategori.tarim, '🌾', 'Tarım Haritası',
      'Ürünlerin en çok yetiştiği ili bul.'),
  HaritaKategoriBilgi(HaritaKategori.hayvancilik, '🐄', 'Hayvancılık Haritası',
      'Hayvan varlığı/üretiminde 1. olan ili bul.'),
  HaritaKategoriBilgi(HaritaKategori.yoresel, '🧀', 'Yöresel Ürünler',
      'Tescilli/özdeşleşen yöresel ürünün ilini bul.'),
  HaritaKategoriBilgi(HaritaKategori.madenler, '⛏️', 'Madenler Haritası',
      'Madenin en önemli çıkarım yerini bul.'),
  HaritaKategoriBilgi(HaritaKategori.enerji, '⚡', 'Enerji Haritası',
      'Enerji kaynağı/tesisinin ilini bul.'),
  HaritaKategoriBilgi(HaritaKategori.sanayi, '🏭', 'Sanayi Haritası',
      'Sanayi kolu/el sanatının merkez ilini bul.'),
  HaritaKategoriBilgi(HaritaKategori.cografya, '🏔️', 'Coğrafya & Doğa',
      'Yer şekli, su kaynağı ve doğa öğesinin ilini bul.'),
  HaritaKategoriBilgi(HaritaKategori.ulasimTurizm, '🚢', 'Ulaşım & Turizm',
      'Liman, antik kent, kayak/termal merkezinin ilini bul.'),
];

String haritaKategoriEmoji(HaritaKategori k) =>
    kHaritaKategorileri.firstWhere((b) => b.kategori == k).emoji;
String haritaKategoriAd(HaritaKategori k) =>
    kHaritaKategorileri.firstWhere((b) => b.kategori == k).ad;

/// KPSS ekonomik/fiziki coğrafyasından bir öğe ile onunla en çok özdeşleşen
/// il(ler)i eşleyen kayıt. Cevaplar TÜİK/resmî kuruma göre GÜNCEL ve büyük
/// çoğunlukla TEK ildir (üretim/varlık/çıkarım 1.\'si). İl adını ELE VEREN
/// öğe adı kullanılmaz (ör. "Maraş dondurması" değil "Dövme Dondurma").
class UrunEsleme {
  final String urun;
  final List<String> ilIds;
  final HaritaKategori kategori;
  const UrunEsleme(this.urun, this.ilIds, {required this.kategori});
}

const List<UrunEsleme> kUrunEslemeleri = [
  // ── TARIM ──────────────────────────────────────────────────────────────
  UrunEsleme('Çay', ['rize'], kategori: HaritaKategori.tarim),
  UrunEsleme('Fındık', ['samsun'], kategori: HaritaKategori.tarim),
  UrunEsleme('Antep Fıstığı', ['sanliurfa'], kategori: HaritaKategori.tarim),
  UrunEsleme('Kayısı', ['mersin'], kategori: HaritaKategori.tarim),
  UrunEsleme('Pamuk', ['sanliurfa'], kategori: HaritaKategori.tarim),
  UrunEsleme('Zeytin', ['aydin'], kategori: HaritaKategori.tarim),
  UrunEsleme('Kuru İncir', ['aydin'], kategori: HaritaKategori.tarim),
  UrunEsleme('Çekirdeksiz Kuru Üzüm', ['manisa'], kategori: HaritaKategori.tarim),
  UrunEsleme('Gül (Gül Yağı)', ['isparta'], kategori: HaritaKategori.tarim),
  UrunEsleme('Muz', ['antalya'], kategori: HaritaKategori.tarim),
  UrunEsleme('Şeftali', ['canakkale'], kategori: HaritaKategori.tarim),
  UrunEsleme('Leblebi (nohut işleme)', ['denizli'], kategori: HaritaKategori.tarim),
  UrunEsleme('Elma', ['isparta'], kategori: HaritaKategori.tarim),
  UrunEsleme('Ayçiçeği', ['konya'], kategori: HaritaKategori.tarim),
  UrunEsleme('Tütün', ['denizli'], kategori: HaritaKategori.tarim),
  UrunEsleme('Haşhaş', ['afyonkarahisar'], kategori: HaritaKategori.tarim),
  UrunEsleme('Kivi', ['yalova'], kategori: HaritaKategori.tarim),
  UrunEsleme('Çeltik (pirinç)', ['edirne'], kategori: HaritaKategori.tarim),
  UrunEsleme('Buğday', ['konya'], kategori: HaritaKategori.tarim),
  UrunEsleme('Arpa', ['konya'], kategori: HaritaKategori.tarim),
  UrunEsleme('Mısır', ['konya'], kategori: HaritaKategori.tarim),
  UrunEsleme('Şeker Pancarı', ['konya'], kategori: HaritaKategori.tarim),
  UrunEsleme('Turunçgil (narenciye)', ['adana'], kategori: HaritaKategori.tarim),
  UrunEsleme('Nar', ['antalya'], kategori: HaritaKategori.tarim),
  UrunEsleme('Kiraz', ['izmir'], kategori: HaritaKategori.tarim),
  UrunEsleme('Vişne', ['afyonkarahisar'], kategori: HaritaKategori.tarim),
  UrunEsleme('Çilek', ['mersin'], kategori: HaritaKategori.tarim),
  UrunEsleme('Domates', ['bursa'], kategori: HaritaKategori.tarim),
  UrunEsleme('Biber', ['mersin'], kategori: HaritaKategori.tarim),
  UrunEsleme('Patates', ['kayseri'], kategori: HaritaKategori.tarim),
  UrunEsleme('Kuru Soğan', ['ankara'], kategori: HaritaKategori.tarim),
  UrunEsleme('Sarımsak', ['kastamonu'], kategori: HaritaKategori.tarim),
  UrunEsleme('Kırmızı Mercimek', ['sanliurfa'], kategori: HaritaKategori.tarim),
  UrunEsleme('Nohut', ['ankara'], kategori: HaritaKategori.tarim),
  UrunEsleme('Kuru Fasulye', ['nigde'], kategori: HaritaKategori.tarim),
  UrunEsleme('Ceviz', ['hakkari'], kategori: HaritaKategori.tarim),
  UrunEsleme('Badem', ['mersin'], kategori: HaritaKategori.tarim),
  UrunEsleme('Kestane', ['aydin'], kategori: HaritaKategori.tarim),
  UrunEsleme('Susam', ['antalya'], kategori: HaritaKategori.tarim),
  UrunEsleme('Soya', ['adana'], kategori: HaritaKategori.tarim),
  UrunEsleme('Kanola (kolza)', ['tekirdag'], kategori: HaritaKategori.tarim),
  UrunEsleme('Karpuz', ['adana'], kategori: HaritaKategori.tarim),
  UrunEsleme('Kavun', ['adana'], kategori: HaritaKategori.tarim),
  UrunEsleme('Anason', ['burdur'], kategori: HaritaKategori.tarim),
  UrunEsleme('Kimyon', ['ankara'], kategori: HaritaKategori.tarim),
  UrunEsleme('Kekik', ['denizli'], kategori: HaritaKategori.tarim),
  UrunEsleme('Defne', ['mersin'], kategori: HaritaKategori.tarim),
  UrunEsleme('Nane', ['gaziantep'], kategori: HaritaKategori.tarim),
  UrunEsleme('Safran', ['karabuk'], kategori: HaritaKategori.tarim),
  UrunEsleme('Keten', ['usak'], kategori: HaritaKategori.tarim),
  UrunEsleme('Kenevir (kendir)', ['konya'], kategori: HaritaKategori.tarim),
  // ── HAYVANCILIK (varlık/üretim 1.) ─────────────────────────────────────
  UrunEsleme('Sığır (büyükbaş)', ['konya'], kategori: HaritaKategori.hayvancilik),
  UrunEsleme('Koyun (küçükbaş)', ['van'], kategori: HaritaKategori.hayvancilik),
  UrunEsleme('Kıl Keçisi', ['mersin'], kategori: HaritaKategori.hayvancilik),
  UrunEsleme('Tiftik Keçisi', ['ankara'], kategori: HaritaKategori.hayvancilik),
  UrunEsleme('Bal (arıcılık)', ['ordu'], kategori: HaritaKategori.hayvancilik),
  UrunEsleme('Manda', ['samsun'], kategori: HaritaKategori.hayvancilik),
  UrunEsleme('Yumurta tavukçuluğu', ['afyonkarahisar'], kategori: HaritaKategori.hayvancilik),
  UrunEsleme('Et tavukçuluğu (broiler)', ['manisa'], kategori: HaritaKategori.hayvancilik),
  UrunEsleme('Hindi', ['tekirdag'], kategori: HaritaKategori.hayvancilik),
  UrunEsleme('Kaz', ['kars'], kategori: HaritaKategori.hayvancilik),
  UrunEsleme('İpekböceği (koza)', ['diyarbakir'], kategori: HaritaKategori.hayvancilik),
  UrunEsleme('Hamsi (deniz balıkçılığı)', ['trabzon'], kategori: HaritaKategori.hayvancilik),
  UrunEsleme('Kültür balıkçılığı (levrek/çipura)', ['mugla'], kategori: HaritaKategori.hayvancilik),
  // ── YÖRESEL / GIDA ─────────────────────────────────────────────────────
  UrunEsleme('Pastırma ve Sucuk', ['kayseri'], kategori: HaritaKategori.yoresel),
  UrunEsleme('Dövme Dondurma', ['kahramanmaras'], kategori: HaritaKategori.yoresel),
  UrunEsleme('Kırmızı Toz Biber', ['gaziantep'], kategori: HaritaKategori.yoresel),
  UrunEsleme('Otlu Peynir', ['van'], kategori: HaritaKategori.yoresel),
  UrunEsleme('Kaşar Peyniri', ['kars'], kategori: HaritaKategori.yoresel),
  // ── MADENLER (en önemli çıkarım yeri) ──────────────────────────────────
  UrunEsleme('Bor', ['eskisehir'], kategori: HaritaKategori.madenler),
  UrunEsleme('Krom', ['elazig'], kategori: HaritaKategori.madenler),
  UrunEsleme('Demir', ['sivas'], kategori: HaritaKategori.madenler),
  UrunEsleme('Bakır', ['artvin'], kategori: HaritaKategori.madenler),
  UrunEsleme('Kaya Tuzu', ['cankiri'], kategori: HaritaKategori.madenler),
  UrunEsleme('Taşkömürü', ['zonguldak'], kategori: HaritaKategori.madenler),
  UrunEsleme('Lületaşı', ['eskisehir'], kategori: HaritaKategori.madenler),
  UrunEsleme('Linyit', ['manisa'], kategori: HaritaKategori.madenler),
  UrunEsleme('Altın', ['erzincan'], kategori: HaritaKategori.madenler),
  UrunEsleme('Gümüş', ['kutahya'], kategori: HaritaKategori.madenler),
  UrunEsleme('Cıva', ['izmir'], kategori: HaritaKategori.madenler),
  UrunEsleme('Çinko-Kurşun', ['kayseri'], kategori: HaritaKategori.madenler),
  UrunEsleme('Mermer', ['afyonkarahisar'], kategori: HaritaKategori.madenler),
  UrunEsleme('Fosfat', ['mardin'], kategori: HaritaKategori.madenler),
  UrunEsleme('Barit', ['antalya'], kategori: HaritaKategori.madenler),
  UrunEsleme('Perlit', ['izmir'], kategori: HaritaKategori.madenler),
  UrunEsleme('Feldspat', ['mugla'], kategori: HaritaKategori.madenler),
  UrunEsleme('Manyezit', ['kutahya'], kategori: HaritaKategori.madenler),
  UrunEsleme('Antimon', ['kutahya'], kategori: HaritaKategori.madenler),
  UrunEsleme('Wolfram (tungsten)', ['bursa'], kategori: HaritaKategori.madenler),
  UrunEsleme('Toryum', ['eskisehir'], kategori: HaritaKategori.madenler),
  UrunEsleme('Zımpara Taşı', ['aydin'], kategori: HaritaKategori.madenler),
  UrunEsleme('Pomza (bims)', ['nevsehir'], kategori: HaritaKategori.madenler),
  UrunEsleme('Kükürt', ['isparta'], kategori: HaritaKategori.madenler),
  UrunEsleme('Asfaltit', ['sirnak'], kategori: HaritaKategori.madenler),
  // ── ENERJİ (kaynak/tesis) ──────────────────────────────────────────────
  UrunEsleme('Doğalgaz (çıkarım)', ['zonguldak'], kategori: HaritaKategori.enerji),
  UrunEsleme('Güneş Enerjisi (GES)', ['konya'], kategori: HaritaKategori.enerji),
  UrunEsleme('Rüzgâr Enerjisi (RES)', ['balikesir'], kategori: HaritaKategori.enerji),
  UrunEsleme('Jeotermal Enerji', ['aydin'], kategori: HaritaKategori.enerji),
  UrunEsleme('Petrol (çıkarım)', ['batman'], kategori: HaritaKategori.enerji),
  UrunEsleme('Petrol Rafinerisi', ['kocaeli'], kategori: HaritaKategori.enerji),
  UrunEsleme('Hidroelektrik (en büyük baraj)', ['sanliurfa'], kategori: HaritaKategori.enerji),
  UrunEsleme('Termik Santral (linyit)', ['manisa'], kategori: HaritaKategori.enerji),
  UrunEsleme('Nükleer Santral', ['mersin'], kategori: HaritaKategori.enerji),
  // ── SANAYİ & EL SANATLARI ──────────────────────────────────────────────
  UrunEsleme('Demir-Çelik Sanayii', ['hatay'], kategori: HaritaKategori.sanayi),
  UrunEsleme('Halı Dokumacılığı', ['gaziantep'], kategori: HaritaKategori.sanayi),
  UrunEsleme('Çini / Seramik', ['kutahya'], kategori: HaritaKategori.sanayi),
  UrunEsleme('Otomotiv', ['bursa'], kategori: HaritaKategori.sanayi),
  UrunEsleme('Tekstil', ['gaziantep'], kategori: HaritaKategori.sanayi),
  UrunEsleme('Beyaz Eşya', ['manisa'], kategori: HaritaKategori.sanayi),
  UrunEsleme('Petrokimya', ['izmir'], kategori: HaritaKategori.sanayi),
  UrunEsleme('Çimento', ['istanbul'], kategori: HaritaKategori.sanayi),
  UrunEsleme('Kâğıt', ['giresun'], kategori: HaritaKategori.sanayi),
  UrunEsleme('Şeker Fabrikaları', ['konya'], kategori: HaritaKategori.sanayi),
  UrunEsleme('Gübre', ['kocaeli'], kategori: HaritaKategori.sanayi),
  UrunEsleme('Tersane (gemi inşa)', ['yalova'], kategori: HaritaKategori.sanayi),
  UrunEsleme('Deri Sanayii', ['istanbul'], kategori: HaritaKategori.sanayi),
  UrunEsleme('Cam Sanayii', ['kirklareli'], kategori: HaritaKategori.sanayi),
  UrunEsleme('Savunma Sanayii', ['ankara'], kategori: HaritaKategori.sanayi),
  // ── COĞRAFYA & DOĞA (öğe adı ili ELE VERMEZ) ───────────────────────────
  UrunEsleme('Türkiye\'nin en yüksek dağı', ['agri'], kategori: HaritaKategori.cografya),
  UrunEsleme('Erciyes (volkanik dağ)', ['kayseri'], kategori: HaritaKategori.cografya),
  UrunEsleme('Çukurova (en büyük delta ovası)', ['adana'], kategori: HaritaKategori.cografya),
  UrunEsleme('Valla Kanyonu', ['kastamonu'], kategori: HaritaKategori.cografya),
  UrunEsleme('Peribacaları (Kapadokya)', ['nevsehir'], kategori: HaritaKategori.cografya),
  UrunEsleme('Obrukların en yaygın olduğu il', ['konya'], kategori: HaritaKategori.cografya),
  UrunEsleme('Karstik şekillerin (traverten) yaygın olduğu il', ['antalya'], kategori: HaritaKategori.cografya),
  UrunEsleme('En uzun nehir: Kızılırmak', ['sivas', 'samsun'], kategori: HaritaKategori.cografya),
  UrunEsleme('Türkiye\'nin en büyük gölü', ['van'], kategori: HaritaKategori.cografya),
  UrunEsleme('En büyük baraj (Atatürk Barajı)', ['sanliurfa'], kategori: HaritaKategori.cografya),
  UrunEsleme('Kula-Salihli Jeoparkı', ['manisa'], kategori: HaritaKategori.cografya),
  // ── ULAŞIM & TURİZM ────────────────────────────────────────────────────
  UrunEsleme('En büyük konteyner limanı', ['kocaeli', 'mersin'], kategori: HaritaKategori.ulasimTurizm),
  UrunEsleme('Göbeklitepe (ilk tapınak)', ['sanliurfa'], kategori: HaritaKategori.ulasimTurizm),
  UrunEsleme('Uludağ Kayak Merkezi', ['bursa'], kategori: HaritaKategori.ulasimTurizm),
  UrunEsleme('Termal / kaplıca turizmi merkezi', ['afyonkarahisar'], kategori: HaritaKategori.ulasimTurizm),
  UrunEsleme('Pamukkale travertenleri', ['denizli'], kategori: HaritaKategori.ulasimTurizm),
  UrunEsleme('İnanç turizmi (Balıklıgöl)', ['sanliurfa'], kategori: HaritaKategori.ulasimTurizm),
];

class UrunHaritasiScreen extends StatefulWidget {
  /// null ise TÜM kategorilerden karışık sorar; verilirse yalnızca o kategori
  /// (ör. HaritaKategori.tarim → Tarım Haritası).
  final HaritaKategori? kategori;
  const UrunHaritasiScreen({super.key, this.kategori});

  @override
  State<UrunHaritasiScreen> createState() => _UrunHaritasiScreenState();
}

class _UrunHaritasiScreenState extends State<UrunHaritasiScreen> {
  bool _locked = false;
  bool _booted = false;
  bool _finished = false;
  int _round = 0;
  int _score = 0;
  int _attempts = 0;
  late List<UrunEsleme> _queue;
  TurkeyProvince? _tapped;
  bool _showResult = false;
  String? _flashWrongId;
  final List<TurkeyProvince> _yanlisSecilen = [];
  DateTime? _sessionStart;

  /// Başlık/emoji: kategori verilmişse ona göre, yoksa genel "Ürün Haritası".
  String get _emoji =>
      widget.kategori != null ? haritaKategoriEmoji(widget.kategori!) : '🌾';
  String get _baslik =>
      widget.kategori != null ? haritaKategoriAd(widget.kategori!) : 'Ürün Haritası';

  @override
  void initState() {
    super.initState();
    _sessionStart = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    final start = _sessionStart;
    if (start != null) {
      context.read<StorageService>().addGameTimeSpent(kUrunHaritasiGameId, DateTime.now().difference(start));
    }
    super.dispose();
  }

  Future<void> _boot() async {
    final ok = await consumeMapGameDailyPlay(context);
    if (!mounted) return;
    if (!ok) {
      setState(() => _locked = true);
      return;
    }
    // Kategori verilmişse yalnızca o kategorinin öğelerinden sor (kullanıcı
    // isteği: tek oyun, soruya göre şehir çıksın).
    final havuz = widget.kategori == null
        ? kUrunEslemeleri
        : kUrunEslemeleri.where((e) => e.kategori == widget.kategori).toList();
    final pool = List<UrunEsleme>.from(havuz)..shuffle(Random());
    setState(() {
      _queue = pool.take(kUrunRounds).toList();
      _booted = true;
      _round = 0;
      _score = 0;
      _attempts = 0;
      _finished = false;
      // bkz. bolge_bul_mode.dart — retry sonrası bir önceki oyunun son
      // sonuç durumunun sızmaması için tur-bazlı alanlar burada da sıfırlanır.
      _showResult = false;
      _tapped = null;
      _flashWrongId = null;
    });
  }

  UrunEsleme get _target => _queue[_round];

  void _onTapProvince(TurkeyProvince p) {
    if (_showResult) return;
    context.read<SoundService>().click();
    if (_target.ilIds.contains(p.id)) {
      setState(() {
        _tapped = p;
        _showResult = true;
        _score++;
        context.read<StorageService>().addGameAnswer(kUrunHaritasiGameId, 'cografya', true);
      });
      return;
    }
    _attempts++;
    if (!_yanlisSecilen.any((x) => x.id == p.id)) _yanlisSecilen.add(p);
    context.read<StorageService>().addGameAnswer(kUrunHaritasiGameId, 'cografya', false);
    if (_attempts >= kMapMaxAttempts) {
      _kaydetYanlis();
      setState(() {
        _tapped = p;
        _showResult = true;
      });
    } else {
      _flashWrong(p.id);
      haritaYanlisAfis(context, kMapMaxAttempts - _attempts);
    }
  }

  void _kaydetYanlis() {
    if (_yanlisSecilen.isEmpty) return;
    final dogruId = _target.ilIds.isNotEmpty ? _target.ilIds.first : '';
    final dogruAd = dogruId.isEmpty
        ? ''
        : kTurkeyProvinces.firstWhere((p) => p.id == dogruId).ad;
    haritaYanlisKaydet(
      context,
      soru: '"${_target.urun}" → doğru ili işaretle',
      dogruId: dogruId,
      dogruAd: dogruAd,
      secilenIds: _yanlisSecilen.map((e) => e.id).toList(),
      secilenAdlar: _yanlisSecilen.map((e) => e.ad).toList(),
      modId: kUrunHaritasiGameId,
      modAd: 'Konu Haritası',
    );
  }

  /// Yanlış dokunulan ili kısa süreliğine kırmızı yakıp söndürür.
  void _flashWrong(String id) {
    setState(() => _flashWrongId = id);
    Future.delayed(const Duration(milliseconds: 550), () {
      if (mounted && _flashWrongId == id) setState(() => _flashWrongId = null);
    });
  }

  void _next() {
    context.read<SoundService>().click();
    if (_round + 1 >= _queue.length) {
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _round++;
      _yanlisSecilen.clear();
      _tapped = null;
      _showResult = false;
      _attempts = 0;
      _flashWrongId = null;
    });
  }

  void _retry() {
    setState(() {
      _booted = false;
      _locked = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return LockedFeatureCard(
        gameId: kMapGameId,
        oyunAdi: 'Harita Oyunu',
        onUnlocked: _retry,

        title: _baslik,
        desc: "Bugünkü $kFreeGameDailyLimit ücretsiz harita oyunu hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_finished) {
      return MapQuizResult(
        title: '$_emoji $_baslik',
        modeId: kUrunHaritasiGameId,
        score: _score,
        total: _queue.length,
        onRetry: _retry,
      );
    }
    return _buildRound(context);
  }

  Widget _buildRound(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final mapRenk = mapHighlightColor(context);
    return MapQuizScaffold(
      title: '$_emoji $_baslik',
      promptText: '"${_target.urun}" → doğru ili haritada işaretle!',
      statusText: 'Soru ${_round + 1}/${_queue.length} • Skor: $_score'
          '${_showResult ? "" : " • Hak: ${kMapMaxAttempts - _attempts}/$kMapMaxAttempts"}',
      palette: mapModePaletteFor(kUrunHaritasiGameId),
      howToPlay: _kHowToPlay,
      map: TurkeyMapCanvas(
        provinces: kTurkeyProvinces,
        colorFor: (p) {
          if (!_showResult) {
            if (p.id == _flashWrongId) return colors.danger;
            return mapRenk.withValues(alpha: 0.32);
          }
          if (_target.ilIds.contains(p.id)) return colors.success;
          if (p.id == _tapped?.id) return colors.danger;
          return colors.violet.withValues(alpha: 0.12);
        },
        onTap: _onTapProvince,
      ),
      feedback: _showResult ? _buildFeedback(colors) : null,
    );
  }

  Widget _buildFeedback(KpssColors colors) {
    final correct = _target.ilIds.contains(_tapped?.id);
    final correctNames = _target.ilIds.map((id) => kTurkeyProvinces.firstWhere((p) => p.id == id).ad).join(', ');
    return haritaSonucAfisi(
      context,
      dogru: correct,
      baslik: correct
          ? 'Doğru! "${_target.urun}": $correctNames'
          : '"${_target.urun}" ile öne çıkan il(ler): $correctNames',
      aciklama: (!correct && _yanlisSecilen.isNotEmpty)
          ? haritaYanlisSebebi(kUrunHaritasiGameId, correctNames,
              _yanlisSecilen.map((e) => e.ad).toList())
          : null,
      sonSoru: _round + 1 >= _queue.length,
      onNext: _next,
    );
  }
}
