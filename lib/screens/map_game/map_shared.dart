import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/turkey_geo_paths.dart';
import '../../data/turkey_map_data.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/subject_colors.dart';
import '../../theme/theme_provider.dart';
import '../../widgets/turkey_map_painter.dart';
// Sonuç ekranı TÜM oyunlarda ortak olsun diye Hızlı Modlar'daki
// [GameResultScreen] burada da kullanılır (tek tasarım dili, tek yer).
import '../quick_modes/quick_modes_shared.dart';
import '../tools_hub_screen.dart';

/// Harita Oyunu — JS karşılığı yok (yeni Flutter-özel oyun), diğer oyunlarla
/// (Solitaire/Kart Oyunu V2) aynı günlük hak/ilerleme desenini kullanır.
///
/// ÖNEMLİ: "81 İl Fethi" modu bu günlük sayaca TABİ DEĞİLDİR — kullanıcı
/// istediği kadar il fethedebilir. Diğer tüm mini oyun modları (İli Bul,
/// Bölgeyi Bul, Komşu İl, Ürün Haritası, Tarih Haritası, İklim Avı, 60
/// Saniyede Türkiye) TEK bir ortak sayaç üzerinden günlük [kFreeGameDailyLimit]
/// hakkına tabidir.
const String kMapGameId = 'haritaoyunu';

/// Haritada doğrudan bir ile dokunarak cevaplanan mini oyun modlarında
/// (İli Bul, Bölgeyi Bul, Komşu İl, Ürün/Tarih Haritası, İklim Avı) her soru
/// için tanınan deneme hakkı — kullanıcı 3 kez yanlış dokunursa doğru cevap
/// gösterilip bir sonraki soruya geçilir.
const int kMapMaxAttempts = 3;

/// Bölgelere göre ayırt edici renk paleti — Bölgeyi Bul modunda ve genel
/// harita gösteriminde kullanılır.
const Map<String, Color> kRegionColors = {
  'Marmara': Color(0xFF3B82F6),
  'Ege': Color(0xFF22C55E),
  'Akdeniz': Color(0xFFF59E0B),
  'İç Anadolu': Color(0xFFA855F7),
  'Karadeniz': Color(0xFF0891B2),
  'Doğu Anadolu': Color(0xFFEF4444),
  'Güneydoğu Anadolu': Color(0xFFEA580C),
};

Color regionColor(String bolge) => kRegionColors[bolge] ?? Colors.grey;

// ── Harita oyunu modlarının kimlikleri (oyun-bazlı SÜRE takibi için) ──
// NOT: Bunlar [kMapGameId] (günlük ORTAK oynama hakkı sayacı) ile KARIŞTIRILMAMALI
// — her modun burada AYRI bir kimliği var, çünkü "hangi modda ne kadar zaman
// geçirdin" istatistiği mod bazında tutulur (bkz. StorageService.addGameTimeSpent).
const String kIliBulGameId = 'map_ili_bul';
const String kBolgeBulGameId = 'map_bolge_bul';
const String kKomsuIlGameId = 'map_komsu_il';
const String kUrunHaritasiGameId = 'map_urun_haritasi';
const String kTarihHaritasiGameId = 'map_tarih_haritasi';
const String kIklimAviGameId = 'map_iklim_avi';
const String kHizliTurkiyeGameId = 'map_hizli_turkiye';
const String kIlFethiTimeGameId = 'map_il_fethi';
const String kHaritadanOgrenGameId = 'map_haritadan_ogren';

/// Harita oyunu hub'ında ve her modun kendi ekranında gösterilen tüm mod
/// kimlikleri — hub'daki "toplam süre" özetini hesaplamak için kullanılır.
const List<String> kAllMapModeIds = [
  kIliBulGameId,
  kBolgeBulGameId,
  kKomsuIlGameId,
  kUrunHaritasiGameId,
  kTarihHaritasiGameId,
  kIklimAviGameId,
  kHizliTurkiyeGameId,
  kIlFethiTimeGameId,
  kHaritadanOgrenGameId,
];

