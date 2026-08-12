import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/data_service.dart';
import '../../services/duel_service.dart';
import '../../services/remote_question_service.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/design_system.dart';
import '../../theme/theme_provider.dart';
import '../../utils/ust_bildirim.dart';
import 'duel_waiting_room_screen.dart';

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
  bool _returnedToWaiting = false;
  bool _resetting = false;

  /// Host "Tekrar Oyna" derse oda 'waiting'e döner; TÜM oyuncular (host +
  /// diğerleri) bunu stream'den görüp otomatik olarak bekleme odasına döner.
  void _maybeReturnToWaiting(DuelRoom room) {
    if (_returnedToWaiting) return;
    if (room.status == 'waiting') {
      _returnedToWaiting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => DuelWaitingRoomScreen(roomId: widget.roomId!),
        ));
      });
    }
  }

  Future<void> _tekrarOyna() async {
    if (_resetting) return;
    setState(() => _resetting = true);
    context.read<SoundService>().click();
    final remote = context.read<RemoteQuestionService>();
    try {
      // Taze soru havuzuyla yeniden başlat (kullanıcı isteği: odaya dönünce
      // AYNI sorular gelmesin). Ders verisini yükleyip odanın filtresine göre
      // yeni sorular toplanır. Herhangi bir hata olursa eski (aynı soruları
      // karıştıran) resetRoom'a düşülür ki oyun yine de tekrar başlayabilsin.
      final subjects = (await context.read<DataService>().loadAll())
          .where((x) => x.konular.isNotEmpty)
          .toList();
      await _duel.resetRoomFresh(
        roomId: widget.roomId!,
        subjects: subjects,
        remote: remote,
      );
      // Başarılıysa stream 'waiting' yayınlar ve _maybeReturnToWaiting devreye
      // girer; ayrıca burada beklemeye gerek yok.
    } catch (e) {
      try {
        await _duel.resetRoom(widget.roomId!);
      } catch (_) {
        if (mounted) {
          setState(() => _resetting = false);
          ustBildirim('Tekrar başlatılamadı, yeniden dene.');
        }
      }
    }
  }

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
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DsCard(
            accent: c.mint,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DsIllustration(emoji: '🏁', glowColor: c.mint, size: 88),
                const SizedBox(height: 8),
                Text('Pratik Tamamlandı',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900, color: c.text)),
                const SizedBox(height: 6),
                DsChip(label: 'TEK BAŞINA YARIŞ', color: c.mint),
              ],
            ),
          ),
          const SizedBox(height: kDsGap),
          DsStatStrip(
            items: [
              DsStatItem(
                visual: DsIconBadge(emoji: '⭐', color: c.gold, size: 40, glow: false),
                value: '${widget.soloScore}',
                label: 'Puan',
              ),
              DsStatItem(
                visual: DsIconBadge(emoji: '✅', color: c.success, size: 40, glow: false),
                value: '${widget.soloCorrect}/${widget.soloTotal}',
                label: 'Doğru',
              ),
              DsStatItem(
                visual: DsIconBadge(emoji: '📈', color: c.violetL, size: 40, glow: false),
                value: '%$rate',
                label: 'Başarı',
              ),
            ],
          ),
          const SizedBox(height: kDsGap + 8),
          _doneButton(context),
        ],
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
          // Host "Tekrar Oyna" derse oda 'waiting'e döner → herkes bekleme
          // odasına geri döner.
          _maybeReturnToWaiting(room);
          final myUid = _duel.currentUid;
          final isHost = myUid != null && myUid == room.hostUid;
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
          // BERABERLİK: en yüksek skoru BİRDEN ÇOK oyuncu paylaşıyorsa maç
          // beraberedir — kimse "kazanan" gösterilmez (aksi halde her istemci
          // kendini kazanan sanıyordu). Royale'de eleme sonrası ayakta kalanlar
          // arasında bakılır.
          final adaylar = room.isRoyale
              ? ranked.where((p) => !p.eliminated).toList()
              : ranked;
          final enYuksekSkor = adaylar.isEmpty ? 0 : adaylar.first.score;
          final tepedekiler =
              adaylar.where((p) => p.score == enYuksekSkor).toList();
          final berabere = tepedekiler.length > 1;
          final winner =
              berabere ? null : (ranked.isNotEmpty ? ranked.first : null);
          final iAmWinner = winner != null && winner.uid == myUid;
          final iAmDraw =
              berabere && myUid != null && tepedekiler.any((p) => p.uid == myUid);

          final vurgu = iAmWinner
              ? c.gold
              : (berabere ? c.mint : (room.isRoyale ? c.roseL : c.violetL));

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ── Kazanan / beraberlik kutlaması ──
              DsCard(
                accent: vurgu,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    DsIllustration(
                      emoji: berabere
                          ? '🤝'
                          : (iAmWinner ? '🏆' : (room.isRoyale ? '👑' : '🎉')),
                      glowColor: vurgu,
                      size: 96,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      berabere
                          ? 'Berabere!'
                          : (winner == null
                              ? 'Maç Bitti'
                              : (room.isRoyale
                                  ? '${winner.name} Şampiyon!'
                                  : '${winner.name} Kazandı!')),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w900, color: c.text),
                    ),
                    if (berabere) ...[
                      const SizedBox(height: 8),
                      DsChip(
                        label: iAmDraw
                            ? 'BERABERE KALDINIZ ($enYuksekSkor puan)'
                            : 'EŞİT SKOR — BERABERE',
                        color: c.mint,
                      ),
                    ] else if (iAmWinner) ...[
                      const SizedBox(height: 8),
                      DsChip(label: 'TEBRİKLER, KAZANAN SENSİN', color: c.gold),
                    ],
                    if (me != null) ...[
                      const SizedBox(height: 8),
                      Text('Senin skorun: ${me.score}',
                          style: TextStyle(
                              fontSize: 13, color: c.textDim, fontWeight: FontWeight.w800)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: kDsGap + 6),
              const DsSectionHeader(title: 'Final Sıralama'),
              const SizedBox(height: kDsGap - 4),
              for (var i = 0; i < ranked.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: kDsGap - 4),
                  child: _StandingRow(
                    // Eşit skorlar AYNI sırayı alır (berabere yanıltmasın).
                    rank: 1 + ranked.where((p) => p.score > ranked[i].score).length,
                    player: ranked[i],
                    isMe: ranked[i].uid == myUid,
                    showEliminationNote: room.isRoyale,
                    colors: c,
                  ),
                ),
              const SizedBox(height: kDsGap + 8),
              // ── Tekrar Oyna (aynı oda) + Lobiye Dön ──
              if (isHost)
                Center(
                  child: DsPillButton(
                    label: _resetting ? 'Hazırlanıyor…' : 'Tekrar Oyna (Aynı Oda)',
                    color: c.gold,
                    leadingIcon: Icons.replay_rounded,
                    onPressed: _resetting ? null : _tekrarOyna,
                  ),
                )
              else
                Center(
                  child: Text(
                    'Kurucu "Tekrar Oyna" derse aynı odada yeniden başlarsınız.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textFaint, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              _doneButton(context, leaveRoom: true, isHost: isHost),
            ],
          );
        },
      ),
    );
  }

  Widget _doneButton(BuildContext context, {bool leaveRoom = false, bool isHost = false}) {
    final c = context.watch<ThemeProvider>().colors;
    return Center(
      child: DsPillButton(
        label: 'Lobiye Dön',
        color: c.violetL,
        filled: false,
        trailingIcon: Icons.arrow_forward,
        onPressed: () {
          context.read<SoundService>().click();
          if (leaveRoom && widget.roomId != null) {
            // Kullanıcı isteği: maç bitip ODA KURUCUSU lobiye dönerse (odadan
            // çıkarsa) oda TAMAMEN silinir. Kurucu değilse yalnızca kendisi
            // ayrılır — böylece tekrar maçında "hayalet oyuncu" kalmaz.
            if (isHost) {
              _duel.deleteRoom(widget.roomId!);
            } else {
              _duel.leaveRoom(widget.roomId!);
            }
          }
          // Play/Waiting ekranları pushReplacement ile geldiği için tek pop
          // doğrudan lobiye döner.
          Navigator.of(context).pop();
        },
      ),
    );
  }
}

