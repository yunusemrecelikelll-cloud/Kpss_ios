import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/question.dart';
import '../models/subject.dart';
import '../models/topic.dart';
import 'question_picker.dart';

/// Bir konunun anlatımını ve sorularını PDF olarak dışa aktarır — tek
/// dokunuşla cihazın paylaşma sayfasını (kaydet/paylaş/yazdır) açar.
/// Ücretsiz kullanıcı için sadece ilk [QuestionPicker.freeTopicPoolSize] soru,
/// premium kullanıcı için havuzdaki tüm sorular PDF'e dahil edilir.
class PdfExportService {
  static pw.Font? _font;

  static Future<pw.Font> _loadFont() async {
    if (_font != null) return _font!;
    final data = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    _font = pw.Font.ttf(data);
    return _font!;
  }

  /// [soruHavuzu] verilmezse (geriye dönük uyumluluk için) konunun gömülü
  /// yedek soruları kullanılır — normalde çağıran taraf, o an geçerli olan
  /// (Firestore önbellekli ya da yedek) havuzu RemoteQuestionService.getPool
  /// üzerinden alıp burada geçirmelidir.
  static Future<void> exportTopic({
    required SubjectMeta subject,
    required Topic topic,
    required bool premium,
    List<Question>? soruHavuzu,
  }) async {
    final font = await _loadFont();
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final doc = pw.Document(theme: theme);

    final havuz = soruHavuzu ?? topic.sorular;
    final sorular = premium
        ? havuz
        : havuz.take(QuestionPicker.freeTopicPoolSize).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text('KPSS Hazırlık — ${subject.ad}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Sayfa ${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
        ),
        build: (context) => [
          pw.Text('${subject.icon}  ${topic.baslik}',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          if (topic.anlatim.ozet != null) ...[
            pw.Text(topic.anlatim.ozet!,
                style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic, color: PdfColors.grey800)),
            pw.SizedBox(height: 12),
          ],
          if (topic.anlatim.icerik.isNotEmpty) ...[
            pw.Text('Konu Anlatımı', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            for (final p in topic.anlatim.icerik)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(p, style: const pw.TextStyle(fontSize: 11, lineSpacing: 3)),
              ),
            pw.SizedBox(height: 6),
          ],
          if (topic.anlatim.anahtarNoktalar.isNotEmpty) ...[
            pw.Text('Anahtar Noktalar', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            for (final k in topic.anlatim.anahtarNoktalar)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('•  ', style: const pw.TextStyle(fontSize: 11)),
                    pw.Expanded(child: pw.Text(k, style: const pw.TextStyle(fontSize: 11))),
                  ],
                ),
              ),
            pw.SizedBox(height: 16),
          ],
          pw.Text('Sorular (${sorular.length})',
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          if (!premium)
            pw.Text(
              'Ücretsiz sürümde konu havuzunun ilk ${QuestionPicker.freeTopicPoolSize} sorusu gösterilir. '
              'Sınırsıza yakın soru için Premium\'a geçebilirsin.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          pw.SizedBox(height: 10),
          for (var i = 0; i < sorular.length; i++) ...[
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 14),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('${i + 1}. ${sorular[i].soru}',
                      style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 6),
                  for (var j = 0; j < sorular[i].secenekler.length; j++)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 2),
                      child: pw.Text(
                        '${String.fromCharCode(65 + j)}) ${sorular[i].secenekler[j]}',
                        style: pw.TextStyle(
                          fontSize: 10.5,
                          color: j == sorular[i].dogruIndex ? PdfColors.green800 : PdfColors.black,
                          fontWeight: j == sorular[i].dogruIndex ? pw.FontWeight.bold : pw.FontWeight.normal,
                        ),
                      ),
                    ),
                  pw.SizedBox(height: 6),
                  pw.Text('Açıklama: ${sorular[i].aciklama}',
                      style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700)),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: '${topic.id}.pdf');
  }
}
