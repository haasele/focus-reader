import 'dart:typed_data';
import 'dart:convert';
import 'package:epub_view/epub_view.dart' as epub_parser;
import 'package:html/parser.dart' as html_parser;
import 'package:syncfusion_flutter_pdf/pdf.dart' deferred as pdf;
import 'package:archive/archive.dart';

/// Result of parsing a book file
class ParsedBookResult {
  final String text;
  final String? title;
  final String? author;
  final String fileType;

  ParsedBookResult({
    required this.text,
    this.title,
    this.author,
    required this.fileType,
  });
}

/// Service for parsing various book file formats (EPUB, PDF, TXT)
class FileParserService {
  static final FileParserService _instance = FileParserService._internal();
  factory FileParserService() => _instance;
  FileParserService._internal();

  // Cache for parsed EPUB books to avoid re-parsing
  final Map<String, epub_parser.EpubBook> _epubCache = {};

  /// Parse a book file based on its extension
  Future<ParsedBookResult> parseBook({
    required Uint8List bytes,
    required String extension,
    String? fallbackTitle,
  }) async {
    final ext = extension.toLowerCase();

    if (ext == 'epub') {
      return await _parseEpub(bytes, fallbackTitle: fallbackTitle);
    } else if (ext == 'pdf') {
      return await _parsePdf(bytes);
    } else if (ext == 'txt') {
      return await _parseTxt(bytes);
    } else {
      throw UnsupportedError('Unsupported file type: $ext');
    }
  }

  /// Parse EPUB file (with fallback to manual parsing)
  Future<ParsedBookResult> _parseEpub(
    Uint8List bytes, {
    String? fallbackTitle,
  }) async {
    // Try using epub_view library first
    try {
      final book = await epub_parser.EpubReader.readBook(bytes);
      final text = _extractTextFromEpubBook(book);
      return ParsedBookResult(
        text: text,
        title: book.Title ?? fallbackTitle,
        author: book.Author,
        fileType: 'epub',
      );
    } catch (e) {
      // If epub_view fails (e.g., missing META-INF/container.xml), try manual parsing
      if (e.toString().contains('META-INF/container.xml') ||
          e.toString().contains('not found in archive')) {
        try {
          return await _parseEpubManually(bytes, fallbackTitle: fallbackTitle);
        } catch (manualError) {
          throw Exception(
            'Failed to parse EPUB: ${manualError.toString()}',
          );
        }
      } else {
        rethrow;
      }
    }
  }

  /// Extract text from EPUB book using epub_view
  String _extractTextFromEpubBook(epub_parser.EpubBook book) {
    final buffer = StringBuffer();
    if (book.Chapters != null) {
      for (var chapter in book.Chapters!) {
        _extractTextFromEpubChapter(chapter, buffer);
      }
    }
    return buffer.toString();
  }

  /// Extract text from EPUB chapter recursively
  void _extractTextFromEpubChapter(
    epub_parser.EpubChapter chapter,
    StringBuffer buffer,
  ) {
    if (chapter.HtmlContent != null) {
      try {
        final document = html_parser.parse(chapter.HtmlContent);
        final text = document.body?.text ?? "";
        if (text.isNotEmpty) {
          buffer.write(text);
          buffer.write(" ");
        }
      } catch (e) {
        // Skip chapters that can't be parsed
      }
    }
    if (chapter.SubChapters != null) {
      for (var sub in chapter.SubChapters!) {
        _extractTextFromEpubChapter(sub, buffer);
      }
    }
  }

  /// Manual EPUB parser using archive library (fallback for web/complex EPUBs)
  Future<ParsedBookResult> _parseEpubManually(
    Uint8List bytes, {
    String? fallbackTitle,
  }) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final buffer = StringBuffer();
    String? title;
    String? author;
    List<String>? spineOrder;
    String? opfBasePath;

    // Find and parse content.opf for metadata AND spine (reading order)
    ArchiveFile? opfFile;
    for (var file in archive.files) {
      if (file.name.toLowerCase().endsWith('.opf')) {
        opfFile = file;
        // Get the base path of the OPF file (e.g., "OEBPS/")
        final lastSlash = file.name.lastIndexOf('/');
        opfBasePath = lastSlash > 0 ? file.name.substring(0, lastSlash + 1) : '';
        break;
      }
    }

