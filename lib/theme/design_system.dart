import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'theme_provider.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// KPSS Hazırlık — ortak tasarım sistemi
/// ─────────────────────────────────────────────────────────────────────────
///
/// Uygulamanın TAMAMI bu dosyadaki yapı taşlarını kullanır. Amaç, her ekranda
/// yeniden `Container(decoration: BoxDecoration(...))` yazmak yerine aynı
/// köşe yarıçapı, aynı kenarlık, aynı gölge, aynı iç boşluk ve aynı tipografi
/// ölçeğinin tek yerden gelmesi.
///
/// RENKLER: Buradaki hiçbir bileşen sabit renk barındırmaz — hepsi
/// [KpssColors] token'larından (bkz. app_theme.dart) ya da çağıranın verdiği
/// vurgu renginden türer. Böylece 9 temanın hepsinde ve hem açık hem koyu
/// modda tutarlı çalışır.
///
/// İLLÜSTRASYONLAR: Tasarımdaki 3B görseller (kum saati, roket, kupa, taç,
/// klasör) için [DsIllustration] bir YUVA görevi görür. Projede henüz görsel
/// dosyası yok; asset verilmediğinde bileşen otomatik olarak büyük bir emoji +
/// yumuşak ışıma çizer. Görseller hazırlandığında yapılacak tek şey:
///   1) `assets/images/` klasörünü oluştur, PNG'leri koy
///   2) pubspec.yaml > flutter > assets altına `- assets/images/` ekle
///   3) İlgili ekranda `DsIllustration(emoji: '🚀', asset: 'assets/images/roket.png')`
/// Kodun geri kalanı hiç değişmez.

// ── Ölçü sabitleri ────────────────────────────────────────────────────────

/// Kart köşe yarıçapı — tasarımdaki tüm büyük yüzeyler bunu kullanır.
const double kDsRadius = 20;

/// Rozet / küçük yüzey köşe yarıçapı.
const double kDsRadiusSm = 14;

/// Kartların standart iç boşluğu.
const EdgeInsets kDsCardPadding = EdgeInsets.all(16);

/// Dikey listelerde kartlar arası boşluk.
const double kDsGap = 12;

/// ── Kart ──────────────────────────────────────────────────────────────────
///
/// Tasarımdaki temel yüzey: yumuşak cam zemin, ince kenarlık, 20px köşe.
/// [accent] verilirse kart o renge boyanmış (tint + kenarlık + hafif ışıma)
/// vurgulu bir karta dönüşür — Premium kartı gibi.
class DsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? accent;

  /// Dolu degrade zemin (Tam Deneme / Düello kartları gibi). Verilirse
  /// [accent] tint'i yerine bu degrade kullanılır.
  final Gradient? gradient;
  final VoidCallback? onTap;

  const DsCard({
    super.key,
    required this.child,
    this.padding,
    this.accent,
    this.gradient,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final vurgu = accent;

    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(kDsRadius),
      gradient: gradient,
      color: gradient != null
          ? null
          : (vurgu != null ? vurgu.withValues(alpha: c.isLight ? 0.07 : 0.10) : c.glass),
      border: Border.all(
        color: vurgu != null
            ? vurgu.withValues(alpha: c.isLight ? 0.35 : 0.45)
            : c.border,
        width: vurgu != null ? 1.4 : 1,
      ),
      boxShadow: vurgu != null
          ? [
              BoxShadow(
                color: vurgu.withValues(alpha: c.isLight ? 0.14 : 0.22),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ]
          : null,
    );

    final govde = Padding(padding: padding ?? kDsCardPadding, child: child);

    if (onTap == null) {
      return Container(decoration: decoration, child: govde);
    }
    // Dokunma dalgası köşeleri taşmasın diye Material+InkWell, Container'ın
    // İÇİNDE ve aynı yarıçapla kırpılmış halde duruyor.
    return Container(
      decoration: decoration,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kDsRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(kDsRadius),
          onTap: onTap,
          child: govde,
        ),
      ),
    );
  }
}

/// ── İkon rozeti ───────────────────────────────────────────────────────────
///
/// Tasarımdaki sol taraf ikonları: yuvarlak (banner kartları) ya da
/// yuvarlatılmış kare (liste satırları) zemin üzerinde emoji veya Material
/// ikonu. [glow] açıkken rozetin etrafına renkten türeyen yumuşak bir ışıma
/// düşer (giriş/taç/hedef rozetlerindeki etki).
class DsIconBadge extends StatelessWidget {
  final String? emoji;
  final IconData? icon;
  final Color color;
  final double size;
  final bool circle;
  final bool glow;

  const DsIconBadge({
    super.key,
    this.emoji,
    this.icon,
    required this.color,
    this.size = 52,
    this.circle = true,
    this.glow = true,
  }) : assert(emoji != null || icon != null, 'emoji ya da icon verilmeli');

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(kDsRadiusSm),
        color: color.withValues(alpha: c.isLight ? 0.12 : 0.16),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.2),
        boxShadow: glow
            ? [BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 14)]
            : null,
      ),
      child: icon != null
          ? Icon(icon, color: color, size: size * 0.46)
          : Text(emoji!, style: TextStyle(fontSize: size * 0.42)),
    );
  }
}