/// Her harita modu için ayırt edici, canlı bir renk paleti — bkz.
/// lib/theme/subject_colors.dart `SubjectPalette`/`subjectCardDecoration`
/// deseninin AYNISI, sadece ders id'si yerine harita-modu id'si ile anahtarlanır
/// (dersler ve harita modları birebir örtüşmediği için ayrı bir küçük palet).
const Map<String, SubjectPalette> kMapModePalettes = {
  kIliBulGameId: SubjectPalette(Color(0xFF38BDF8), Color(0xFF6366F1)), // gökyüzü mavisi → indigo
  kBolgeBulGameId: SubjectPalette(Color(0xFFA855F7), Color(0xFFEC4899)), // mor → pembe (7 bölge çeşitliliği)
  kKomsuIlGameId: SubjectPalette(Color(0xFFFB923C), Color(0xFFFACC15)), // turuncu → altın (komşuluk sıcaklığı)
  kUrunHaritasiGameId: SubjectPalette(Color(0xFF65A30D), Color(0xFFF59E0B)), // hasat yeşili → amber
  kTarihHaritasiGameId: SubjectPalette(Color(0xFFB45309), Color(0xFF78350F)), // amber → kahve (tarih)
  kIklimAviGameId: SubjectPalette(Color(0xFF0EA5E9), Color(0xFF7DD3FC)), // gökyüzü/deniz mavisi
  kHizliTurkiyeGameId: SubjectPalette(Color(0xFFEF4444), Color(0xFFF97316)), // kırmızı → turuncu (hız/aciliyet)
  kIlFethiTimeGameId: SubjectPalette(Color(0xFFF59E0B), Color(0xFFE11D48)), // altın → gül (bayrak mod, flagship kartla uyumlu)
  kHaritadanOgrenGameId: SubjectPalette(Color(0xFF10B981), Color(0xFF0D9488)), // yeşil → deniz mavisi (öğrenme/kitap)
};

const SubjectPalette _kFallbackMapPalette = SubjectPalette(Color(0xFF8B5CF6), Color(0xFFF472B6));

SubjectPalette mapModePaletteFor(String modeId) => kMapModePalettes[modeId] ?? _kFallbackMapPalette;

/// [MapQuizScaffold]/mod ekranlarının arka planına uygulanan hafif, tema-duyarlı
/// gradyan yıkaması — subject_colors.dart'taki `subjectCardDecoration` ile AYNI
/// ruhta ama kart değil TAM EKRAN arka planı için daha düşük alpha kullanır.
BoxDecoration mapModeBackgroundDecoration(SubjectPalette palette, bool isLight) {
  final alphaA = isLight ? 0.10 : 0.16;
  final alphaB = isLight ? 0.04 : 0.08;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [palette.a.withValues(alpha: alphaA), palette.b.withValues(alpha: alphaB)],
    ),
  );
}

// NOT: Süre biçimlendirme için AYRI bir yardımcı EKLENMEDİ — tools_hub_screen.dart
// zaten genel amaçlı bir `formatPlayDuration(int totalSeconds)` fonksiyonu
// tanımlıyor (Kart Oyunu/Balon Patlat/Hız 60/Düello'nun "toplam ... oynadın"
// etiketlerinde kullanılan AYNI fonksiyon) ve bu dosya zaten tools_hub_screen.dart'ı
// import ediyor — harita modları da TUTARLILIK için o fonksiyonu kullanır
// (bkz. map_game_screen.dart). İkinci bir aynı-isimli fonksiyon tanımlamak,
// hem map_shared.dart HEM tools_hub_screen.dart'ı birlikte import eden mod
// dosyalarında (hepsi) "ambiguous import" derleme hatasına yol açardı.

