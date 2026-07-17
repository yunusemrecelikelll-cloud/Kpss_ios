import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/duel_service.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/theme_provider.dart';

/// Maç sonu ekranı — final sıralama, kazanan kutlaması, Royale'de "Şampiyon"
/// vurgusu. Kazanılan puanlar bir kez lig/XP sistemine eklenir
/// (StorageService.addWeeklyPoints / addXp / addSeasonXp).
class DuelResultScreen extends StatefulWidget {
  final String? roomId; // online
  final int soloScore;
  final int soloCorrect;
  final int soloTotal;

  const DuelResultScreen.online({super.key, required String this.roomId})
      : soloScore = 0,
        soloCorrect = 0,
        soloTotal = 0;

  const DuelResultScreen.solo({
    super.key,
    required int score,
    required int correct,
    required int total,
  })  : roomId = null,
        soloScore = score,
        soloCorrect = correct,
        soloTotal = total;

  bool get isSolo => roomId == null;

  @override
  State<DuelResultScreen> createState() => _DuelResultScreenState();
}

class _DuelResultScreenState extends State<DuelResultScreen> {
  final DuelService _duel = DuelService();
  bool _rewarded = false;

  @override
  void initState() {
    super.initState();
    if (widget.isSolo) {
      // Solo pratik: puanı hemen (bir kez) ödüllendir.
      WidgetsBinding.instance.addPostFrameCallback((_) => _awardOnce(widget.soloScore));
    }
  }

  /// Maçta kazanılan skoru bir kez haftalık lig puanı + XP + sezon XP'sine
  /// dönüştürür (skor / 10). Tekrar çağrılırsa hiçbir şey yapmaz.
  Future<void> _awardOnce(int score) async {
    if (_rewarded) return;
    _rewarded = true;
    final points = (score / 10).round();
    if (points <= 0) return;
    final storage = context.read<StorageService>();
    await storage.addWeeklyPoints(points);
    await storage.addXp(points);
    await storage.addSeasonXp(points);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isSolo) return _buildSolo(context);
    return _buildOnline(context);
  }

  Widget _buildSolo(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final rate = widget.soloTotal == 0 ? 0 : ((widget.soloCorrect / widget.soloTotal) * 100).round();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sonuç'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏁', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 10),
                const Text('Pratik Tamamlandı', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('Puan', '${widget.soloScore}', c),
                    _stat('Doğru', '${widget.soloCorrect}/${widget.soloTotal}', c),
                    _stat('Başarı', '%$rate', c),
                  ],
                ),
                const SizedBox(height: 22),
                _doneButton(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOnline(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Maç Sonucu'), automaticallyImplyLeading: false),
      body: StreamBuilder<DuelRoom?>(
        stream: _duel.watchRoom(widget.roomId!),
        builder: (context, snap) {
          final room = snap.data;
          if (room == null) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            return const Center(child: Text('Oda bilgisi bulunamadı.'));
          }
          final myUid = _duel.currentUid;
          final standings = room.playersByScore;
          // Royale'de kazanan: elenmemişler arasında en yüksek skor; yoksa genel lider.
          final ranked = room.isRoyale
              ? ([...standings.where((p) => !p.eliminated), ...standings.where((p) => p.eliminated)])
              : standings;

          // Kendi skorunla lig/XP ödülü (bir kez). Skor tüm cevap yazımları
          // sunucuda oturduktan sonra kesinleşsin diye SADECE oda 'finished'
          // olduğunda ödüllendir.
          final me = myUid == null ? null : room.players[myUid];
          if (me != null && room.status == 'finished') {
            WidgetsBinding.instance.addPostFrameCallback((_) => _awardOnce(me.score));
          }
          final winner = ranked.isNotEmpty ? ranked.first : null;
          final iAmWinner = winner != null && winner.uid == myUid;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                color: (iAmWinner ? c.gold : c.violet).withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(iAmWinner ? '🏆' : (room.isRoyale ? '👑' : '🎉'),
                          style: const TextStyle(fontSize: 52)),
                      const SizedBox(height: 8),
                      Text(
                        winner == null
                            ? 'Maç Bitti'
                            : (room.isRoyale
                                ? '${winner.name} Şampiyon!'
                                : '${winner.name} Kazandı!'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                      ),
                      if (me != null) ...[
                        const SizedBox(height: 6),
                        Text('Senin skorun: ${me.score}',
                            style: TextStyle(fontSize: 13, color: c.textDim, fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Final Sıralama', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              for (var i = 0; i < ranked.length; i++)
                Card(
                  child: ListTile(
                    leading: Text(
                      i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '${i + 1}.',
                      style: const TextStyle(fontSize: 18),
                    ),
                    title: Text(
                      ranked[i].uid == myUid ? '${ranked[i].name} (sen)' : ranked[i].name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: ranked[i].eliminated ? TextDecoration.lineThrough : null,
                        color: ranked[i].eliminated ? c.textFaint : null,
                      ),
                    ),
                    subtitle: room.isRoyale && ranked[i].eliminated
                        ? Text('${ranked[i].eliminatedAtRound ?? "-"}. turda elendi',
                            style: TextStyle(fontSize: 11, color: c.textFaint))
                        : null,
                    trailing: Text('${ranked[i].score}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                ),
              const SizedBox(height: 20),
              _doneButton(context),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value, dynamic c) => Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(fontSize: 11.5, color: c.textFaint)),
        ],
      );

  Widget _doneButton(BuildContext context) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () {
            context.read<SoundService>().click();
            // Play/Waiting ekranları pushReplacement ile geldiği için tek pop
            // doğrudan lobiye döner.
            Navigator.of(context).pop();
          },
          child: const Text('Lobiye Dön'),
        ),
      );
}
