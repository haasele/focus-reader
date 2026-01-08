import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert'; // Für Text-Decoding
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:epub_view/epub_view.dart' as epub_parser;
import 'package:html/parser.dart' as html_parser;
import 'package:syncfusion_flutter_pdf/pdf.dart'; // PDF Support
import 'package:archive/archive.dart';
import 'models/book_metadata.dart';
import 'services/storage_service.dart';
import 'services/book_service.dart';
import 'widgets/book_list_drawer.dart';
import 'widgets/page_preview_panel.dart';
import 'widgets/ebook_reader_view.dart';

void main() {
  runApp(const RSVPApp());
}

class RSVPApp extends StatelessWidget {
  const RSVPApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter RSVP Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF007ACC),
          secondary: Color(0xFFFF4444),
          surface: Color(0xFF252526),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return const Color(0xFF007ACC);
            }
            return Colors.grey;
          }),
          trackColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return const Color(0xFF007ACC).withOpacity(0.5);
            }
            return Colors.grey.withOpacity(0.3);
          }),
        ),
      ),
      home: const RSVPReaderScreen(),
    );
  }
}

// Layout-Modi
enum LayoutMode { rsvpOnly, splitView, ebookOnly }

class RSVPReaderScreen extends StatefulWidget {
  const RSVPReaderScreen({super.key});

  @override
  State<RSVPReaderScreen> createState() => _RSVPReaderScreenState();
}

class _RSVPReaderScreenState extends State<RSVPReaderScreen> {
  // --- Zustand ---
  List<String> _words = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  double _wpm = 300;
  Timer? _timer;
  bool _isLoading = false;
  String? _bookTitle;
  String? _currentBookId; // ID des aktuell geladenen Buches
  Uint8List? _currentBookBytes; // Bytes des aktuellen Buches (für EPUB Reader)

  // Layout-Modi
  LayoutMode _layoutMode = LayoutMode.rsvpOnly;

  // Neue Einstellung
  bool _longWordDelay = true; // Standardmäßig an

  final RegExp _whitespaceRegex = RegExp(r'\s+');
  final StorageService _storageService = StorageService();
  int _lastSavedIndex = 0; // Letzter gespeicherter Index für Debouncing

  @override
  void dispose() {
    _timer?.cancel();
    // Speichere Fortschritt beim Schließen
    _saveProgress();
    super.dispose();
  }

  // Fortschritt speichern (mit Debouncing)
  Future<void> _saveProgress() async {
    if (_currentBookId != null && _currentIndex != _lastSavedIndex) {
      try {
        await _storageService.updateProgress(_currentBookId!, _currentIndex);
        _lastSavedIndex = _currentIndex;
      } catch (e) {
        // Ignore save errors silently
      }
    }
  }

