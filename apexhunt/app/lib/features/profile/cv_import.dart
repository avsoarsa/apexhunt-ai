import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import '../../core/ai/llm.dart';
import '../../core/ai/prompts.dart';
import '../../core/models.dart';

/// Extracts plain text from a PDF, DOCX or TXT CV entirely on-device.
class CvTextExtractor {
  static Future<String> extract(Uint8List bytes, String fileName) async {
    final ext = fileName.toLowerCase().split('.').last;
    final text = switch (ext) {
      'pdf' => await _pdf(bytes),
      'docx' => _docx(bytes),
      'txt' || 'md' => utf8.decode(bytes, allowMalformed: true),
      _ => throw FormatException('Unsupported file type .$ext — use PDF, DOCX or TXT.'),
    };
    final cleaned = text.replaceAll('\r', '').replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    if (cleaned.length < 80) {
      throw const FormatException('Could not read text from this file. If it is a scanned image, paste your CV text instead.');
    }
    return cleaned;
  }

  static Future<String> _pdf(Uint8List bytes) async {
    final doc = await PdfDocument.openData(bytes);
    try {
      final buf = StringBuffer();
      for (final page in doc.pages) {
        final t = await page.loadText();
        if (t != null) buf.writeln(t.fullText);
      }
      return buf.toString();
    } finally {
      await doc.dispose();
    }
  }

  static String _docx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.findFile('word/document.xml');
    if (entry == null) throw const FormatException('Not a valid DOCX file.');
    final xml = XmlDocument.parse(utf8.decode(entry.content as List<int>));
    final buf = StringBuffer();
    for (final p in xml.findAllElements('w:p')) {
      final line = p.findAllElements('w:t').map((t) => t.innerText).join();
      final isBullet = p.findAllElements('w:numPr').isNotEmpty;
      if (line.trim().isNotEmpty) buf.writeln(isBullet ? '• ${line.trim()}' : line.trim());
    }
    return buf.toString();
  }
}

/// Turns CV text into a [MasterProfile] with the AI engine, falling back to a
/// simple offline heuristic when no engine is available.
class ProfileParser {
  static Future<MasterProfile> parseWithAi(LlmClient llm, String cvText) async {
    final res = await llm.complete([
      const ChatMsg.system(Prompts.parseCv),
      ChatMsg.user('CV TEXT:\n"""\n${cvText.length > 30000 ? cvText.substring(0, 30000) : cvText}\n"""'),
    ], json: true, maxTokens: 5000, temperature: 0, purpose: 'parse_cv');
    final j = parseJsonObject(res.content);
    final p = MasterProfile.fromJson(j)..rawText = cvText;
    _dedupeSkills(p);
    return p;
  }

  static void _dedupeSkills(MasterProfile p) {
    final seen = <String>{};
    p.skills = [
      for (final s in [...p.skills, for (final r in p.roles) ...r.skills])
        if (s.trim().isNotEmpty && seen.add(s.trim().toLowerCase())) s.trim()
    ];
  }

  static final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+');
  static final _phone = RegExp(r'\+?\d[\d\s().-]{7,}\d');
  static final _url = RegExp(r'(https?://\S+|(?:www\.)?(?:linkedin\.com|github\.com)/\S+)', caseSensitive: false);

  /// Offline fallback: contact details, a skills line and bullet points. The user
  /// completes the rest in the profile editor.
  static MasterProfile parseHeuristic(String text) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final contact = Contact(
      name: lines.isNotEmpty && lines.first.length < 60 && !_email.hasMatch(lines.first) ? lines.first : '',
      email: _email.firstMatch(text)?.group(0) ?? '',
      phone: _phone.firstMatch(text)?.group(0)?.trim() ?? '',
      links: _url.allMatches(text).map((m) => m.group(0)!).toSet().toList(),
    );
    final skills = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i].toLowerCase();
      if (l.startsWith('skills') || l.startsWith('technical skills') || l.startsWith('core skills') || l.startsWith('tools')) {
        final body = lines[i].contains(':') ? lines[i].split(':').skip(1).join(':') : (i + 1 < lines.length ? lines[i + 1] : '');
        skills.addAll(body.split(RegExp(r'[,|•·;/]')).map((s) => s.trim()).where((s) => s.length > 1 && s.length < 40));
      }
    }
    final bullets = lines.where((l) => RegExp(r'^[•\-*▪●◦]\s*').hasMatch(l)).map((l) => l.replaceFirst(RegExp(r'^[•\-*▪●◦]\s*'), '')).toList();
    return MasterProfile(
      contact: contact,
      headline: lines.length > 1 && lines[1].length < 80 ? lines[1] : '',
      roles: bullets.isEmpty ? [] : [WorkRole(title: 'Most recent role', company: 'Edit company', bullets: bullets.take(10).toList())],
      skills: skills.toSet().toList(),
      rawText: text,
    );
  }
}
