import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:epub_view/epub_view.dart' as epub_parser;
import 'package:html/parser.dart' as html_parser;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:archive/archive.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'models/book_metadata.dart';
import 'services/storage_service.dart';
import 'services/book_service.dart';
import 'services/theme_service.dart';
import 'widgets/book_list_drawer.dart';
import 'widgets/page_preview_panel.dart';
import 'widgets/ebook_reader_view.dart';
import 'widgets/settings_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeService = ThemeService();
  await themeService.loadSettings();
  runApp(RSVPApp(themeService: themeService));
}

class RSVPApp extends StatelessWidget {
  final ThemeService themeService;

  const RSVPApp({super.key, required this.themeService});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // Update theme service with dynamic colors
        if (lightDynamic != null) {
          themeService.setDynamicPrimaryColor(lightDynamic.primary);
        }

        return ListenableBuilder(
          listenable: themeService,
          builder: (context, _) {
            return MaterialApp(
              title: 'Focus Reader',
              debugShowCheckedModeBanner: false,
              theme: themeService.getLightTheme(lightDynamic),
              darkTheme: themeService.getDarkTheme(darkDynamic),
              themeMode: themeService.flutterThemeMode,
              home: RSVPReaderScreen(themeService: themeService),
            );
          },
        );
      },
    );
  }
}

// Layout-Modi
enum LayoutMode { rsvpOnly, splitView, ebookOnly }

class RSVPReaderScreen extends StatefulWidget {
  final ThemeService themeService;

  const RSVPReaderScreen({super.key, required this.themeService});

  @override
  State<RSVPReaderScreen> createState() => _RSVPReaderScreenState();
}

class _RSVPReaderScreenState extends State<RSVPReaderScreen> {
  // --- State ---
  List<String> _words = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  double _wpm = 300;
  Timer? _timer;
  bool _isLoading = false;
  String? _bookTitle;
  String? _currentBookId;
  Uint8List? _currentBookBytes;

  // Layout modes
  LayoutMode _layoutMode = LayoutMode.rsvpOnly;

  // Settings
  bool _longWordDelay = true;

