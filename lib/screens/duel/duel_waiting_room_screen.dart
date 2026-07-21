import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/duel_service.dart';
import '../../services/sound_service.dart';
import '../../theme/design_system.dart';
import '../../theme/theme_provider.dart';
import 'duel_play_screen.dart';

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
  bool _startTriggered = false;

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
    final room = _room;
    if (room == null || room.status != 'waiting') {
      setState(() {}); // sadece geri sayımı yenile
      return;
    }
    // Auto-start: oda dolduysa ya da autoStartAt geçtiyse başlat.
    final now = DateTime.now();
    final full = room.isFull;
    final expired = room.autoStartAt != null && now.isAfter(room.autoStartAt!);
    if ((full || expired) && !_startTriggered) {
      _startTriggered = true;
      _duel.startRoom(widget.roomId).catchError((_) {});
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
    await _duel.leaveRoom(widget.roomId);
    if (mounted) Navigator.of(context).pop();
  }

  String _countdownLabel(DuelRoom room) {
    if (room.autoStartAt == null) return '';
    final diff = room.autoStartAt!.difference(DateTime.now());
    if (diff.isNegative) return 'Başlıyor...';
    final m = diff.inMinutes;
    final s = diff.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
        ),
        body: StreamBuilder<DuelRoom?>(
          stream: _duel.watchRoom(widget.roomId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && _room == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final room = snap.data;
            if (room == null) {
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
                    ],
                  ),
                ),
              );
            }
            _room = room;
            _maybeNavigateToPlay(room);
            final isHost = myUid != null && myUid == room.hostUid;
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Oda kodu kopyalandı')),
                            );
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
                      const SizedBox(height: 12),
                      Text('En geç başlangıç: ${_countdownLabel(room)}',
                          style: TextStyle(
                              fontSize: 13, color: c.warn, fontWeight: FontWeight.w800)),
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
                          if (p.uid == room.hostUid)
                            DsChip(label: 'KURUCU', color: c.gold)
                          else if (p.uid == myUid)
                            DsChip(label: 'SEN', color: c.mint),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: kDsGap + 8),
                if (isHost)
                  Center(
                    child: DsPillButton(
                      label: room.isRoyale && players.length < 2
                          ? 'Şimdi Başlat (tek başına)'
                          : 'Şimdi Başlat',
                      leadingIcon: Icons.play_arrow,
                      color: vurgu,
                      onPressed: players.isEmpty
                          ? null
                          : () {
                              context.read<SoundService>().click();
                              _duel.startRoom(widget.roomId);
                            },
                    ),
                  )
                else
                  Center(
                    child: Text('Kurucunun başlatması bekleniyor...',
                        style: TextStyle(color: c.textFaint, fontSize: 12.5)),
                  ),
                const SizedBox(height: 10),
                Center(
                  child: Text('Oda dolunca ya da süre bitince otomatik başlar.',
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