/// Final sıralamadaki tek satır — madalya/sıra, oyuncu adı, elenme notu, skor.
class _StandingRow extends StatelessWidget {
  final int rank;
  final DuelPlayer player;
  final bool isMe;
  final bool showEliminationNote;
  final KpssColors colors;

  const _StandingRow({
    required this.rank,
    required this.player,
    required this.isMe,
    required this.showEliminationNote,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final madalya = rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : null;
    // İlk üçe altın/gümüş hissi veren vurgu; kendi satırın her zaman belirgin.
    final vurgu = rank == 1 ? c.gold : (isMe ? c.violetL : null);

    return DsCard(
      accent: vurgu,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: madalya != null
                ? Text(madalya, style: const TextStyle(fontSize: 20))
                : Text('$rank.',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900, color: c.textFaint)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isMe ? '${player.name} (sen)' : player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    decoration: player.eliminated ? TextDecoration.lineThrough : null,
                    color: player.eliminated ? c.textFaint : c.text,
                  ),
                ),
                if (showEliminationNote && player.eliminated) ...[
                  const SizedBox(height: 2),
                  Text('${player.eliminatedAtRound ?? "-"}. turda elendi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: c.textFaint)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${player.score}',
              style: TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 15, color: vurgu ?? c.text)),
        ],
      ),
    );
  }
}