/// ── İllüstrasyon yuvası ───────────────────────────────────────────────────
///
/// Tasarımdaki 3B görsellerin yeri. [asset] verilmişse onu çizer; verilmemişse
/// (şu anki durum) büyük emojiyi radyal bir ışımanın üstünde gösterir.
/// Asset bulunamazsa da sessizce emojiye düşer — eksik dosya uygulamayı
/// çökertmez.
class DsIllustration extends StatelessWidget {
  final String emoji;
  final String? asset;
  final double size;
  final Color glowColor;

  const DsIllustration({
    super.key,
    required this.emoji,
    this.asset,
    this.size = 84,
    required this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Görselin arkasındaki yumuşak ışıma — 3B render'ların altındaki
          // parlama hissini taklit eder.
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  glowColor.withValues(alpha: 0.30),
                  glowColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          if (asset != null)
            Image.asset(
              asset!,
              width: size * 0.92,
              height: size * 0.92,
              fit: BoxFit.contain,
              // Asset henüz eklenmemişse emojiye düş.
              errorBuilder: (_, _, _) => _emojiChild(),
            )
          else
            _emojiChild(),
        ],
      ),
    );
  }

  Widget _emojiChild() => Text(emoji, style: TextStyle(fontSize: size * 0.52));
}

/// ── Hap (pill) buton ──────────────────────────────────────────────────────
///
/// Tasarımdaki iki buton tipi: dolu (birincil eylem) ve dış çizgili (ikincil).
/// [gradient] verilirse dolu buton degradeye boyanır ("Sınava Gir" butonu).
class DsPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool filled;
  final IconData? trailingIcon;
  final IconData? leadingIcon;
  final Gradient? gradient;

  const DsPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.color,
    this.filled = true,
    this.trailingIcon,
    this.leadingIcon,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    // Dolu butonda zemin koyu/doygun olduğu için yazı her temada beyaz;
    // dış çizgili butonda yazı vurgu renginin kendisi.
    final yaziRengi = filled ? Colors.white : color;

    final icerik = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leadingIcon != null) ...[
          Icon(leadingIcon, size: 16, color: yaziRengi),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: yaziRengi,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: 6),
          Icon(trailingIcon, size: 16, color: yaziRengi),
        ],
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: filled ? (gradient ?? LinearGradient(colors: [color, color])) : null,
            color: filled ? null : color.withValues(alpha: c.isLight ? 0.06 : 0.10),
            border: filled ? null : Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
            boxShadow: filled
                ? [BoxShadow(color: color.withValues(alpha: 0.32), blurRadius: 14, offset: const Offset(0, 4))]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            child: icerik,
          ),
        ),
      ),
    );
  }
}

/// ── Banner kart ───────────────────────────────────────────────────────────
///
/// Tasarımda en çok tekrar eden kalıp: solda yuvarlak ikon rozeti, ortada
/// başlık + açıklama, sağda hap buton. (Giriş Yap / Hedef Belirle / Tekrar
/// Sına / Premium'a Geç kartlarının hepsi budur.)
///
/// Dar ekranlarda buton alta iner — taşma olmaz.
class DsBannerCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? emoji;
  final IconData? icon;
  final Color accent;
  final String actionLabel;
  final VoidCallback? onAction;
  final bool filledAction;

  /// Kartın kendisi de vurgulu görünsün mü (Premium kartı gibi).
  final bool highlighted;

  const DsBannerCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.actionLabel,
    required this.onAction,
    this.emoji,
    this.icon,
    this.filledAction = true,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;

    final metin = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: c.text)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: TextStyle(fontSize: 12.5, height: 1.35, color: c.textFaint)),
      ],
    );

    final buton = DsPillButton(
      label: actionLabel,
      onPressed: onAction,
      color: accent,
      filled: filledAction,
    );

    return DsCard(
      accent: highlighted ? accent : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Dar ekranda (küçük telefonlar, büyük yazı ölçeği) buton yan yana
          // sığmaz; bu durumda metnin altına alınır.
          final darMi = constraints.maxWidth < 340;
          final rozet = DsIconBadge(emoji: emoji, icon: icon, color: accent);

          if (darMi) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [rozet, const SizedBox(width: 12), Expanded(child: metin)]),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: buton),
              ],
            );
          }
          return Row(
            children: [
              rozet,
              const SizedBox(width: 12),
              Expanded(child: metin),
              const SizedBox(width: 12),
              buton,
            ],
          );
        },
      ),
    );
  }
}

