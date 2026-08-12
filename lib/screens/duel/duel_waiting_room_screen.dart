import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/duel_service.dart';
import '../../services/sound_service.dart';
import '../../theme/design_system.dart';
import '../../theme/theme_provider.dart';
import 'duel_notepad.dart';
import 'duel_play_screen.dart';
import '../../utils/ust_bildirim.dart';

/// Katılan oyuncuların canlı beklendiği oda — oyuncu listesi (StreamBuilder),
/// host için "Başlat" butonu, autoStartAt geri sayımı ve oda kodu paylaşımı.
///
/// Oda dolunca ya da autoStartAt geçince İSTEMCİ tarafında (ilk fark eden
/// cihaz) [DuelService.startRoom] tetiklenir; transaction çift-başlatmayı
/// engeller. status 'active' olunca oyun ekranına geçilir.
class DuelWaitingRoomScreen extends StatefulWidget {
  final String roomId;
  const DuelWaitingRoomScreen({super.key, required this.roomId});

  @override
  State<DuelWaitingRoomScreen> createState() => _DuelWaitingRoomScreenState();
}

class _DuelWaitingRoomScreenState extends State<DuelWaitingRoomScreen> {
  final DuelService _duel = DuelService();
  Timer? _ticker;
  DuelRoom? _room;
  bool _navigated = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    // Oda kurucusu VARSA: sadece kurucunun "Başlat"ı beklenir (auto-start yok).
    // Oda kurucusu YOKSA (ayrılmış) ve yeterli (>=2) oyuncu varsa: sınav
    // OTOMATİK başlar (startRoom transaction'ı çift-başlatmayı engeller).
    final room = _room;
    if (room != null && room.status == 'waiting') {
      // Boş oda otomatik kapansın (kullanıcı isteği): hiç oyuncu kalmadıysa
      // odayı sil. Transaction içinde tekrar boşluk kontrolü yapılır.
      if (room.players.isEmpty) {
        _duel.closeIfEmpty(widget.roomId);
      } else {
        final hostPresent = room.players.containsKey(room.hostUid);
        if (!hostPresent && room.players.length >= 2) {
          _duel.startRoom(widget.roomId);
        }
      }
    }
    setState(() {});
  }

  void _maybeNavigateToPlay(DuelRoom room) {
    if (_navigated) return;
    if (room.status == 'active' || room.status == 'finished') {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => DuelPlayScreen.online(roomId: widget.roomId),
        ));
      });
    }
  }

  Future<void> _leave() async {
    // Kurucu bekleme odasından çıkarsa odayı TAMAMEN siler (oda kurucusuz
    // kalmasın diye). Kurucu değilse sadece kendini oyunculardan çıkarır.
    final room = _room;
    final myUid = _duel.currentUid;
    if (room != null && myUid != null && myUid == room.hostUid) {
      await _duel.deleteRoom(widget.roomId);
    } else {
      await _duel.leaveRoom(widget.roomId);
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// Kurucu için: onaylı "Odayı sil" — odayı siler ve ekrandan çıkar.
  Future<void> _confirmDeleteRoom() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        title: const Text('Odayı sil?'),
        content: const Text('Oda kapatılır ve tüm oyuncular çıkarılır.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(dc, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true) {
      await _duel.deleteRoom(widget.roomId);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _toggleReady(bool ready) async {
    context.read<SoundService>().click();
    await _duel.setReady(widget.roomId, ready);
  }

  /// Kurucu için: onaylı "oyuncuyu odadan at".
  Future<void> _confirmKick(String targetUid, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        title: const Text('Oyuncuyu at?'),
        content: Text('$name odadan çıkarılacak.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(dc, true), child: const Text('At')),
        ],
      ),
    );
    if (ok == true) {
      if (!mounted) return;
      context.read<SoundService>().click();
      await _duel.kickPlayer(widget.roomId, targetUid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final myUid = _duel.currentUid;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Oda Bekleniyor'),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _leave),
          actions: [
            const DuelNotepadButton(),
            // Kurucu için "Odayı sil" (yalnızca host görür).
            if (_room != null && _duel.currentUid == _room!.hostUid)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Odayı sil',
                onPressed: _confirmDeleteRoom,
              ),
          ],
        ),
        body: StreamBuilder<DuelRoom?>(
          stream: _duel.watchRoom(widget.roomId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && _room == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final room = snap.data;
            if (room == null) {
              // Oda silinmiş/kapatılmış. Daha önce yüklendiyse (kurucu sildi)
              // oyuncuyu otomatik geri gönder.
              if (_room != null && !_closed) {
                _closed = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) Navigator.of(context).maybePop();
                });
              }
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DsIllustration(emoji: '🚪', glowColor: c.danger),
                      const SizedBox(height: 10),
                      Text('Oda bulunamadı ya da kapatıldı.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800, color: c.text)),
                      const SizedBox(height: 14),
                      DsPillButton(
                        label: 'Geri Dön',
                        color: c.violetL,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
              );
            }
            _room = room;
            // Kurucu tarafından atıldıysam (artık oyuncular arasında değilim)
            // odadan çık (kullanıcı isteği: kurucu kullanıcı atabilsin).
            if (myUid != null &&
                !room.players.containsKey(myUid) &&
                myUid != room.hostUid &&
                !_closed) {
              _closed = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                ustBildirim('Odadan çıkarıldın.', tur: UstBildirimTuru.hata);
                Navigator.of(context).maybePop();
              });
            }
            _maybeNavigateToPlay(room);
            final isHost = myUid != null && myUid == room.hostUid;
            // Hazır olmayan (host olmayan) oyuncu var mı? Kurucu, katılımcılar
            // hazır olmadan oyunu başlatamaz (kullanıcı isteği).
            final bekleyenler = room.players.values
                .where((p) => p.uid != room.hostUid && !p.ready)
                .toList();
            final herkesHazir = bekleyenler.isEmpty;
            final players = room.players.values.toList()
              ..sort((a, b) => (a.joinedAt?.millisecondsSinceEpoch ?? 0)
                  .compareTo(b.joinedAt?.millisecondsSinceEpoch ?? 0));

            final vurgu = room.isRoyale ? c.gold : c.violetL;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Oda başlığı + kod + geri sayım ──
                DsCard(
                  accent: vurgu,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      DsIllustration(
                        emoji: room.isRoyale ? '👑' : '⚔️',
                        glowColor: vurgu,
                        size: 72,
                      ),
                      const SizedBox(height: 8),
                      Text(room.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900, color: c.text)),
                      const SizedBox(height: 8),
                      DsChip(
                        label: room.isRoyale ? 'KPSS ROYALE' : 'KPSS DÜELLO',
                        color: vurgu,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        room.configLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: c.textDim, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 14),
                      // Oda kodu (kopyalanabilir)
                      Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(kDsRadiusSm),
                        child: InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: room.code));
                            ustBildirim('Oda kodu kopyalandı', tur: UstBildirimTuru.basari);
                          },
                          borderRadius: BorderRadius.circular(kDsRadiusSm),
                          child: Ink(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              color: c.glass2,
                              borderRadius: BorderRadius.circular(kDsRadiusSm),
                              border: Border.all(color: c.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(room.code,
                                    style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 3,
                                        color: c.text)),
                                const SizedBox(width: 8),
                                Icon(Icons.copy, size: 16, color: c.textFaint),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: kDsGap + 4),
                DsSectionHeader(title: 'Oyuncular  ${players.length}/${room.maxPlayers}'),
                const SizedBox(height: kDsGap - 4),
                for (final p in players)
                  Padding(
                    padding: const EdgeInsets.only(bottom: kDsGap - 4),
                    child: DsCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          DsIconBadge(
                            emoji: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                            color: p.uid == room.hostUid ? c.gold : c.violetL,
                            size: 40,
                            glow: false,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 14, color: c.text),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Hazır olan (host olmayan) oyuncular için HAZIR rozeti
                          // — kurucu kimlerin hazır olduğunu görür.
                          if (p.uid != room.hostUid && p.ready) ...[
                            DsChip(label: '✓ HAZIR', color: c.success),
                            const SizedBox(width: 6),
                          ],
                          if (p.uid == room.hostUid)
                            DsChip(label: 'KURUCU', color: c.gold)
                          else if (p.uid == myUid)
                            DsChip(label: 'SEN', color: c.mint),
                          // Kurucu, kendisi dışındaki oyuncuları atabilir
                          // (kullanıcı isteği).
                          if (isHost && p.uid != room.hostUid) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(Icons.person_remove_outlined,
                                  size: 20, color: c.danger),
                              tooltip: 'Odadan at',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _confirmKick(p.uid, p.name),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: kDsGap + 8),
                if (isHost) ...[
                  // ── Kurucu Paneli (temaya uygun yeniden tasarım) ──
                  // Kurucu, katılımcılar hazır olmadan başlatamaz (kullanıcı
                  // isteği). Tek oyuncu (yalnızca kurucu) varsa hazır koşulu
                  // aranmaz — kurucu istediğinde tek başına başlatabilir.
                  Builder(builder: (_) {
                    final tekBasina = players.length < 2;
                    final baslatilabilir = tekBasina || herkesHazir;
                    final hazirSayisi = players.length <= 1
                        ? 0
                        : players.where((p) => p.uid != room.hostUid && p.ready).length;
                    final digerSayisi = (players.length - 1).clamp(0, 999);
                    return DsCard(
                      accent: vurgu,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.shield_moon_outlined, size: 20, color: vurgu),
                              const SizedBox(width: 8),
                              Text('Kurucu Paneli',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: c.text)),
                              const Spacer(),
                              if (!tekBasina)
                                DsChip(
                                  label: '$hazirSayisi/$digerSayisi hazır',
                                  color: herkesHazir ? c.success : c.textFaint,
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          DsPillButton(
                            label: tekBasina
                                ? 'Şimdi Başlat (tek başına)'
                                : (herkesHazir
                                    ? 'Şimdi Başlat'
                                    : 'Oyuncular hazır bekleniyor…'),
                            leadingIcon: Icons.play_arrow,
                            color: baslatilabilir ? vurgu : c.textFaint,
                            onPressed: (players.isEmpty || !baslatilabilir)
                                ? null
                                : () {
                                    context.read<SoundService>().click();
                                    _duel.startRoom(widget.roomId);
                                  },
                          ),
                          if (!herkesHazir && players.length >= 2) ...[
                            const SizedBox(height: 10),
                            Text(
                                '${bekleyenler.length} oyuncu henüz "Hazırım" demedi.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: c.textFaint, fontSize: 12)),
                          ],
                        ],
                      ),
                    );
                  }),
                ]
                else ...[
                  // Kurucu olmayan oyuncu için HAZIR butonu — bastığında kurucu
                  // onun hazır olduğunu görür.
                  Builder(builder: (_) {
                    final meReady =
                        myUid != null && (room.players[myUid]?.ready ?? false);
                    return Center(
                      child: DsPillButton(
                        label: meReady ? 'Hazırım ✓ (iptal)' : 'Hazırım',
                        leadingIcon: meReady
                            ? Icons.check_circle
                            : Icons.check_circle_outline,
                        color: meReady ? c.success : c.violetL,
                        filled: meReady,
                        onPressed: () => _toggleReady(!meReady),
                      ),
                    );
                  }),
                  const SizedBox(height: 10),
                  Center(
                    child: Text('Kurucunun başlatması bekleniyor...',
                        style: TextStyle(color: c.textFaint, fontSize: 12.5)),
                  ),
                ],
                const SizedBox(height: 10),
                Center(
                  child: Text(
                      isHost
                          ? 'Oyunu sen başlatırsın; oyuncuların "Hazırım" demesini bekleyebilirsin.'
                          : 'Kurucu yoksa yeterli oyuncu olunca oyun otomatik başlar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textFaint, fontSize: 11.5)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
