import 'package:flutter/material.dart';
import 'package:epub_view/epub_view.dart' as epub_parser;
import 'package:html/parser.dart' as html_parser;
import 'dart:typed_data';

class PagePreviewPanel extends StatefulWidget {
  final List<String> words;
  final int currentWordIndex;
  final Function(int wordIndex) onPageSelected;
  final Uint8List? epubBytes;
  final double? width;

  const PagePreviewPanel({
    super.key,
    required this.words,
    required this.currentWordIndex,
    required this.onPageSelected,
    this.epubBytes,
    this.width,
  });

  @override
  State<PagePreviewPanel> createState() => _PagePreviewPanelState();
}

class _PagePreviewPanelState extends State<PagePreviewPanel> {
  bool _isLoading = false;
  List<_PageContent> _pages = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadContent() async {
    setState(() => _isLoading = true);

    try {
      if (widget.epubBytes != null) {
        await _loadEpubPages();
      } else {
        _createTextPages();
      }
    } catch (e) {
      _createTextPages(); // Fallback to text pages
    }

    setState(() => _isLoading = false);
  }

  Future<void> _loadEpubPages() async {
    if (widget.epubBytes == null) return;

    try {
      final book = await epub_parser.EpubReader.readBook(widget.epubBytes!);

      // Extract chapter content for previews
      List<_PageContent> pages = [];
      int wordOffset = 0;

      if (book.Chapters != null) {
        for (var chapter in book.Chapters!) {
          final chapterPages = _extractChapterPages(chapter, wordOffset);
          pages.addAll(chapterPages);

          // Calculate word offset for this chapter
          for (var page in chapterPages) {
            wordOffset += page.wordCount;
          }
        }
      }

      if (pages.isEmpty) {
        _createTextPages();
      } else {
        _pages = pages;
      }
    } catch (e) {
      _createTextPages();
    }
  }

  List<_PageContent> _extractChapterPages(
    epub_parser.EpubChapter chapter,
    int startWordOffset,
  ) {
    List<_PageContent> pages = [];

    if (chapter.HtmlContent != null) {
      final document = html_parser.parse(chapter.HtmlContent);
      final text = document.body?.text ?? "";

      if (text.trim().isNotEmpty) {
        // Split into pages of ~150 words each
        final words = text
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();
        const wordsPerPage = 150;

        for (int i = 0; i < words.length; i += wordsPerPage) {
          final pageWords = words.sublist(
            i,
            (i + wordsPerPage) < words.length ? i + wordsPerPage : words.length,
          );

          pages.add(
            _PageContent(
              title: chapter.Title,
              text: pageWords.join(' '),
              wordStartIndex: startWordOffset + i,
              wordCount: pageWords.length,
              isChapterStart: i == 0,
            ),
          );
        }
      }
    }

    // Process subchapters
    if (chapter.SubChapters != null) {
      int subOffset =
          startWordOffset + pages.fold(0, (sum, p) => sum + p.wordCount);
      for (var sub in chapter.SubChapters!) {
        pages.addAll(_extractChapterPages(sub, subOffset));
        subOffset += pages.last.wordCount;
      }
    }

    return pages;
  }

  void _createTextPages() {
    const wordsPerPage = 150;
    _pages = [];

    for (int i = 0; i < widget.words.length; i += wordsPerPage) {
      final end = (i + wordsPerPage) < widget.words.length
          ? i + wordsPerPage
          : widget.words.length;
      final pageWords = widget.words.sublist(i, end);

      _pages.add(
        _PageContent(
          title: null,
          text: pageWords.join(' '),
          wordStartIndex: i,
          wordCount: pageWords.length,
          isChapterStart: false,
        ),
      );
    }
  }

  int _getCurrentPageIndex() {
    for (int i = 0; i < _pages.length; i++) {
      final page = _pages[i];
      if (widget.currentWordIndex >= page.wordStartIndex &&
          widget.currentWordIndex < page.wordStartIndex + page.wordCount) {
        return i;
      }
    }
    return 0;
  }

  @override
  void didUpdateWidget(PagePreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Scroll to current page when word index changes significantly
    if ((widget.currentWordIndex - oldWidget.currentWordIndex).abs() > 50) {
      _scrollToCurrentPage();
    }
  }

  void _scrollToCurrentPage() {
    final currentPage = _getCurrentPageIndex();
    if (_scrollController.hasClients && _pages.isNotEmpty) {
      final itemHeight = 160.0; // Approximate height of each item
      final targetOffset = currentPage * itemHeight;
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final panelWidth = widget.width ?? 200.0;
    final currentPage = _getCurrentPageIndex();

    return Container(
      width: panelWidth,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(right: BorderSide(color: Colors.grey[800]!, width: 1)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[800]!, width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_stories, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Seiten (${_pages.length})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Page Grid
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      final page = _pages[index];
                      final isCurrentPage = index == currentPage;

                      return _PagePreviewItem(
                        pageNumber: index + 1,
                        isCurrentPage: isCurrentPage,
                        pageContent: page,
                        onTap: () {
                          widget.onPageSelected(page.wordStartIndex);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PageContent {
  final String? title;
  final String text;
  final int wordStartIndex;
  final int wordCount;
  final bool isChapterStart;

  _PageContent({
    this.title,
    required this.text,
    required this.wordStartIndex,
    required this.wordCount,
    this.isChapterStart = false,
  });
}

class _PagePreviewItem extends StatelessWidget {
  final int pageNumber;
  final bool isCurrentPage;
  final VoidCallback onTap;
  final _PageContent pageContent;

  const _PagePreviewItem({
    required this.pageNumber,
    required this.isCurrentPage,
    required this.onTap,
    required this.pageContent,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          // Paper-like background
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFFFAF8F5), const Color(0xFFF5F2ED)],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isCurrentPage
                ? Theme.of(context).colorScheme.primary
                : Colors.grey[400]!,
            width: isCurrentPage ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 4,
              offset: const Offset(2, 2),
            ),
          ],
        ),
        child: AspectRatio(
          aspectRatio: 0.7,
          child: Stack(
            children: [
              // Page content
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Chapter title if this is a chapter start
                    if (pageContent.isChapterStart &&
                        pageContent.title != null) ...[
                      Text(
                        pageContent.title!,
                        style: const TextStyle(
                          fontSize: 6,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF333333),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Container(
                        height: 0.5,
                        color: Colors.grey[400],
                        margin: const EdgeInsets.only(bottom: 2),
                      ),
                    ],
                    // Text content
                    Expanded(
                      child: Text(
                        pageContent.text,
                        style: const TextStyle(
                          fontSize: 5,
                          height: 1.2,
                          color: Color(0xFF444444),
                          fontFamily: 'serif',
                        ),
                        overflow: TextOverflow.fade,
                      ),
                    ),
                  ],
                ),
              ),
              // Page number
              Positioned(
                bottom: 2,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    '$pageNumber',
                    style: TextStyle(fontSize: 7, color: Colors.grey[600]),
                  ),
                ),
              ),
              // Current page indicator
              if (isCurrentPage)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(3),
                        bottomLeft: Radius.circular(6),
                      ),
                    ),
                    child: const Icon(
                      Icons.bookmark,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
