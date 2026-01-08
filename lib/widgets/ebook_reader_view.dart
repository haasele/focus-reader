import 'package:flutter/material.dart';
import 'package:epub_view/epub_view.dart' as epub_parser;
import 'dart:typed_data';

enum ReaderMode { scroll, pageTurn }

class EbookReaderView extends StatefulWidget {
  final Uint8List epubBytes;
  final int currentWordIndex;
  final int totalWords;
  final Function()? onShowRSVP;

  const EbookReaderView({
    super.key,
    required this.epubBytes,
    required this.currentWordIndex,
    required this.totalWords,
    this.onShowRSVP,
  });

  @override
  State<EbookReaderView> createState() => _EbookReaderViewState();
}

class _EbookReaderViewState extends State<EbookReaderView> {
  epub_parser.EpubController? _controller;
  bool _isLoading = true;
  String? _errorMessage;
  ReaderMode _readerMode = ReaderMode.scroll;

  // For page turn mode
  epub_parser.EpubBook? _book;
  List<epub_parser.EpubChapter> _chapters = [];
  PageController? _pageController;
  int _currentChapterIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadEpub();
  }

  Future<void> _loadEpub() async {
    try {
      final book = await epub_parser.EpubReader.readBook(widget.epubBytes);
      _book = book;

      // Flatten chapters for page view
      _chapters = [];
      if (book.Chapters != null) {
        for (var chapter in book.Chapters!) {
          _flattenChapters(chapter, _chapters);
        }
      }

      final controller = epub_parser.EpubController(
        document: Future.value(book),
      );

      _pageController = PageController();

      if (mounted) {
        setState(() {
          _controller = controller;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('EPUB load error: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Fehler beim Laden des E-Book Viewers:\n$e\n\n'
              'Der Speed-Modus funktioniert trotzdem.';
        });
      }
    }
  }

  void _flattenChapters(
    epub_parser.EpubChapter chapter,
    List<epub_parser.EpubChapter> list,
  ) {
    list.add(chapter);
    if (chapter.SubChapters != null) {
      for (var sub in chapter.SubChapters!) {
        _flattenChapters(sub, list);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller == null || _book == null) {
      return _buildErrorView();
    }

    return Stack(
      children: [
        // Reader content
        _readerMode == ReaderMode.scroll
            ? _buildScrollReader()
            : _buildPageTurnReader(),

        // Top bar with mode toggle
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.7), Colors.transparent],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildModeChip(
                    icon: Icons.swap_vert,
                    label: 'Scrollen',
                    isSelected: _readerMode == ReaderMode.scroll,
                    onTap: () =>
                        setState(() => _readerMode = ReaderMode.scroll),
                  ),
                  const SizedBox(width: 8),
                  _buildModeChip(
                    icon: Icons.auto_stories,
                    label: 'Blättern',
                    isSelected: _readerMode == ReaderMode.pageTurn,
                    onTap: () =>
                        setState(() => _readerMode = ReaderMode.pageTurn),
                  ),
                ],
              ),
            ),
          ),
        ),

        // FAB to return to Speed Reader
        if (widget.onShowRSVP != null)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: widget.onShowRSVP,
              tooltip: 'Speed Reader',
              child: const Icon(Icons.speed),
            ),
          ),
      ],
    );
  }

  Widget _buildModeChip({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey[800],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollReader() {
    return epub_parser.EpubView(controller: _controller!);
  }

  Widget _buildPageTurnReader() {
    if (_chapters.isEmpty) {
      return const Center(child: Text('Keine Kapitel gefunden'));
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: _chapters.length,
      onPageChanged: (index) {
        setState(() => _currentChapterIndex = index);
      },
      itemBuilder: (context, index) {
        final chapter = _chapters[index];
        return _buildChapterPage(chapter, index, _currentChapterIndex == index);
      },
    );
  }

  Widget _buildChapterPage(
    epub_parser.EpubChapter chapter,
    int index,
    bool isCurrent,
  ) {
    // Parse HTML content
    String content = '';
    if (chapter.HtmlContent != null) {
      // Simple HTML stripping - extract text
      content = chapter.HtmlContent!
          .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
          .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          // Chapter title
          if (chapter.Title != null && chapter.Title!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 16),
              child: Text(
                chapter.Title!,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Text(
                content,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.6,
                  color: Colors.grey[300],
                ),
              ),
            ),
          ),
          // Page indicator
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (index > 0)
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _pageController?.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
                  )
                else
                  const SizedBox(width: 48),
                Text(
                  'Kapitel ${index + 1} / ${_chapters.length}',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                if (index < _chapters.length - 1)
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _pageController?.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
                  )
                else
                  const SizedBox(width: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Fehler beim Laden des E-Books',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[400]),
            ),
            if (widget.onShowRSVP != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: widget.onShowRSVP,
                icon: const Icon(Icons.speed),
                label: const Text('Speed Reader öffnen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