  // --- Logik: Datei laden & Parsen ---
  Future<void> _pickAndLoadFile() async {
    setState(() => _isLoading = true);

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'epub',
          'pdf',
          'txt',
        ], // .mobi ist komplex in Dart pur
      );

      if (result != null) {
        String extension = result.files.single.extension?.toLowerCase() ?? "";
        String title = result.files.single.name;
        Uint8List? bytes = result.files.single.bytes;

        // Fix: EPUB files are ZIP archives, so on web they may be detected as "zip"
        // Check filename extension as fallback - handle both .epub and .epub.zip cases
        final titleLower = title.toLowerCase();
        if (extension == 'zip' &&
            (titleLower.endsWith('.epub') || titleLower.contains('.epub'))) {
          extension = 'epub';
        }

        // On platforms where .bytes is null (like mobile/desktop), fallback to reading the file from path
        // CRITICAL: On web, accessing .path throws an exception, so we must check kIsWeb first
        if (bytes == null && !kIsWeb) {
          try {
            final path = result.files.single.path;
            if (path != null) {
              bytes = await File(path).readAsBytes();
            }
          } catch (e) {
            // Ignore path access errors
          }
        }

        if (bytes == null) {
          throw Exception(
            "Konnte die Datei nicht laden (keine Bytes verfügbar)",
          );
        }

        String extractedText = "";
        String? author;

        // Unterscheidung nach Dateityp
        if (extension == 'epub') {
          try {
            var parsed = await _parseEpub(bytes);
            extractedText = parsed.text;
            title = parsed.title ?? title;
            author = parsed.author;
          } catch (e) {
            // epub_view failed - try manual EPUB extraction using archive library
            if (e.toString().contains('META-INF/container.xml') ||
                e.toString().contains('not found in archive')) {
              try {
                // Manually extract text from EPUB using archive library
                var parsed = await _parseEpubManually(bytes);
                extractedText = parsed.text;
                title = parsed.title ?? title;
                author = parsed.author;
              } catch (manualError) {
                rethrow;
              }
            } else {
              rethrow;
            }
          }
        } else if (extension == 'pdf') {
          extractedText = await _parsePdf(bytes);
        } else if (extension == 'txt') {
          extractedText = utf8.decode(bytes);
        }

        // Text bereinigen und splitten
        List<String> words = extractedText
            .split(_whitespaceRegex)
            .where((w) => w.isNotEmpty)
            .toList();

        if (words.isEmpty) throw Exception("Kein Text gefunden");

        // Generiere eindeutige Book-ID
        final bookId =
            '${DateTime.now().millisecondsSinceEpoch}_${title.hashCode}';

        // Erstelle Metadata
        final metadata = BookMetadata(
          id: bookId,
          title: title,
          author: author,
          filePath: 'book.$extension',
          totalWords: words.length,
          lastReadIndex: 0,
          lastOpened: DateTime.now(),
          fileType: extension,
        );

        // Extrahiere Cover-Bild
        Uint8List? coverImage;
        if (extension == 'epub') {
          coverImage = await BookService.extractCoverFromEpub(bytes);
        } else if (extension == 'pdf') {
          coverImage = await BookService.extractCoverFromPdf(bytes);
        }

        // Speichere Buch (nur wenn nicht Web, da Web keine lokale Dateispeicherung hat)
        if (!kIsWeb) {
          try {
            await _storageService.saveBook(
              bookId: bookId,
              fileBytes: bytes,
              fileName: 'book.$extension',
              metadata: metadata,
              coverImage: coverImage,
            );
          } catch (e) {
            // Ignore save errors, continue loading
          }
        }

        setState(() {
          _words = words;
          _currentIndex = 0;
          _bookTitle = title;
          _currentBookId = bookId;
          _currentBookBytes = extension == 'epub' ? bytes : null;
          _isPlaying = false;
          _lastSavedIndex = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Manual EPUB parser using archive library (fallback for web)
  Future<({String text, String? title, String? author})> _parseEpubManually(
    Uint8List bytes,
  ) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    StringBuffer buffer = StringBuffer();
    String? title;
    String? author;

    // Find and parse content.opf for metadata
    ArchiveFile? opfFile;
    for (var file in archive.files) {
      if (file.name.toLowerCase().endsWith('content.opf')) {
        opfFile = file;
        break;
      }
    }

    if (opfFile != null && opfFile.content != null) {
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
    }

    // Extract text from HTML/XHTML files in OEBPS or similar folders
    for (var file in archive.files) {
      final name = file.name.toLowerCase();
      if ((name.endsWith('.html') ||
              name.endsWith('.xhtml') ||
              name.endsWith('.htm')) &&
          file.content != null) {
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

    return (text: buffer.toString(), title: title, author: author);
  }

  // Parser für EPUB
  Future<({String text, String? title, String? author})> _parseEpub(
    Uint8List bytes,
  ) async {
    epub_parser.EpubBook book = await epub_parser.EpubReader.readBook(bytes);
    StringBuffer buffer = StringBuffer();

    if (book.Chapters != null) {
      for (var chapter in book.Chapters!) {
        _extractTextFromEpubChapter(chapter, buffer);
      }
    }
    return (text: buffer.toString(), title: book.Title, author: book.Author);
  }

  void _extractTextFromEpubChapter(
    epub_parser.EpubChapter chapter,
    StringBuffer buffer,
  ) {
    if (chapter.HtmlContent != null) {
      var document = html_parser.parse(chapter.HtmlContent);
      buffer.write(document.body?.text ?? "");
      buffer.write(" ");
    }
    if (chapter.SubChapters != null) {
      for (var sub in chapter.SubChapters!) {
        _extractTextFromEpubChapter(sub, buffer);
      }
    }
  }

  // Parser für PDF
  Future<String> _parsePdf(Uint8List bytes) async {
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      String text = PdfTextExtractor(document).extractText();
      document.dispose();
      return text;
    } catch (e) {
      return "Fehler beim Lesen der PDF. Ist sie verschlüsselt?";
    }
  }

  // --- Logik: RSVP & Timer ---

  void _togglePlay() {
    if (_words.isEmpty) return;
    _isPlaying ? _pause() : _play();
  }

  void _play() {
    setState(() => _isPlaying = true);
    _scheduleNextWord();
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _isPlaying = false);
    // Speichere Fortschritt bei Pause
    _saveProgress();
  }

  void _reset() {
    _pause();
    setState(() => _currentIndex = 0);
    _saveProgress();
  }

  // Lade gespeichertes Buch
  Future<void> _loadBook(String bookId) async {
    if (kIsWeb) {
      // Web unterstützt keine lokale Dateispeicherung
      return;
    }

    setState(() => _isLoading = true);

    try {
      final metadata = await _storageService.getBookMetadata(bookId);
      final bytes = await _storageService.loadBook(bookId);

      String extractedText = "";
      String title = metadata.title;
      String? author = metadata.author;

      // Parse based on file type
      if (metadata.fileType == 'epub') {
        try {
          var parsed = await _parseEpub(bytes);
          extractedText = parsed.text;
          title = parsed.title ?? title;
          author = parsed.author ?? author;
        } catch (e) {
          if (e.toString().contains('META-INF/container.xml') ||
              e.toString().contains('not found in archive')) {
            try {
              var parsed = await _parseEpubManually(bytes);
              extractedText = parsed.text;
              title = parsed.title ?? title;
              author = parsed.author ?? author;
            } catch (manualError) {
              rethrow;
            }
          } else {
            rethrow;
          }
        }
      } else if (metadata.fileType == 'pdf') {
        extractedText = await _parsePdf(bytes);
      } else if (metadata.fileType == 'txt') {
        extractedText = utf8.decode(bytes);
      }

      // Text bereinigen und splitten
      List<String> words = extractedText
          .split(_whitespaceRegex)
          .where((w) => w.isNotEmpty)
          .toList();

      if (words.isEmpty) throw Exception("Kein Text gefunden");

      // Lade gespeicherten Fortschritt
      final savedIndex = metadata.lastReadIndex;
      final startIndex = savedIndex < words.length ? savedIndex : 0;

      setState(() {
        _words = words;
        _currentIndex = startIndex;
        _bookTitle = title;
        _currentBookId = bookId;
        _currentBookBytes = metadata.fileType == 'epub' ? bytes : null;
        _isPlaying = false;
        _lastSavedIndex = startIndex;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler beim Laden: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _scheduleNextWord() {
    if (!_isPlaying) return;

    if (_currentIndex >= _words.length) {
      _pause();
      _currentIndex = 0;
      return;
    }

    String currentWord = _words[_currentIndex];

    // 1. Basis-Intervall
    int baseDelay = (60000 / _wpm).round();
    double multiplier = 1.0;

    // 2. Satzzeichen-Verzögerung
    if (currentWord.endsWith('.') ||
        currentWord.endsWith('!') ||
        currentWord.endsWith('?') ||
        currentWord.endsWith(':')) {
      multiplier = 2.5;
    } else if (currentWord.endsWith(',') || currentWord.endsWith(';')) {
      multiplier = 1.5;
    }

    // 3. NEU: Lange Worte verzögern
    // Wir definieren "lang" als > 10 Zeichen (anpassbar)
    if (_longWordDelay && currentWord.length > 9) {
      // Wenn wir schon eine Pause haben (Satzzeichen), verlängern wir nicht nochmal drastisch
      // Sonst addieren wir Zeit hinzu.
      multiplier = multiplier == 1.0 ? 1.5 : multiplier * 1.2;
    } else if (currentWord.length < 3) {
      multiplier *= 0.8;
    }

    int finalDelay = (baseDelay * multiplier).round();

    _timer = Timer(Duration(milliseconds: finalDelay), () {
      if (mounted && _isPlaying) {
        setState(() {
          _currentIndex++;
        });
        // Speichere Fortschritt alle 10 Wörter
        if (_currentIndex % 10 == 0) {
          _saveProgress();
        }
        _scheduleNextWord();
      }
    });
  }

  // --- Logik: ORP (Optimal Recognition Point) ---
  // The ORP should be around 30-35% into the word for optimal reading
  int _getOrpIndex(String word) {
    int len = word.length;
    if (len <= 1) return 0;
    if (len <= 3) return 1;
    // For longer words, position at roughly 30-35% into the word
    return (len * 0.33).round().clamp(1, len - 1);
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_bookTitle ?? "Speed Reader"),
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: Builder(
          builder: (scaffoldContext) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(scaffoldContext).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _pickAndLoadFile,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _words.isNotEmpty ? _reset : null,
          ),
        ],
      ),
      drawer: BookListDrawer(
        onBookSelected: _loadBook,
        onAddNewBook: _pickAndLoadFile,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Ebook Reader Only Mode - show when user selects Reader mode and has EPUB
    if (_currentBookBytes != null && _layoutMode == LayoutMode.ebookOnly) {
      return EbookReaderView(
        epubBytes: _currentBookBytes!,
        currentWordIndex: _currentIndex,
        totalWords: _words.length,
        onShowRSVP: () {
          setState(() => _layoutMode = LayoutMode.rsvpOnly);
        },
      );
    }

    // RSVP Only oder Split View
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate preview panel width based on available space
        final screenWidth = constraints.maxWidth;
        final previewWidth = screenWidth < 500
            ? screenWidth *
                  0.35 // 35% on small screens
            : screenWidth < 800
            ? 180.0 // Fixed 180px on medium screens
            : 220.0; // Fixed 220px on large screens

        return Row(
          children: [
            // Seitenvorschau (nur wenn Split View und EPUB/PDF)
            if (_layoutMode == LayoutMode.splitView &&
                (_currentBookBytes != null || _words.isNotEmpty))
              SizedBox(
                width: previewWidth,
                child: PagePreviewPanel(
                  words: _words,
                  currentWordIndex: _currentIndex,
                  onPageSelected: (wordIndex) {
                    _pause();
                    setState(() => _currentIndex = wordIndex);
                  },
                  epubBytes: _currentBookBytes,
                  width: previewWidth,
                ),
              ),
            // RSVP Reader Bereich
            Expanded(
              child: Column(
                children: [
                  // Lesebereich
                  Expanded(
                    flex: 4,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Center(
                        child: _isLoading
                            ? const CircularProgressIndicator()
                            : _buildWordDisplay(),
                      ),
                    ),
                  ),

                  // Fortschritt
                  if (_words.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("0", style: TextStyle(color: Colors.grey[600])),
                          Text(
                            "${_words.length}",
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    Slider(
                      value: _currentIndex.toDouble(),
                      min: 0,
                      max: _words.isEmpty ? 100 : _words.length.toDouble(),
                      onChanged: (val) {
                        _pause();
                        setState(() => _currentIndex = val.toInt());
                      },
                    ),
                    Text(
                      _words.isEmpty
                          ? ""
                          : "${(_currentIndex / _words.length * 100).toStringAsFixed(1)} %",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],

                  const SizedBox(height: 10),

                  // Kontrollbereich
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Layout-Modus Buttons
                        if (_words.isNotEmpty) ...[
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildLayoutModeButton(
                                icon: Icons.speed,
                                label: 'Speed',
                                mode: LayoutMode.rsvpOnly,
                              ),
                              _buildLayoutModeButton(
                                icon: Icons.view_column,
                                label: 'Vorschau',
                                mode: LayoutMode.splitView,
                              ),
                              // E-Book mode only for EPUBs
                              if (_currentBookBytes != null)
                                _buildLayoutModeButton(
                                  icon: Icons.menu_book,
                                  label: 'E-Book',
                                  mode: LayoutMode.ebookOnly,
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        // Einstellungen: WPM & Long Words
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Geschwindigkeit",
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        "${_wpm.round()}",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      ),
                                      Expanded(
                                        child: Slider(
                                          value: _wpm,
                                          min: 60,
                                          max: 1200,
                                          onChanged: (val) =>
                                              setState(() => _wpm = val),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              children: [
                                const Text(
                                  "Länger stoppen bei langen Worten",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                                Switch(
                                  value: _longWordDelay,
                                  onChanged: (val) =>
                                      setState(() => _longWordDelay = val),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Play Button
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: _words.isNotEmpty ? _togglePlay : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: _isPlaying ? 0 : 4,
                            ),
                            child: Text(
                              _isPlaying ? "Pausieren" : "Starten",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWordDisplay() {
    if (_words.isEmpty) {
      return const Text(
        "PDF / EPUB / TXT öffnen",
        style: TextStyle(fontSize: 20, color: Colors.grey),
      );
    }
    if (_currentIndex >= _words.length) {
      return const Text("Fertig!", style: TextStyle(fontSize: 40));
    }

    String word = _words[_currentIndex];
    int orpIndex = _getOrpIndex(word);

    String part1 = word.substring(0, orpIndex);
    String focusChar = word[orpIndex];
    String part2 = word.substring(orpIndex + 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 40; // padding

        // Start with base font size based on screen width
        final screenWidth = MediaQuery.of(this.context).size.width;
        double baseFontSize = screenWidth < 400
            ? 28.0
            : (screenWidth < 600 ? 36.0 : 52.0);

        // Calculate required width and scale down if needed
        double fontSize = baseFontSize;
        double totalWidth;

        do {
          final testStyle = TextStyle(
            fontFamily: 'Courier New',
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          );
          final wordPainter = TextPainter(
            text: TextSpan(text: word, style: testStyle),
            textDirection: TextDirection.ltr,
          );
          wordPainter.layout();
          totalWidth = wordPainter.width;

          if (totalWidth > availableWidth && fontSize > 16) {
            fontSize -= 2;
          } else {
            break;
          }
        } while (fontSize > 16);

        final textStyle = TextStyle(
          fontFamily: 'Courier New',
          fontSize: fontSize,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        );

        final redStyle = TextStyle(
          fontFamily: 'Courier New',
          fontSize: fontSize,
          color: Theme.of(this.context).colorScheme.secondary,
          fontWeight: FontWeight.bold,
        );

        // Measure exact widths
        final part1Painter = TextPainter(
          text: TextSpan(text: part1, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        part1Painter.layout();

        final focusCharPainter = TextPainter(
          text: TextSpan(text: focusChar, style: redStyle),
          textDirection: TextDirection.ltr,
        );
        focusCharPainter.layout();

        final part1Width = part1Painter.width;
        final focusCharWidth = focusCharPainter.width;

        // Center the red letter
        final centerX = constraints.maxWidth / 2;
        final focusCharLeft = centerX - focusCharWidth / 2;
        final part1Left = focusCharLeft - part1Width;
        final part2Left = focusCharLeft + focusCharWidth;

        // Vertical centering
        final centerY = constraints.maxHeight / 2 - fontSize / 2;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // part1 - left of red letter
            if (part1.isNotEmpty)
              Positioned(
                left: part1Left,
                top: centerY,
                child: Text(part1, style: textStyle),
              ),
            // Red letter - centered
            Positioned(
              left: focusCharLeft,
              top: centerY,
              child: Text(focusChar, style: redStyle),
            ),
            // part2 - right of red letter
            if (part2.isNotEmpty)
              Positioned(
                left: part2Left,
                top: centerY,
                child: Text(part2, style: textStyle),
              ),
          ],
        );
      },
    );
  }

  Widget _buildLayoutModeButton({
    required IconData icon,
    required String label,
    required LayoutMode mode,
  }) {
    final isSelected = _layoutMode == mode;
    return OutlinedButton.icon(
      onPressed: () {
        setState(() => _layoutMode = mode);
      },
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: isSelected
            ? Theme.of(context).colorScheme.primary
            : Colors.grey,
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey[700]!,
          width: isSelected ? 2 : 1,
        ),
        backgroundColor: isSelected
            ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
            : Colors.transparent,
      ),
    );
  }
}
