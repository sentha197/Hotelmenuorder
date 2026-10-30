import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The dish photo header: swipe between photos when the dish has several,
/// tap to open them full screen with pinch-to-zoom. The first photo carries
/// the [heroTag] so it flies in from the menu card.
class DishGallery extends StatefulWidget {
  const DishGallery({super.key, required this.item, required this.heroTag});

  final MenuItem item;
  final String heroTag;

  @override
  State<DishGallery> createState() => _DishGalleryState();
}

class _DishGalleryState extends State<DishGallery> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _openViewer(List<String> photos) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: Motion.of(context, Motion.slow),
        reverseTransitionDuration: Motion.of(context, Motion.medium),
        pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Motion.standard),
          child: _PhotoViewer(
            photos: photos,
            initialIndex: _index,
            name: widget.item.name,
            heroTag: widget.heroTag,
            onPageChanged: (index) {
              if (!mounted) return;
              _pages.jumpToPage(index);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.item.photos;
    if (photos.length <= 1) {
      return GestureDetector(
        onTap: photos.isEmpty ? null : () => _openViewer(photos),
        child: Hero(
          tag: widget.heroTag,
          child: FoodImage(
            photos.isEmpty ? '' : photos.first,
            semanticLabel: widget.item.name,
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pages,
          itemCount: photos.length,
          onPageChanged: (index) => setState(() => _index = index),
          itemBuilder: (context, index) {
            final image = FoodImage(
              photos[index],
              semanticLabel:
                  '${widget.item.name}, photo ${index + 1} of '
                  '${photos.length}',
            );
            return GestureDetector(
              onTap: () => _openViewer(photos),
              child: index == 0
                  ? Hero(tag: widget.heroTag, child: image)
                  : image,
            );
          },
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 40,
          child: _PageDots(count: photos.length, index: _index),
        ),
      ],
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: Motion.of(context, Motion.medium),
              curve: Motion.standard,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == index
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.55),
                borderRadius: AppRadii.pill,
              ),
            ),
        ],
      ),
    );
  }
}

/// Full-screen photos with pinch-to-zoom and swipe between photos.
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({
    required this.photos,
    required this.initialIndex,
    required this.name,
    required this.heroTag,
    required this.onPageChanged,
  });

  final List<String> photos;
  final int initialIndex;
  final String name;
  final String heroTag;
  final ValueChanged<int> onPageChanged;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  /// Swiping between photos is paused while a photo is zoomed in.
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.photos.length;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pages,
              physics: _zoomed
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: count,
              onPageChanged: (index) {
                setState(() => _index = index);
                widget.onPageChanged(index);
              },
              itemBuilder: (context, index) => _ZoomablePhoto(
                path: widget.photos[index],
                label: count > 1
                    ? '${widget.name}, photo ${index + 1} of $count'
                    : widget.name,
                heroTag: index == widget.initialIndex ? widget.heroTag : null,
                onZoomChanged: (zoomed) => setState(() => _zoomed = zoomed),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    CircleIconButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Close photos',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.cardTitle.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (count > 1)
                      Text(
                        '${_index + 1} / $count',
                        style: AppTypography.label.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    required this.path,
    required this.label,
    required this.heroTag,
    required this.onZoomChanged,
  });

  final String path;
  final String label;
  final String? heroTag;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final _transform = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged(zoomed);
  }

  @override
  void dispose() {
    _transform
      ..removeListener(_onTransform)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Plain image (no placeholder behind it) so letterboxing stays black.
    final path = widget.path;
    Widget broken(BuildContext context, Object error, StackTrace? stack) =>
        const Icon(
          Icons.broken_image_outlined,
          color: Colors.white54,
          size: 48,
        );
    final photo = DineQrAssets.isNetwork(path)
        ? Image.network(
            path,
            fit: BoxFit.contain,
            semanticLabel: widget.label,
            errorBuilder: broken,
          )
        : Image.asset(
            path,
            package: DineQrAssets.packageFor(path),
            fit: BoxFit.contain,
            semanticLabel: widget.label,
            errorBuilder: broken,
          );
    return GestureDetector(
      // Double tap toggles between fit and 2.5×.
      onDoubleTapDown: (details) {
        if (_zoomed) {
          _transform.value = Matrix4.identity();
        } else {
          final point = details.localPosition;
          _transform.value = Matrix4.identity()
            ..translateByDouble(-point.dx * 1.5, -point.dy * 1.5, 0, 1)
            ..scaleByDouble(2.5, 2.5, 1, 1);
        }
      },
      onDoubleTap: () {},
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 4,
        child: Center(
          child: widget.heroTag == null
              ? photo
              : Hero(tag: widget.heroTag!, child: photo),
        ),
      ),
    );
  }
}
