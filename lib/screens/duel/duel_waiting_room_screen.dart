import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/duel_service.dart';
import '../../services/sound_service.dart';
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
              return const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Oda bulunamadı ya da kapatıldı.'),
              ));
            }
            _room = room;
            _maybeNavigateToPlay(room);
            final isHost = myUid != null && myUid == room.hostUid;
            final players = room.players.values.toList()
              ..sort((a, b) => (a.joinedAt?.millisecondsSinceEpoch ?? 0)
                  .compareTo(b.joinedAt?.millisecondsSinceEpoch ?? 0));

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Text(room.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(room.isRoyale ? '👑 KPSS Royale' : '⚔️ KPSS Düello',
                            style: TextStyle(color: c.textFaint, fontSize: 12.5)),
                        const SizedBox(height: 6),
                        Text(
                          room.configLabel,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.textDim, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 14),
                        // Oda kodu (kopyalanabilir)
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: room.code));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Oda kodu kopyalandı')),
                            );
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              color: c.glass2,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: c.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(room.code,
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3)),
                                const SizedBox(width: 8),
                                Icon(Icons.copy, size: 16, color: c.textFaint),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('En geç başlangıç: ${_countdownLabel(room)}',
                            style: TextStyle(fontSize: 13, color: c.warn, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Oyuncular', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    Text('${players.length}/${room.maxPlayers}',
                        style: TextStyle(fontSize: 13, color: c.textFaint)),
                  ],
                ),
                const SizedBox(height: 10),
                for (final p in players)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?')),
                      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: p.uid == room.hostUid
                          ? const Chip(label: Text('Kurucu', style: TextStyle(fontSize: 11)))
                          : (p.uid == myUid ? const Text('Sen') : null),
                    ),
                  ),
                const SizedBox(height: 20),
                if (isHost)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: players.isEmpty
                          ? null
                          : () {
                              context.read<SoundService>().click();
                              _duel.startRoom(widget.roomId);
                            },
                      icon: const Icon(Icons.play_arrow),
                      label: Text(room.isRoyale && players.length < 2
                          ? 'Şimdi Başlat (tek başına)'
                          : 'Şimdi Başlat'),
                    ),
                  )
                else
                  Center(
                    child: Text('Kurucunun başlatması bekleniyor...',
                        style: TextStyle(color: c.textFaint, fontSize: 12.5)),
                  ),
                const SizedBox(height: 8),
                Center(
                  child: Text('Oda dolunca ya da süre bitince otomatik başlar.',
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