  final RegExp _whitespaceRegex = RegExp(r'\s+');
  final StorageService _storageService = StorageService();
  int _lastSavedIndex = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _saveProgress();
    super.dispose();
  }

  Future<void> _saveProgress() async {
    if (_currentBookId != null && _currentIndex != _lastSavedIndex) {
      try {
        await _storageService.updateProgress(_currentBookId!, _currentIndex);
        _lastSavedIndex = _currentIndex;
      } catch (e) {
        // Ignore save errors
      }
    }
  }

  Future<void> _pickAndLoadFile() async {
    setState(() => _isLoading = true);

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub', 'pdf', 'txt'],
      );

      if (result != null) {
        String extension = result.files.single.extension?.toLowerCase() ?? "";
        String title = result.files.single.name;
        Uint8List? bytes = result.files.single.bytes;

        final titleLower = title.toLowerCase();
        if (extension == 'zip' &&
            (titleLower.endsWith('.epub') || titleLower.contains('.epub'))) {
          extension = 'epub';
        }

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
          throw Exception("Konnte die Datei nicht laden");
        }

        String extractedText = "";
        String? author;

        if (extension == 'epub') {
          try {
            var parsed = await _parseEpub(bytes);
            extractedText = parsed.text;
            title = parsed.title ?? title;
            author = parsed.author;
          } catch (e) {
            if (e.toString().contains('META-INF/container.xml') ||
                e.toString().contains('not found in archive')) {
              try {
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

        List<String> words = extractedText
            .split(_whitespaceRegex)
            .where((w) => w.isNotEmpty)
            .toList();

        if (words.isEmpty) throw Exception("Kein Text gefunden");

        final bookId =
            '${DateTime.now().millisecondsSinceEpoch}_${title.hashCode}';

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

        Uint8List? coverImage;
        if (extension == 'epub') {
          coverImage = await BookService.extractCoverFromEpub(bytes);
        } else if (extension == 'pdf') {
          coverImage = await BookService.extractCoverFromPdf(bytes);
        }

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
            // Ignore save errors
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

  Future<({String text, String? title, String? author})> _parseEpubManually(
    Uint8List bytes,
  ) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    StringBuffer buffer = StringBuffer();
    String? title;
    String? author;

    ArchiveFile? opfFile;
    for (var file in archive.files) {
      if (file.name.toLowerCase().endsWith('content.opf')) {
        opfFile = file;
        break;
      }
    }

    if (opfFile != null && opfFile.content != null) {
      final opfContent = utf8.decode(opfFile.content as List<int>);
      final titleMatch = RegExp(
        r'<dc:title[^>]*>([^<]+)</dc:title>',
        caseSensitive: false,
      ).firstMatch(opfContent);
      if (titleMatch != null) {
        title = titleMatch.group(1);
      }
      final authorMatch = RegExp(
        r'<dc:creator[^>]*>([^<]+)</dc:creator>',
        caseSensitive: false,
      ).firstMatch(opfContent);
      if (authorMatch != null) {
        author = authorMatch.group(1);
      }
    }

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
          // Skip unparsable files
        }
      }
    }

    return (text: buffer.toString(), title: title, author: author);
  }

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

  Future<String> _parsePdf(Uint8List bytes) async {
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      String text = PdfTextExtractor(document).extractText();
      document.dispose();
      return text;
    } catch (e) {
      return "Fehler beim Lesen der PDF.";
    }
  }

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
    _saveProgress();
  }

  void _reset() {
    _pause();
    setState(() => _currentIndex = 0);
    _saveProgress();
  }

  Future<void> _loadBook(String bookId) async {
    if (kIsWeb) return;

    setState(() => _isLoading = true);

    try {
      final metadata = await _storageService.getBookMetadata(bookId);
      final bytes = await _storageService.loadBook(bookId);

      String extractedText = "";
      String title = metadata.title;
      String? author = metadata.author;

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

      List<String> words = extractedText
          .split(_whitespaceRegex)
          .where((w) => w.isNotEmpty)
          .toList();

      if (words.isEmpty) throw Exception("Kein Text gefunden");

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

    int baseDelay = (60000 / _wpm).round();
    double multiplier = 1.0;

    if (currentWord.endsWith('.') ||
        currentWord.endsWith('!') ||
        currentWord.endsWith('?') ||
        currentWord.endsWith(':')) {
      multiplier = 2.5;
    } else if (currentWord.endsWith(',') || currentWord.endsWith(';')) {
      multiplier = 1.5;
    }

    if (_longWordDelay && currentWord.length > 9) {
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
        if (_currentIndex % 10 == 0) {
          _saveProgress();
        }
        _scheduleNextWord();
      }
    });
  }

  int _getOrpIndex(String word) {
    int len = word.length;
    if (len <= 1) return 0;
    if (len <= 3) return 1;
    return (len * 0.33).round().clamp(1, len - 1);
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingsPage(themeService: widget.themeService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_bookTitle ?? "Speed Reader"),
        leading: Builder(
          builder: (scaffoldContext) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Bibliothek',
            onPressed: () => Scaffold.of(scaffoldContext).openDrawer(),
          ),
        ),
        actions: [
          // Settings button
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Einstellungen',
            onPressed: _openSettings,
          ),
          // Overflow menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Mehr',
            onSelected: (value) {
              switch (value) {
                case 'open_file':
                  _pickAndLoadFile();
                  break;
                case 'reset':
                  if (_words.isNotEmpty) _reset();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'open_file',
                child: ListTile(
                  leading: Icon(Icons.folder_open, color: colorScheme.primary),
                  title: const Text('Datei öffnen'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (_words.isNotEmpty)
                PopupMenuItem<String>(
                  value: 'reset',
                  child: ListTile(
                    leading: Icon(Icons.refresh, color: colorScheme.primary),
                    title: const Text('Zurücksetzen'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
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
    final colorScheme = Theme.of(context).colorScheme;

    // Ebook Reader Only Mode
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

    // RSVP Only or Split View
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final previewWidth = screenWidth < 500
            ? screenWidth * 0.35
            : screenWidth < 800
            ? 180.0
            : 220.0;

        return Row(
          children: [
            // Page preview (Split View)
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
            // RSVP Reader area
            Expanded(
              child: Column(
                children: [
                  // Reading area
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

                  // Progress
                  if (_words.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "0",
                            style: TextStyle(color: colorScheme.outline),
                          ),
                          Text(
                            "${_words.length}",
                            style: TextStyle(color: colorScheme.outline),
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
                      style: TextStyle(color: colorScheme.outline),
                    ),
                  ],

                  const SizedBox(height: 10),

                  // Controls panel
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Layout mode buttons
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
                        // Settings: WPM & Long Words
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Geschwindigkeit",
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        "${_wpm.round()}",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: colorScheme.primary,
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
                                Text(
                                  "Lange Wörter",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colorScheme.onSurfaceVariant,
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
                          child: FilledButton.icon(
                            onPressed: _words.isNotEmpty ? _togglePlay : null,
                            icon: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                            ),
                            label: Text(
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
    final colorScheme = Theme.of(context).colorScheme;

    if (_words.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined, size: 64, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            "PDF / EPUB / TXT öffnen",
            style: TextStyle(fontSize: 18, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _pickAndLoadFile,
            icon: const Icon(Icons.folder_open),
            label: const Text('Datei auswählen'),
          ),
        ],
      );
    }
    if (_currentIndex >= _words.length) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            "Fertig!",
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
        ],
      );
    }

    String word = _words[_currentIndex];
    int orpIndex = _getOrpIndex(word);

    String part1 = word.substring(0, orpIndex);
    String focusChar = word[orpIndex];
    String part2 = word.substring(orpIndex + 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 40;

        final screenWidth = MediaQuery.of(this.context).size.width;
        double baseFontSize = screenWidth < 400
            ? 28.0
            : (screenWidth < 600 ? 36.0 : 52.0);

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
          color: colorScheme.onSurface,
          fontWeight: FontWeight.bold,
        );

        final redStyle = TextStyle(
          fontFamily: 'Courier New',
          fontSize: fontSize,
          color: colorScheme.primary,
          fontWeight: FontWeight.bold,
        );

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

        final centerX = constraints.maxWidth / 2;
        final focusCharLeft = centerX - focusCharWidth / 2;
        final part1Left = focusCharLeft - part1Width;
        final part2Left = focusCharLeft + focusCharWidth;
        final centerY = constraints.maxHeight / 2 - fontSize / 2;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (part1.isNotEmpty)
              Positioned(
                left: part1Left,
                top: centerY,
                child: Text(part1, style: textStyle),
              ),
            Positioned(
              left: focusCharLeft,
              top: centerY,
              child: Text(focusChar, style: redStyle),
            ),
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
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _layoutMode == mode;

    return FilledButton.tonal(
      onPressed: () {
        setState(() => _layoutMode = mode);
      },
      style: FilledButton.styleFrom(
        backgroundColor: isSelected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        foregroundColor: isSelected
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurfaceVariant,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(label)],
      ),
    );
  }
}
