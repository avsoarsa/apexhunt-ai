import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/models.dart';

/// A resolved, render-ready CV (profile anchors + tailored content).
class CvDocument {
  CvDocument({required this.profile, required this.cv});
  final MasterProfile profile;
  final TailoredCv cv;

  String get name => profile.contact.name.isEmpty ? 'Candidate' : profile.contact.name;
  String get contactLine => [profile.contact.email, profile.contact.phone, profile.contact.location, ...profile.contact.links].where((e) => e.trim().isNotEmpty).join('  |  ');
  List<Project> get projects => profile.projects.where((p) => cv.projectIds.contains(p.id)).toList();

  List<(WorkRole, List<String>)> get roles => [
        for (final tr in cv.roles)
          for (final r in profile.roles.where((r) => r.id == tr.roleId)) (r, tr.bullets.where((b) => b.enabled && b.text.trim().isNotEmpty).map((b) => b.text).toList()),
      ];

  static String _sanitize(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');

  /// `{FirstName}_{LastName}_{Company}_{Role}` (spec rule 3.3).
  String fileStem(Opportunity o) {
    final parts = [profile.firstName, profile.lastName, o.company, o.title].map(_sanitize).where((e) => e.isNotEmpty).toList();
    final stem = parts.join('_');
    return stem.length > 90 ? stem.substring(0, 90) : (stem.isEmpty ? 'CV' : stem);
  }
}

/// ATS-pure, strictly single-column PDF: real text, no tables, columns, icons or images.
class CvPdfBuilder {
  static pw.Font? _regular, _bold, _italic;

  static Future<void> _loadFonts() async {
    _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Regular.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf'));
    _italic ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Italic.ttf'));
  }

  static Future<Uint8List> build(CvDocument d) async {
    await _loadFonts();
    final theme = pw.ThemeData.withFont(base: _regular!, bold: _bold!, italic: _italic!);
    const ink = PdfColor.fromInt(0xFF111827);
    const muted = PdfColor.fromInt(0xFF4B5563);
    const rule = PdfColor.fromInt(0xFFD1D5DB);

    pw.Widget heading(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(t.toUpperCase(), style: pw.TextStyle(font: _bold, fontSize: 10.5, letterSpacing: 1.1, color: ink)),
            pw.SizedBox(height: 2),
            pw.Container(height: 0.7, color: rule),
          ]),
        );

    pw.Widget bullet(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(left: 10, bottom: 2.5),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: 10, child: pw.Text('•', style: const pw.TextStyle(fontSize: 10, color: ink))),
            pw.Expanded(child: pw.Text(t, style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.6, color: ink))),
          ]),
        );

    final p = d.profile;
    final doc = pw.Document(title: '${d.name} CV', author: d.name, creator: 'ApexHunt AI');
    doc.addPage(pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 44, vertical: 40),
      build: (_) => [
        pw.Text(d.name, style: pw.TextStyle(font: _bold, fontSize: 20, color: ink)),
        if (d.cv.headline.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: pw.Text(d.cv.headline, style: const pw.TextStyle(fontSize: 11.5, color: muted))),
        if (d.contactLine.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Text(d.contactLine, style: const pw.TextStyle(fontSize: 9.5, color: muted))),
        if (d.cv.summary.isNotEmpty) ...[heading('Summary'), pw.Text(d.cv.summary, style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.6, color: ink))],
        if (d.cv.skills.isNotEmpty) ...[heading('Skills'), pw.Text(d.cv.skills.join(', '), style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.6, color: ink))],
        if (d.roles.isNotEmpty) heading('Experience'),
        for (final (role, bullets) in d.roles) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6, bottom: 2),
            child: pw.Text('${role.title} — ${role.company}${role.location.isEmpty ? '' : ', ${role.location}'}', style: pw.TextStyle(font: _bold, fontSize: 10.5, color: ink)),
          ),
          if (role.dates.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 3), child: pw.Text(role.dates, style: const pw.TextStyle(fontSize: 9.5, color: muted))),
          for (final b in bullets) bullet(b),
        ],
        if (d.projects.isNotEmpty) heading('Projects'),
        for (final pr in d.projects) ...[
          pw.Padding(padding: const pw.EdgeInsets.only(top: 5, bottom: 2), child: pw.Text(pr.name + (pr.link.isEmpty ? '' : ' — ${pr.link}'), style: pw.TextStyle(font: _bold, fontSize: 10.5, color: ink))),
          if (pr.description.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 2), child: pw.Text(pr.description, style: const pw.TextStyle(fontSize: 10, color: ink))),
          for (final b in pr.bullets) bullet(b),
        ],
        if (p.education.isNotEmpty) heading('Education'),
        for (final e in p.education)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: pw.Text([e.degree, e.institution, e.year].where((x) => x.isNotEmpty).join(' — '), style: const pw.TextStyle(fontSize: 10, color: ink)),
          ),
        if (p.certifications.isNotEmpty) ...[heading('Certifications'), for (final c in p.certifications) bullet(c)],
        if (p.languages.isNotEmpty) ...[heading('Languages'), pw.Text(p.languages.join(', '), style: const pw.TextStyle(fontSize: 10, color: ink))],
        if (d.cv.learning.isNotEmpty) ...[heading('Currently learning'), pw.Text(d.cv.learning.join(', '), style: const pw.TextStyle(fontSize: 10, color: ink))],
      ],
    ));
    return doc.save();
  }
}

