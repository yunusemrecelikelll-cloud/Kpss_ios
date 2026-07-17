/// KPSS sınav türlerine göre sınav tarihleri ve geri sayım hesaplaması.
class ExamInfo {
  final String id; // 'lisans' | 'onlisans' | 'ortaogretim'
  final String label;
  final int month; // 1-12
  final int day;

  const ExamInfo({required this.id, required this.label, required this.month, required this.day});
}

const List<ExamInfo> kExamTypes = [
  ExamInfo(id: 'lisans', label: 'Lisans', month: 9, day: 6),
  ExamInfo(id: 'onlisans', label: 'Önlisans', month: 10, day: 4),
  ExamInfo(id: 'ortaogretim', label: 'Ortaöğretim', month: 10, day: 25),
];

ExamInfo? examInfoFor(String id) {
  for (final e in kExamTypes) {
    if (e.id == id) return e;
  }
  return null;
}

/// Verilen sınav türü için bir sonraki sınav tarihini döndürür
/// (tarih geçtiyse otomatik olarak bir sonraki yıla kayar).
DateTime nextExamDate(ExamInfo info, {DateTime? now}) {
  final today = now ?? DateTime.now();
  var date = DateTime(today.year, info.month, info.day);
  if (date.isBefore(DateTime(today.year, today.month, today.day))) {
    date = DateTime(today.year + 1, info.month, info.day);
  }
  return date;
}

/// "2 Ay 5 Gün 3 Saat 20 Dk" gibi, dakika hassasiyetinde bir geri sayım
/// metni üretir (sadece tarih değil, saat:dakika de hesaba katılır).
String formatCountdown(DateTime target, {DateTime? now}) {
  final today = now ?? DateTime.now();
  // Sınav günü, günün başlangıcı (00:00) olarak kabul edilir; kalan süre
  // "şu an"dan sınav gününün başlangıcına kadar hesaplanır.
  final examDayStart = DateTime(target.year, target.month, target.day);
  if (!examDayStart.isAfter(DateTime(today.year, today.month, today.day))) {
    return 'Sınav bugün! 🎯';
  }

  var months = (examDayStart.year - today.year) * 12 + (examDayStart.month - today.month);
  var days = examDayStart.day - today.day;
  var hours = 23 - today.hour;
  var minutes = 60 - today.minute;
  if (minutes == 60) {
    minutes = 0;
  } else {
    hours -= 1;
  }
  if (hours < 0) {
    hours += 24;
    days -= 1;
  }
  if (days < 0) {
    months -= 1;
    final prevMonth = DateTime(examDayStart.year, examDayStart.month, 0); // önceki ayın son günü
    days += prevMonth.day;
  }

  final parts = <String>[];
  if (months > 0) parts.add('$months Ay');
  if (days > 0) parts.add('$days Gün');
  if (hours > 0) parts.add('$hours Saat');
  if (minutes > 0) parts.add('$minutes Dk');
  if (parts.isEmpty) return 'Sınav bugün! 🎯';
  return parts.join(' ');
}