/// ── Kahraman (hero) kart ──────────────────────────────────────────────────
///
/// "Tam Deneme Sınavı" / "KPSS Düello" / ders sınavı kartlarının kalıbı:
/// degrade zemin, üstte emoji + başlık (+ isteğe bağlı rozet etiketi),
/// açıklama, isteğe bağlı vurgu satırı, altta hap buton; sağda illüstrasyon.
class DsHeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emoji;
  final Color accent;

  /// Degradenin ikinci rengi — verilmezse [accent]'ten türetilir.
  final Color? accent2;
  final String actionLabel;
  final VoidCallback? onAction;

  /// Başlığın yanındaki küçük etiket ("POPÜLER" gibi).
  final String? badge;

  /// Butonun üstündeki altın vurgu satırı ("✨ Sınırsız deneme hakkın var").
  final String? highlightLine;

  /// Sağdaki illüstrasyon için emoji ve (varsa) asset yolu.
  final String illustrationEmoji;
  final String? illustrationAsset;

  /// Küçük harf üst etiket ("GÜNCEL BİLGİLER SINAVI" gibi).
  final String? overline;

  const DsHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.accent,
    required this.actionLabel,
    required this.onAction,
    required this.illustrationEmoji,
    this.accent2,
    this.badge,
    this.highlightLine,
    this.illustrationAsset,
    this.overline,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final ikinci = accent2 ?? accent;

    return DsCard(
      accent: accent,
      padding: const EdgeInsets.all(18),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: c.isLight ? 0.16 : 0.26),
          ikinci.withValues(alpha: c.isLight ? 0.07 : 0.12),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (overline != null) ...[
                  Text(
                    overline!.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Row(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 19)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w900, color: c.text),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      DsChip(label: badge!, color: accent),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textDim)),
                if (highlightLine != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    highlightLine!,
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800, color: c.gold),
                  ),
                ],
                const SizedBox(height: 14),
                DsPillButton(
                  label: actionLabel,
                  onPressed: onAction,
                  color: accent,
                  trailingIcon: Icons.arrow_forward,
                  gradient: LinearGradient(colors: [accent, ikinci]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DsIllustration(
            emoji: illustrationEmoji,
            asset: illustrationAsset,
            glowColor: accent,
          ),
        ],
      ),
    );
  }
}

/// ── Etiket rozeti ─────────────────────────────────────────────────────────
class DsChip extends StatelessWidget {
  final String label;
  final Color color;
  const DsChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: color),
      ),
    );
  }
}

/// ── Bölüm başlığı ─────────────────────────────────────────────────────────
///
/// "Dersler ............ Tüm Dersler >" satırı.
class DsSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const DsSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w900, color: c.text)),
          ),
          if (actionLabel != null)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    Text(actionLabel!,
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800, color: c.violetL)),
                    Icon(Icons.chevron_right, size: 17, color: c.violetL),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// ── Liste satırı ──────────────────────────────────────────────────────────
///
/// Konu listelerinin kalıbı: renkli ikon rozeti, sıra numarası, başlık,
/// durum satırı, sağda daire içinde ok.
class DsListRow extends StatelessWidget {
  final String title;
  final String status;
  final String? emoji;
  final IconData? icon;
  final int? index;
  final Color accent;
  final VoidCallback? onTap;

  const DsListRow({
    super.key,
    required this.title,
    required this.status,
    required this.accent,
    this.emoji,
    this.icon,
    this.index,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return DsCard(
      accent: accent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          DsIconBadge(
            emoji: emoji,
            icon: icon,
            color: accent,
            size: 46,
            circle: false,
            glow: false,
          ),
          if (index != null) ...[
            const SizedBox(width: 10),
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.65), width: 1.4),
              ),
              child: Text('$index',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900, color: accent)),
            ),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800, color: c.text)),
                const SizedBox(height: 3),
                Text(status,
                    style: TextStyle(fontSize: 11.5, color: c.textFaint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.glass2,
              border: Border.all(color: c.border),
            ),
            child: Icon(Icons.chevron_right, size: 18, color: c.textDim),
          ),
        ],
      ),
    );
  }
}

/// ── İstatistik şeridi ─────────────────────────────────────────────────────
///
/// Anasayfadaki üç sütunlu (dikey çizgilerle ayrılmış) istatistik kartı.
class DsStatStrip extends StatelessWidget {
  final List<Widget> items;
  const DsStatStrip({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      children.add(Expanded(child: items[i]));
      if (i != items.length - 1) {
        children.add(Container(width: 1, height: 60, color: c.border));
      }
    }
    return DsCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: children),
    );
  }
}

/// [DsStatStrip] içinde kullanılan tek bir istatistik sütunu.
class DsStatItem extends StatelessWidget {
  final Widget visual;
  final String value;
  final String label;
  final String? sublabel;

  const DsStatItem({
    super.key,
    required this.visual,
    required this.value,
    required this.label,
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        visual,
        const SizedBox(height: 8),
        if (value.isNotEmpty)
          Text(value,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: c.text)),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.textDim)),
        if (sublabel != null)
          Text(sublabel!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: c.textFaint)),
      ],
    );
  }
}

/// ── İlerleme çubuğu ───────────────────────────────────────────────────────
class DsProgressBar extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final double height;

  const DsProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: c.isLight ? c.border : Colors.white.withValues(alpha: 0.08),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}
