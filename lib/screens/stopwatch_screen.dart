import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/subject.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import 'tools_hub_screen.dart';

String _fmtDuration(int sec) {
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${p2(h)}:${p2(m)}:${p2(s)}';
}

/// Çalışma Kronometresi ve Zaman Analizi — JS: renderStopwatch.
class StopwatchScreen extends StatefulWidget {
  const StopwatchScreen({super.key});

  @override
  State<StopwatchScreen> createState() => _StopwatchScreenState();
}

class _StopwatchScreenState extends State<StopwatchScreen> with WidgetsBindingObserver {
  Timer? _timer;
  int _seconds = 0;
  bool _running = false;
  String _subjectId = kSubjects.first.id;

  /// Uygulama arka plana alındığı için kronometreyi BİZ duraklattıysak true
  /// olur — kullanıcıya "otomatik duraklatıldı" bilgisini bir kez göstermek
  /// için kullanılır. Kullanıcının kendi elle duraklatmasından ayırt edilir.
  bool _autoPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  /// Uygulamadan çıkılınca (ana ekrana dönme, uygulama değiştirme, ekran
  /// kilidi) kronometre DURSUN — aksi halde çalışılmayan süre de çalışma
  /// süresi olarak kaydediliyordu.
  ///
  /// `inactive` DAHİL edilir çünkü iOS'ta uygulama arka plana giderken önce
  /// bu duruma düşer (kontrol merkezi, gelen arama, uygulama değiştirici).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final gittiArkaPlana = state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;

    if (gittiArkaPlana && _running) {
      _timer?.cancel();
      setState(() {
        _running = false;
        _autoPaused = true;
      });
    } else if (state == AppLifecycleState.resumed && _autoPaused) {
      // Geri dönüldüğünde kendiliğinden BAŞLATMIYORUZ — kullanıcı gerçekten
      // çalışmaya devam ettiğinde kendisi "Başlat"a bassın ki kayıt dürüst
      // kalsın. Sadece ne olduğunu bir kez bildiriyoruz.
      setState(() => _autoPaused = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Uygulamadan çıktığın için kronometre duraklatıldı. '
                'Devam etmek için "Başlat"a bas.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _toggle() {
    context.read<SoundService>().click();
    setState(() {
      _running = !_running;
      _autoPaused = false;
      if (_running) {
        _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _seconds++));
      } else {
        _timer?.cancel();
      }
    });
  }

  Future<void> _finishAndSave() async {
    context.read<SoundService>().click();
    _timer?.cancel();
    final had = _seconds;
    setState(() => _running = false);
    if (had > 0) {
      final storage = context.read<StorageService>();
      await storage.addStudyTime(_subjectId, had);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${_fmtDuration(had)} kaydedildi!')));
    }
    setState(() => _seconds = 0);
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    if (!storage.isPremiumUser()) {
      return const LockedFeatureCard(
        title: 'Çalışma Kronometresi ve Zaman Analizi',
        desc: "Ders bazlı çalışma sürelerini kaydetmek ve analiz etmek için Premium'a geç.",
      );
    }

    final times = storage.getStudyTime();
    final rows = kSubjects.map((s) => (id: s.id, label: s.ad, icon: s.icon, minutes: ((times[s.id] ?? 0) / 60).round())).toList();
    final maxMinutes = rows.fold<int>(1, (m, r) => r.minutes > m ? r.minutes : m);

    return Scaffold(
      appBar: AppBar(title: const Text('⏱️ Çalışma Kronometresi ve Zaman Analizi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  DropdownButton<String>(
                    value: _subjectId,
                    isExpanded: true,
                    items: [
                      for (final s in kSubjects)
                        DropdownMenuItem(value: s.id, child: Text('${s.icon} ${s.ad}')),
                    ],
                    onChanged: _running ? null : (v) => setState(() => _subjectId = v ?? _subjectId),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _fmtDuration(_seconds),
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(onPressed: _toggle, child: Text(_running ? '⏸ Duraklat' : '▶ Başlat')),
                      const SizedBox(width: 10),
                      OutlinedButton(onPressed: _finishAndSave, child: const Text('✅ Bitir ve Kaydet')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Toplam Çalışma Süreleri (dk)', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
              child: SizedBox(
                height: 220,
                child: BarChart(
                  BarChartData(
                    maxY: (maxMinutes * 1.2).clamp(1, double.infinity),
                    barTouchData: BarTouchData(enabled: true),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            if (i < 0 || i >= rows.length) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(rows[i].icon, style: const TextStyle(fontSize: 14)),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(drawVerticalLine: false),
                    barGroups: [
                      for (var i = 0; i < rows.length; i++)
                        BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                            toY: rows[i].minutes.toDouble(),
                            color: Theme.of(context).colorScheme.primary,
                            width: 18,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