    if (opfFile != null && opfFile.content != null) {
      try {
        final opfContent = utf8.decode(opfFile.content as List<int>);
        
        // Extract title from OPF
        final titleMatch = RegExp(
          r'<dc:title[^>]*>([^<]+)</dc:title>',
          caseSensitive: false,
        ).firstMatch(opfContent);
        if (titleMatch != null) {
          title = titleMatch.group(1);
        }
        
        // Extract author from OPF
        final authorMatch = RegExp(
          r'<dc:creator[^>]*>([^<]+)</dc:creator>',
          caseSensitive: false,
        ).firstMatch(opfContent);
        if (authorMatch != null) {
          author = authorMatch.group(1);
        }

        // Extract manifest (id -> href mapping)
        final manifest = <String, String>{};
        final manifestRegex = RegExp(
          r'<item[^>]+id="([^"]+)"[^>]+href="([^"]+)"',
          caseSensitive: false,
        );
        for (final match in manifestRegex.allMatches(opfContent)) {
          manifest[match.group(1)!] = match.group(2)!;
        }
        // Also try reversed order (href before id)
        final manifestRegex2 = RegExp(
          r'<item[^>]+href="([^"]+)"[^>]+id="([^"]+)"',
          caseSensitive: false,
        );
        for (final match in manifestRegex2.allMatches(opfContent)) {
          manifest[match.group(2)!] = match.group(1)!;
        }

        // Extract spine (reading order)
        final spineRegex = RegExp(
          r'<itemref[^>]+idref="([^"]+)"',
          caseSensitive: false,
        );
        
        spineOrder = [];
        for (final match in spineRegex.allMatches(opfContent)) {
          final idref = match.group(1)!;
          final href = manifest[idref];
          if (href != null) {
            // Construct full path relative to OPF location
            spineOrder.add('$opfBasePath$href');
          }
        }
      } catch (e) {
        // If OPF parsing fails, continue without spine order
      }
    }

    // Build a map of filename -> ArchiveFile for quick lookup
    final fileMap = <String, ArchiveFile>{};
    for (var file in archive.files) {
      fileMap[file.name] = file;
      // Also add lowercase version for case-insensitive matching
      fileMap[file.name.toLowerCase()] = file;
    }

    // Get list of HTML files to process
    List<String> orderedFiles;
    
    if (spineOrder != null && spineOrder.isNotEmpty) {
      // Use spine order (correct reading order from OPF)
      orderedFiles = spineOrder;
    } else {
      // Fallback: sort HTML files naturally by name
      final htmlFiles = <String>[];
      for (var file in archive.files) {
        final name = file.name.toLowerCase();
        if (name.endsWith('.html') || name.endsWith('.xhtml') || name.endsWith('.htm')) {
          htmlFiles.add(file.name);
        }
      }
      // Natural sort: part1, part2, ..., part10 (not part1, part10, part2)
      htmlFiles.sort((a, b) => _naturalCompare(a, b));
      orderedFiles = htmlFiles;
    }

    // Extract text in correct order
    for (var fileName in orderedFiles) {
      final file = fileMap[fileName] ?? fileMap[fileName.toLowerCase()];
      if (file != null && file.content != null) {
        try {
          final htmlContent = utf8.decode(file.content as List<int>);
          final document = html_parser.parse(htmlContent);
          final text = document.body?.text ?? "";
          if (text.isNotEmpty) {
            buffer.write(text);
            buffer.write(" ");
          }
        } catch (e) {
          // Skip files that can't be parsed
        }
      }
    }

    return ParsedBookResult(
      text: buffer.toString(),
      title: title ?? fallbackTitle,
      author: author,
      fileType: 'epub',
    );
  }

  /// Natural sort comparison (handles numbers correctly)
  int _naturalCompare(String a, String b) {
    final regExp = RegExp(r'(\d+)|(\D+)');
    final partsA = regExp.allMatches(a).toList();
    final partsB = regExp.allMatches(b).toList();
    
    for (var i = 0; i < partsA.length && i < partsB.length; i++) {
      final partA = partsA[i].group(0)!;
      final partB = partsB[i].group(0)!;
      
      final numA = int.tryParse(partA);
      final numB = int.tryParse(partB);
      
      if (numA != null && numB != null) {
        final cmp = numA.compareTo(numB);
        if (cmp != 0) return cmp;
      } else {
        final cmp = partA.toLowerCase().compareTo(partB.toLowerCase());
        if (cmp != 0) return cmp;
      }
    }
    
    return partsA.length.compareTo(partsB.length);
  }

  /// Parse PDF file
  Future<ParsedBookResult> _parsePdf(Uint8List bytes) async {
    // Load PDF library if not already loaded
    await pdf.loadLibrary();

    try {
      final document = pdf.PdfDocument(inputBytes: bytes);
      final text = pdf.PdfTextExtractor(document).extractText();
      document.dispose();
      return ParsedBookResult(
        text: text,
        fileType: 'pdf',
      );
    } catch (e) {
      throw Exception(
        'Fehler beim Lesen der PDF. Ist sie verschlüsselt? ${e.toString()}',
      );
    }
  }

  /// Parse TXT file
  Future<ParsedBookResult> _parseTxt(Uint8List bytes) async {
    try {
      final text = utf8.decode(bytes);
      return ParsedBookResult(
        text: text,
        fileType: 'txt',
      );
    } catch (e) {
      // Try with different encoding if UTF-8 fails
      try {
        final text = latin1.decode(bytes);
        return ParsedBookResult(
          text: text,
          fileType: 'txt',
        );
      } catch (e2) {
        throw Exception(
          'Fehler beim Lesen der Textdatei: ${e.toString()}',
        );
      }
    }
  }

  /// Clear EPUB cache (useful for memory management)
  void clearCache() {
    _epubCache.clear();
  }
}