/// Bir harita modunun AppBar'ına eklenen "❓ Nasıl oynanır?" butonunun açtığı
/// kısa kural özeti — kullanıcı oyundan hiç çıkmadan (bkz. görev talimatı)
/// kuralları hatırlayabilsin diye bir bottom sheet olarak gösterilir.
Future<void> showHowToPlaySheet(BuildContext context, {required String title, required String body}) {
  final colors = context.read<ThemeProvider>().colors;
  return showModalBottomSheet(
    context: context,
    backgroundColor: colors.glass2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('❓', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nasıl Oynanır? — $title',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(body, style: TextStyle(fontSize: 13.5, height: 1.5, color: colors.text)),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Anladım'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Bir mini-oyun oturumu başlatmadan önce günlük hakkı kontrol eder; premium
/// kullanıcılar ya da hakkı kalanlar için hakkı düşürüp true döner, hakkı
/// bitmiş ücretsiz kullanıcılar için false döner (çağıran taraf
/// [LockedFeatureCard] göstermelidir). NOT: "81 İl Fethi" modu bunu ASLA
/// çağırmaz.
Future<bool> consumeMapGameDailyPlay(BuildContext context) async {
  final storage = context.read<StorageService>();
  if (storage.isPremiumUser()) return true;
  final gp = storage.getGamePlayState(kMapGameId);
  if ((gp['plays'] as int) >= kFreeGameDailyLimit + storage.getExtraPlays(kMapGameId)) return false;
  await storage.useGamePlay(kMapGameId);
  return true;
}

/// Kalan günlük hak sayısını hesaplar (UI'da gösterim için).
int mapGameDailyLeft(StorageService storage) {
  final gp = storage.getGamePlayState(kMapGameId);
  return (kFreeGameDailyLimit - (gp['plays'] as int)).clamp(0, kFreeGameDailyLimit);
}

/// Haritanın GERÇEK en/boy oranı — il sınırı poligonlarının kapladığı
/// coğrafi alandan hesaplanmıştır (bkz. lib/data/turkey_geo_paths.dart).
const double kMapAspectRatio = kTurkeyMapAspectRatio;

typedef ProvinceColorFn = Color Function(TurkeyProvince p);
typedef ProvinceOverlayFn = Widget? Function(TurkeyProvince p);

/// Türkiye'nin 81 ilini GERÇEK il sınırı poligonlarıyla gösteren harita.
/// Eskiden normX/normY'ye göre yerleştirilmiş şematik yuvarlak düğmeler
/// kullanılıyordu; artık [TurkeyMapWidget] (bkz. lib/widgets/turkey_map_painter.dart)
/// gerçek coğrafi sınırları çizip dokunulan noktayı `Path.contains` ile
/// hangi ile denk geldiğini bulur. Bu sınıfın DIŞARIYA açık API'si (provinces,
/// colorFor, overlayFor, onTap, dimmed) DEĞİŞMEDİ — tüm mod ekranları
/// (İli Bul, 81 İl Fethi, Bölgeyi Bul, Komşu İl, Ürün/Tarih Haritası, İklim
/// Avı, 60 Saniyede Türkiye) bu widget'ı olduğu gibi kullanmaya devam eder.
/// InteractiveViewer ile sarmalanarak temel bir pinch-zoom/pan imkânı sunulur.
class TurkeyMapCanvas extends StatefulWidget {
  final List<TurkeyProvince> provinces;
  final ProvinceColorFn colorFor;
  final ProvinceOverlayFn? overlayFor;
  final void Function(TurkeyProvince p)? onTap;
  final Set<String> dimmed;

  const TurkeyMapCanvas({
    super.key,
    required this.provinces,
    required this.colorFor,
    this.overlayFor,
    this.onTap,
    this.dimmed = const {},
  });

  @override
  State<TurkeyMapCanvas> createState() => _TurkeyMapCanvasState();
}

class _TurkeyMapCanvasState extends State<TurkeyMapCanvas> with SingleTickerProviderStateMixin {
  // ── Yakınlaşma/uzaklaşma (zoom) davranışı ──────────────────────────────
  // ÖNEMLİ (düzeltilen hata): Eskiden `constrained: false` kullanılıyordu.
  // Bu modda InteractiveViewer çocuğu SINIRSIZ ölçüyle yerleştirir ve dahili
  // sınır (boundary) matematiği viewport ile çocuğun ölçüsünü karıştırdığından
  // harita "büyüyor ama bir daha küçülmüyor" ve büyürken sıçramalı/dengesiz
  // davranıyordu. Artık:
  //   (1) `constrained: true` (varsayılan) — viewport = çocuk, sınır
  //       matematiği tutarlı; ölçek her iki yönde de serbestçe değişebilir,
  //   (2) `boundaryMargin` cömert tutuldu ki içeri/dışarı sıkışma olmasın,
  //   (3) parmak kaldırıldığında ölçek 1.0'a çok yaklaşmışsa harita YUMUŞAK
  //       bir animasyonla tam oturmuş hâline geri döner (küçültememe hatasına
  //       karşı garantili çıkış yolu),
  //   (4) çift dokunuş, dokunulan noktayı merkez alarak KADEMELİ (animasyonlu)
  //       yakınlaştırır; zaten yakınlaşmışsa aynı animasyonla sıfırlar.
  static const double _kMinScale = 1.0;
  static const double _kMaxScale = 4.0;
  static const double _kDoubleTapScale = 2.4;
  static const Duration _kZoomDuration = Duration(milliseconds: 260);

  final _controller = TransformationController();
  late final AnimationController _anim;
  Animation<Matrix4>? _zoomAnimation;
  Offset? _doubleTapPos;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: _kZoomDuration)
      ..addListener(() {
        final a = _zoomAnimation;
        if (a != null) _controller.value = a.value;
      });
  }

  /// Mevcut dönüşümden [target] dönüşüme yumuşak (kademeli) geçiş.
  void _animateTo(Matrix4 target) {
    _zoomAnimation = Matrix4Tween(begin: _controller.value, end: target)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward(from: 0);
  }

  void _resetZoom() => _animateTo(Matrix4.identity());

  double get _scale => _controller.value.getMaxScaleOnAxis();

  void _handleDoubleTap() {
    // Zaten yakınlaşmışsa sıfırla, değilse dokunulan noktaya yaklaş.
    if (_scale > _kMinScale + 0.05) {
      _resetZoom();
      return;
    }
    final pos = _doubleTapPos;
    if (pos == null) {
      _resetZoom();
      return;
    }
    const s = _kDoubleTapScale;
    // Dokunulan nokta sabit kalsın: s * p + t = p  →  t = -p * (s - 1)
    _animateTo(Matrix4.identity()
      ..translateByDouble(-pos.dx * (s - 1), -pos.dy * (s - 1), 0, 1)
      ..scaleByDouble(s, s, 1, 1));
  }

  /// Parmak kaldırıldığında ölçek tam oturmuş hâle çok yakınsa küçük
  /// kaymaları temizleyip haritayı tam oturmuş hâline geri yaslar.
  void _snapIfNearFit() {
    if (_scale <= _kMinScale + 0.02) {
      final m = _controller.value;
      if (m != Matrix4.identity()) _animateTo(Matrix4.identity());
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final byId = {for (final p in widget.provinces) p.id: p};
    final geos = kTurkeyProvinceGeoList.where((g) => byId.containsKey(g.id)).toList();
    final fillColors = <String, Color>{
      for (final g in geos) g.id: widget.colorFor(byId[g.id]!),
    };
    final overlays = <String, Widget>{
      if (widget.overlayFor != null)
        for (final g in geos)
          if (widget.overlayFor!(byId[g.id]!) != null) g.id: widget.overlayFor!(byId[g.id]!)!,
    };
    // NOT: Haritanın arkasında ARTIK beyaz/`glass` bir dolgu ve çerçeve YOK —
    // kullanıcı "haritanın etrafındaki beyazlığı kaldır" dedi. Harita kendi
    // en/boy oranını koruyup alana ortalandığı için (bkz. TurkeyMapWidget)
    // artan boşluk şeffaf kalır ve ekranın tema gradyanı görünür.
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
              onDoubleTap: _handleDoubleTap,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: _kMinScale,
                maxScale: _kMaxScale,
                boundaryMargin: const EdgeInsets.all(48),
                onInteractionStart: (_) {
                  if (_anim.isAnimating) _anim.stop();
                },
                onInteractionEnd: (_) => _snapIfNearFit(),
                child: TurkeyMapWidget(
                  geos: geos,
                  fillColors: fillColors,
                  defaultFillColor: colors.violet.withValues(alpha: 0.15),
                  borderColor: colors.border,
                  dimmedIds: widget.dimmed,
                  overlays: overlays,
                  onProvinceTap: widget.onTap == null
                      ? null
                      : (id) {
                          final p = byId[id];
                          if (p == null) return;
                          context.read<SoundService>().click();
                          widget.onTap!(p);
                        },
                ),
              ),
            ),
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: Material(
              color: colors.glass2,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Yakınlaştırmayı sıfırla',
                icon: Icon(Icons.zoom_out_map, size: 18, color: colors.text),
                onPressed: _resetZoom,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini oyun modlarının ortak "soru üstte, harita altta, sonuç banner'ı"
/// iskeleti. Skor/can göstergesi ve geri bildirim banner'ı burada, harita
/// [child] olarak geçirilir.
class MapQuizScaffold extends StatelessWidget {
  final String title;
  final String promptText;
  final String statusText;
  final Widget map;
  final Widget? feedback;
  /// Bu modun renk kimliği — verilirse Scaffold gövdesine hafif bir gradyan
  /// arka plan yıkaması uygulanır (bkz. map_shared.dart `kMapModePalettes`).
  final SubjectPalette? palette;
  /// Verilirse AppBar'a bir "❓ Nasıl oynanır?" butonu eklenir (bkz.
  /// [showHowToPlaySheet]) — kullanıcı oyundan çıkmadan kuralları görebilir.
  final String? howToPlay;
  const MapQuizScaffold({
    super.key,
    required this.title,
    required this.promptText,
    required this.statusText,
    required this.map,
    this.feedback,
    this.palette,
    this.howToPlay,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (howToPlay != null)
            IconButton(
              tooltip: 'Nasıl oynanır?',
              icon: const Icon(Icons.help_outline),
              onPressed: () => showHowToPlaySheet(context, title: title, body: howToPlay!),
            ),
        ],
      ),
      body: Container(
        decoration: palette != null ? mapModeBackgroundDecoration(palette!, colors.isLight) : null,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(promptText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(statusText, style: TextStyle(fontSize: 12.5, color: colors.textFaint)),
                const SizedBox(height: 10),
                Expanded(child: map),
                if (feedback != null) ...[
                  const SizedBox(height: 10),
                  // ÖNEMLİ (düzeltilen hata — bkz. Ürün Haritası): geri bildirim
                  // kartının içeriği (ör. birden fazla il adı sıralanan "İl(ler):"
                  // metni) uzadığında, üstteki Expanded(map) haritayı olabildiğince
                  // küçültse bile Column'un TOPLAM yüksekliği ekranı aşabiliyor ve
                  // kartın ALT kısmındaki metin/buton ekranın dışına taşıp
                  // görünmez oluyordu. Artık geri bildirim alanı ekran
                  // yüksekliğinin bir kısmıyla SINIRLANIYOR ve gerekirse kendi
                  // içinde KAYDIRILABİLİYOR — böylece hiçbir metin asla kırpılmaz.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.34),
                    child: SingleChildScrollView(child: feedback!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Soru-cevap tipli harita modlarının (İli Bul, Bölgeyi Bul, Komşu İl, Ürün
/// Haritası, Tarih Haritası, İklim Avı) ORTAK sonuç ekranı.
///
/// Hepsi "N sorudan M tanesini doğru bildin" biçiminde bittiği için başarı
/// emojisi, başlık, doğru/yanlış/isabet şeridi ve arka plan tek yerden üretilir
/// — böylece bir modda yapılan iyileştirme hepsine birden yansır.
class MapQuizResult extends StatelessWidget {
  final String title;

  /// Modun kimliği — rengi ([kMapModePalettes]) buradan gelir.
  final String modeId;
  final int score;
  final int total;
  final VoidCallback onRetry;

  const MapQuizResult({
    super.key,
    required this.title,
    required this.modeId,
    required this.score,
    required this.total,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final yanlis = (total - score).clamp(0, total);
    final oran = total <= 0 ? 0 : (score * 100 / total).round();
    // Başarıya göre illüstrasyon: kusursuz tur 🏆, iyi tur 🎉, orta 💪, düşük 📚.
    final String emoji;
    final String baslik;
    if (total > 0 && score == total) {
      emoji = '🏆';
      baslik = 'Kusursuz tur!';
    } else if (oran >= 70) {
      emoji = '🎉';
      baslik = 'Harika iş!';
    } else if (oran >= 40) {
      emoji = '💪';
      baslik = 'Fena değil!';
    } else {
      emoji = '📚';
      baslik = 'Biraz daha çalışmalısın';
    }

    return MapSessionResult(
      title: title,
      emoji: emoji,
      headline: baslik,
      message: '$total sorudan $score tanesini doğru bildin.',
      stats: [
        GameResultStat(emoji: '✅', value: '$score', label: 'Doğru', color: colors.success),
        GameResultStat(emoji: '❌', value: '$yanlis', label: 'Yanlış', color: colors.danger),
        GameResultStat(emoji: '🎯', value: '%$oran', label: 'İsabet'),
      ],
      onRetry: onRetry,
      palette: mapModePaletteFor(modeId),
    );
  }
}

/// Genel bir "oturum bitti" sonuç kartı — TÜM harita modlarının (İli Bul,
/// Bölgeyi Bul, Komşu İl, Ürün/Tarih Haritası, İklim Avı, 60 Saniyede Türkiye)
/// ortak sonuç ekranı.
///
/// Artık kendi düzenini çizmez; Hızlı Modlar ve Kart Oyunu ile AYNI tasarım
/// dilini kullanan ortak [GameResultScreen]'i sarmalar (bkz.
/// quick_modes/quick_modes_shared.dart). Modun kendi rengi ([palette]) hem
/// arka plan gradyanına hem butonlara vurgu olarak geçer.
class MapSessionResult extends StatelessWidget {
  final String title;
  final String emoji;

  /// Kısa değerlendirme cümlesi ("5 sorudan 4 tanesini doğru bildin." gibi).
  final String message;

  /// Büyük başlık — verilmezse "Oturum Bitti!".
  final String? headline;

  /// [DsStatStrip] ile gösterilecek sayısal özet.
  final List<GameResultStat> stats;

  /// Kalıcı rekor (yalnızca rekor tutan modlarda verilir — ör. 60 Saniyede
  /// Türkiye). null ise rekor satırı çizilmez.
  final int? highScore;
  final bool newRecord;

  /// Uzun "neye çalışmalısın" yorumu.
  final String? note;

  final VoidCallback onRetry;
  final SubjectPalette? palette;

  /// Butonların etiketleri ve geri dönüş davranışı — 81 İl Fethi gibi haritaya
  /// sonuç döndüren modlar bunları özelleştirir.
  final String retryLabel;
  final String backLabel;
  final VoidCallback? onBack;

  const MapSessionResult({
    super.key,
    required this.title,
    required this.emoji,
    required this.message,
    required this.onRetry,
    this.headline,
    this.stats = const [],
    this.highScore,
    this.newRecord = false,
    this.note,
    this.palette,
    this.retryLabel = 'Tekrar Oyna',
    this.backLabel = 'Oyunlara Dön',
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    return GameResultScreen(
      title: title,
      emoji: emoji,
      headline: headline ?? 'Oturum Bitti!',
      message: message,
      stats: stats,
      highScore: highScore,
      newRecord: newRecord,
      note: note,
      accent: palette?.a,
      backgroundDecoration:
          palette != null ? mapModeBackgroundDecoration(palette!, colors.isLight) : null,
      onRetry: onRetry,
      retryLabel: retryLabel,
      backLabel: backLabel,
      onBack: onBack,
    );
  }
}
