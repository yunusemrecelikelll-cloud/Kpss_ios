import 'package:flutter/material.dart';
import '../data/turkey_geo_paths.dart';

/// Türkiye'nin 81 ilini GERÇEK il sınırı poligonlarıyla çizen, dokunulan
/// noktanın hangi ile denk geldiğini (`Path.contains`) bulan harita widget'ı.
///
/// Bu widget "Harita Oyunu" (bkz. lib/screens/map_game/map_shared.dart —
/// TurkeyMapCanvas bu widget'ı sarmalar) ve "Haritadan Öğren" kütüphanesi
/// (bkz. lib/screens/learn_map/) tarafından ORTAK kullanılır. Poligon verisi
/// lib/data/turkey_geo_paths.dart'tan (gerçek coğrafi sınırlar, bkz. o
/// dosyanın başlığındaki kaynak notu) gelir; il meta verisi (bölge, komşular,
/// ürünler vb.) İÇERMEZ — sadece id bazlı çizim/hit-test yapar. Renk/etiket
/// gibi anlam katmanları dışarıdan [fillColors]/[overlays] ile beslenir.
class TurkeyMapWidget extends StatelessWidget {
  /// il id -> dolgu rengi. Haritada gösterilecek TÜM iller için burada bir
  /// renk beklenir; eksik olan iller [defaultFillColor] ile boyanır.
  final Map<String, Color> fillColors;
  final Color defaultFillColor;
  final Color borderColor;
  final double borderWidth;

  /// Opaklığı düşürülecek (örn. henüz fethedilmemiş/pasif) il id'leri.
  final Set<String> dimmedIds;

  /// il id -> küçük bir overlay widget (rozet/ikon), ilin ağırlık merkezine
  /// (centroid) yerleştirilir. Örn. 81 İl Fethi modundaki 👑/🔒 işaretleri.
  final Map<String, Widget> overlays;

  /// Bir ile dokunulduğunda çağrılır (il id'si ile). null ise harita
  /// dokunmaya kapalıdır (salt gösterim/"Haritadan Öğren" modu gibi).
  final void Function(String id)? onProvinceTap;

  /// Çizilecek il poligon listesi — varsayılan olarak Türkiye'nin 81 ilinin
  /// tamamı. Alt küme geçilirse sadece o iller çizilir (ör. tek bir bölge).
  final List<TurkeyProvinceGeo> geos;

  const TurkeyMapWidget({
    super.key,
    required this.fillColors,
    this.defaultFillColor = const Color(0xFFB0BEC5),
    this.borderColor = const Color(0x40222222),
    this.borderWidth = 1.0,
    this.dimmedIds = const {},
    this.overlays = const {},
    this.onProvinceTap,
    this.geos = kTurkeyProvinceGeoList,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth;
        // Yükseklik sınırsız gelirse (ör. kaydırılabilir bir Column içinde)
        // haritanın kendi en/boy oranından türetilen yükseklik kullanılır.
        final availH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : availW / kTurkeyMapAspectRatio;
        if (availW <= 0 || availH <= 0) return const SizedBox.shrink();

        // ÖNEMLİ (düzeltilen hata): Eskiden poligonlar doğrudan kullanılabilir
        // alanın TAMAMINA (genişlik × yükseklik) esnetiliyordu; alanın en/boy
        // oranı haritanınkinden farklı olduğunda (ör. "Haritadan Öğren"deki
        // uzun/dar alan) Türkiye şekli YAYVANLAŞIP SIKIŞIYORDU. Artık harita
        // BoxFit.contain gibi davranır: gerçek en/boy oranı [kTurkeyMapAspectRatio]
        // KORUNUR, alana sığdırılır ve ortalanır. Artan boşluk ŞEFFAF bırakılır
        // (arka planda beyaz bir dolgu ÇİZİLMEZ).
        var mapW = availW;
        var mapH = mapW / kTurkeyMapAspectRatio;
        if (mapH > availH) {
          mapH = availH;
          mapW = mapH * kTurkeyMapAspectRatio;
        }
        final origin = Offset((availW - mapW) / 2, (availH - mapH) / 2);
        final mapSize = Size(mapW, mapH);
        final size = Size(availW, availH);

        final paths = <String, Path>{
          for (final g in geos) g.id: _buildPath(g, mapSize, origin),
        };

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: onProvinceTap == null
              ? null
              : (details) {
                  final pos = details.localPosition;
                  for (final g in geos) {
                    final path = paths[g.id];
                    if (path != null && path.contains(pos)) {
                      onProvinceTap!(g.id);
                      return;
                    }
                  }
                },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: size,
                painter: _TurkeyMapPainter(
                  geos: geos,
                  paths: paths,
                  fillColors: fillColors,
                  defaultFillColor: defaultFillColor,
                  dimmedIds: dimmedIds,
                  borderColor: borderColor,
                  borderWidth: borderWidth,
                ),
              ),
              for (final g in geos)
                if (overlays[g.id] != null)
                  Positioned(
                    left: (origin.dx + g.centroid.dx * mapW - 10).clamp(0.0, availW - 20),
                    top: (origin.dy + g.centroid.dy * mapH - 10).clamp(0.0, availH - 20),
                    child: IgnorePointer(child: overlays[g.id]!),
                  ),
            ],
          ),
        );
      },
    );
  }

  /// Bir ilin normalize edilmiş (0.0-1.0) poligon noktalarını, en/boy oranı
  /// korunarak hesaplanmış [mapSize] kutusuna ve [origin] kaymasına göre bir
  /// [Path]'e dönüştürür.
  static Path _buildPath(TurkeyProvinceGeo g, Size mapSize, Offset origin) {
    final path = Path();
    for (var i = 0; i < g.points.length; i++) {
      final pt = g.points[i];
      final dx = origin.dx + pt.dx * mapSize.width;
      final dy = origin.dy + pt.dy * mapSize.height;
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }
    path.close();
    return path;
  }
}

class _TurkeyMapPainter extends CustomPainter {
  final List<TurkeyProvinceGeo> geos;
  final Map<String, Path> paths;
  final Map<String, Color> fillColors;
  final Color defaultFillColor;
  final Set<String> dimmedIds;
  final Color borderColor;
  final double borderWidth;

  _TurkeyMapPainter({
    required this.geos,
    required this.paths,
    required this.fillColors,
    required this.defaultFillColor,
    required this.dimmedIds,
    required this.borderColor,
    required this.borderWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..color = borderColor;

    for (final g in geos) {
      final path = paths[g.id];
      if (path == null) continue;
      final baseColor = fillColors[g.id] ?? defaultFillColor;
      final dim = dimmedIds.contains(g.id);
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = dim ? baseColor.withValues(alpha: baseColor.a * 0.4) : baseColor;
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TurkeyMapPainter oldDelegate) {
    return oldDelegate.fillColors != fillColors ||
        oldDelegate.dimmedIds != dimmedIds ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.geos != geos;
  }
}
