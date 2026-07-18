import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/question.dart';
import '../models/subject.dart';
import '../models/topic.dart';

/// Bir konunun anlatımını ve sorularını PDF olarak dışa aktarır — tek
/// dokunuşla cihazın paylaşma sayfasını (kaydet/paylaş/yazdır) açar.
///
/// Düzen: (opsiyonel) konu anlatımı → sorular → EN SON SAYFADA cevap anahtarı.
/// [includeLecture] false ise (2. ve sonraki indirmeler) konu anlatımı atlanır,
/// yalnızca sorular + cevap anahtarı yazılır.
///
/// PDF fontu (NotoSans) emoji glifleri içermez; bu yüzden tüm metinlerdeki
/// emojiler PDF'e yazılmadan önce temizlenir (kutu/boşluk görünmesin diye).
class PdfExportService {
  static pw.Font? _font;

  static Future<pw.Font> _loadFont() async {
    if (_font != null) return _font!;
    final data = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    _font = pw.Font.ttf(data);
    return _font!;
  }

  /// Emoji ve NotoSans'ta bulunmayan sembolleri kaldırır.
  static String _noEmoji(String s) {
    return s
        .replaceAll(
            RegExp(
                r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2190}-\u{21FF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]',
                unicode: true),
            '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  /// Şık metninin başındaki "A) " gibi bir ön ek varsa kaldırır (PDF kendi
  /// harfini eklediği için çift harf olmasın).
  static String _stripOptPrefix(String s) =>
      _noEmoji(s).replaceFirst(RegExp(r'^[A-Ea-e]\)\s*'), '');

  static Future<void> exportTopic({
    required SubjectMeta subject,
    required Topic topic,
    required List<Question> sorular,
    required bool includeLecture,
  }) async {
    final font = await _loadFont();
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final doc = pw.Document(theme: theme);

    final baslik = _noEmoji(topic.baslik);
    final dersAd = _noEmoji(subject.ad);

    pw.Widget header(pw.Context ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text('KPSS Hazirlik - $dersAd',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        );
    pw.Widget footer(pw.Context ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Sayfa ${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
        );

    // 1) (opsiyonel) konu anlatımı + sorular
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: header,
        footer: footer,
        build: (context) => [
          pw.Text(baslik,
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          if (includeLecture) ..._lectureWidgets(topic),
          pw.Text('Sorular (${sorular.length})',
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          for (var i = 0; i < sorular.length; i++) _questionBlock(i, sorular[i]),
        ],
      ),
    );

    // 2) EN SON SAYFA: cevap anahtarı
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: header,
        footer: footer,
        build: (context) => [
          pw.Text('Cevap Anahtari',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          for (var i = 0; i < sorular.length; i++) _answerBlock(i, sorular[i]),
        ],
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: '${topic.id}.pdf');
  }

  static List<pw.Widget> _lectureWidgets(Topic topic) {
    final a = topic.anlatim;
    final ozet = a.ozet == null ? '' : _noEmoji(a.ozet!);
    return [
      if (ozet.isNotEmpty) ...[
        pw.Text(ozet,
            style: pw.TextStyle(
                fontSize: 12,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey800)),
        pw.SizedBox(height: 12),
      ],
      if (a.icerik.isNotEmpty) ...[
        pw.Text('Konu Anlatimi',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        for (final p in a.icerik)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(_noEmoji(p),
                style: const pw.TextStyle(fontSize: 11, lineSpacing: 3)),
          ),
        pw.SizedBox(height: 6),
      ],
      if (a.anahtarNoktalar.isNotEmpty) ...[
        pw.Text('Anahtar Noktalar',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        for (final k in a.anahtarNoktalar)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('-  ', style: const pw.TextStyle(fontSize: 11)),
                pw.Expanded(
                    child: pw.Text(_noEmoji(k),
                        style: const pw.TextStyle(fontSize: 11))),
              ],
            ),
          ),
        pw.SizedBox(height: 16),
      ],
    ];
  }

  /// Soru bloğu — soru + şıklar. Doğru cevap BURADA gösterilmez (cevap
  /// anahtarında verilir).
  static pw.Widget _questionBlock(int i, Question q) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('${i + 1}. ${_noEmoji(q.soru)}',
              style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          for (var j = 0; j < q.secenekler.length; j++)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(
                '${String.fromCharCode(65 + j)}) ${_stripOptPrefix(q.secenekler[j])}',
                style: const pw.TextStyle(fontSize: 10.5),
              ),
            ),
        ],
      ),
    );
  }

  /// Cevap anahtarı satırı — doğru şıkkın harfi + açıklama.
  static pw.Widget _answerBlock(int i, Question q) {
    final letter = String.fromCharCode(65 + q.dogruIndex);
    final aciklama = _noEmoji(q.aciklama);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('${i + 1}. Dogru cevap: $letter',
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.green800)),
          if (aciklama.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2, left: 12),
              child: pw.Text(aciklama,
                  style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700)),
            ),
        ],
      ),
    );
  }
}
