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
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size.width <= 0 || size.height <= 0) return const SizedBox.shrink();

        final paths = <String, Path>{
          for (final g in geos) g.id: _buildPath(g, size),
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
                    left: (g.centroid.dx * size.width - 10).clamp(0.0, size.width - 20),
                    top: (g.centroid.dy * size.height - 10).clamp(0.0, size.height - 20),
                    child: IgnorePointer(child: overlays[g.id]!),
                  ),
            ],
          ),
        );
      },
    );
  }

  /// Bir ilin normalize edilmiş (0.0-1.0) poligon noktalarını verilen
  /// pixel boyutuna göre bir [Path]'e dönüştürür.
  static Path _buildPath(TurkeyProvinceGeo g, Size size) {
    final path = Path();
    for (var i = 0; i < g.points.length; i++) {
      final pt = g.points[i];
      final dx = pt.dx * size.width;
      final dy = pt.dy * size.height;
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