/// Editable Word document with the same single-column structure.
class CvDocxBuilder {
  static String _esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s).replaceAll('"', '&quot;');

  static String _p(String text, {bool bold = false, double size = 10.5, String color = '111827', int spacingAfter = 60, bool caps = false, int indentLeft = 0, bool rule = false}) {
    final rPr = '<w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>${bold ? '<w:b/>' : ''}${caps ? '<w:caps/>' : ''}<w:color w:val="$color"/><w:sz w:val="${(size * 2).round()}"/></w:rPr>';
    final border = rule ? '<w:pBdr><w:bottom w:val="single" w:sz="4" w:space="1" w:color="D1D5DB"/></w:pBdr>' : '';
    final ind = indentLeft > 0 ? '<w:ind w:left="$indentLeft" w:hanging="200"/>' : '';
    return '<w:p><w:pPr>$border<w:spacing w:after="$spacingAfter"/>$ind</w:pPr><w:r>$rPr<w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p>';
  }

  static Uint8List build(CvDocument d) {
    final p = d.profile;
    final body = StringBuffer()
      ..write(_p(d.name, bold: true, size: 18, spacingAfter: 20))
      ..write(d.cv.headline.isEmpty ? '' : _p(d.cv.headline, size: 11.5, color: '4B5563', spacingAfter: 20))
      ..write(d.contactLine.isEmpty ? '' : _p(d.contactLine, size: 9.5, color: '4B5563', spacingAfter: 120));
    void heading(String t) => body.write(_p(t, bold: true, caps: true, size: 10.5, spacingAfter: 80, rule: true));
    void bullet(String t) => body.write(_p('•  $t', indentLeft: 360, spacingAfter: 40));

    if (d.cv.summary.isNotEmpty) {
      heading('Summary');
      body.write(_p(d.cv.summary, spacingAfter: 120));
    }
    if (d.cv.skills.isNotEmpty) {
      heading('Skills');
      body.write(_p(d.cv.skills.join(', '), spacingAfter: 120));
    }
    if (d.roles.isNotEmpty) heading('Experience');
    for (final (role, bullets) in d.roles) {
      body.write(_p('${role.title} — ${role.company}${role.location.isEmpty ? '' : ', ${role.location}'}', bold: true, spacingAfter: 0));
      if (role.dates.isNotEmpty) body.write(_p(role.dates, size: 9.5, color: '4B5563', spacingAfter: 40));
      bullets.forEach(bullet);
    }
    if (d.projects.isNotEmpty) heading('Projects');
    for (final pr in d.projects) {
      body.write(_p(pr.name + (pr.link.isEmpty ? '' : ' — ${pr.link}'), bold: true, spacingAfter: 20));
      if (pr.description.isNotEmpty) body.write(_p(pr.description, spacingAfter: 20));
      pr.bullets.forEach(bullet);
    }
    if (p.education.isNotEmpty) heading('Education');
    for (final e in p.education) {
      body.write(_p([e.degree, e.institution, e.year].where((x) => x.isNotEmpty).join(' — ')));
    }
    if (p.certifications.isNotEmpty) {
      heading('Certifications');
      p.certifications.forEach(bullet);
    }
    if (p.languages.isNotEmpty) {
      heading('Languages');
      body.write(_p(p.languages.join(', ')));
    }
    if (d.cv.learning.isNotEmpty) {
      heading('Currently learning');
      body.write(_p(d.cv.learning.join(', ')));
    }

    final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>$body'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1000" w:right="1000" w:bottom="1000" w:left="1000" w:header="0" w:footer="0" w:gutter="0"/></w:sectPr>'
        '</w:body></w:document>';
    const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '</Types>';
    const rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '</Relationships>';
    final core = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>${_esc(d.name)} CV</dc:title><dc:creator>${_esc(d.name)}</dc:creator></cp:coreProperties>';

    final archive = Archive()
      ..addFile(ArchiveFile.string('[Content_Types].xml', contentTypes))
      ..addFile(ArchiveFile.string('_rels/.rels', rels))
      ..addFile(ArchiveFile.string('docProps/core.xml', core))
      ..addFile(ArchiveFile.string('word/document.xml', document));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}
