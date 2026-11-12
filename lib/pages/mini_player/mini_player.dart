import 'dart:math' show max;

import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// In-app mini player.
///
/// Swiping the player down on a video page pops the page while the shared
/// [PlPlayerController] keeps playing in a draggable window above the
/// navigator. Tapping the window reopens the page, which adopts the running
/// player instead of loading the media again.
abstract final class MiniPlayer {
  static const settingKey = 'fork_inAppMiniPlayer';
  static bool get enabled =>
      GStorage.setting.get(settingKey, defaultValue: true);

  static const _videoRoute = '/videoV';

  static final Rxn<MiniPlayerSession> _session = Rxn();
  static MiniPlayerSession? get session => _session.value;

  /// Hero tag of the page being reopened from the mini window.
  static String? _handoffTag;

  /// Player gesture hook: the non-fullscreen swipe opposite to the
  /// fullscreen swipe.
  static void onSwipe(VideoDetailController? videoCtr) {
    if (videoCtr == null || !enabled) return;
    enter(videoCtr);
  }

  /// Leaves the video pages and continues playback in the mini window.
  static void enter(VideoDetailController videoCtr) {
    final player = videoCtr.plPlayerController;
    if (session != null || player.videoController == null) return;
    // Hold a reference so the page's dispose does not release the player.
    PlPlayerController.getInstance();
    _session.value = MiniPlayerSession(
      heroTag: videoCtr.heroTag,
      arguments: Map.of(videoCtr.args),
      player: player,
    );
    _entering = true;
    try {
      Get.until(
        (route) => route.isFirst || route.settings.name != _videoRoute,
      );
    } finally {
      _entering = false;
    }
  }

  /// True while [enter] pops the video pages.
  static bool _entering = false;

  /// Video page hook for `didPopNext`: returns true when the page must not
  /// resume. Pages uncovered while entering are popped right after; any other
  /// video page coming back takes the player over from the mini window.
  static bool onVideoPageResumed() {
    if (_entering) return true;
    close();
    return false;
  }

  /// Whether the mini window took over the page with [heroTag].
  static bool owns(String heroTag) => session?.heroTag == heroTag;

  /// Reopens the video page, which adopts the running player.
  static void restore() {
    final session = MiniPlayer.session;
    if (session == null ||
        _handoffTag != null ||
        Get.isRegistered<VideoDetailController>(tag: session.heroTag)) {
      return;
    }
    _handoffTag = session.heroTag;
    PageUtils.toDupNamed(_videoRoute, arguments: Map.of(session.arguments));
  }

  /// Video page hook: true when the page with [heroTag] adopts the running
  /// player. The page already holds the player, so the window lets go.
  static bool takeHandoff(String heroTag) {
    if (_handoffTag == null || _handoffTag != heroTag) return false;
    _handoffTag = null;
    _release();
    return true;
  }

  /// Player hook: any other page acquiring the shared player ends the
  /// mini window, so it never shows someone else's media.
  static void onPlayerAcquire() {
    if (_handoffTag == null) close();
  }

  /// Stops playback and closes the window.
  static void close() {
    final session = MiniPlayer.session;
    if (session == null) return;
    _handoffTag = null;
    session.player.pause();
    _release();
  }

  static void _release() {
    _session.value = null;
    PlPlayerController.updatePlayCount();
  }
}

class MiniPlayerSession {
  MiniPlayerSession({
    required this.heroTag,
    required this.arguments,
    required this.player,
  });

  final String heroTag;
  final Map arguments;
  final PlPlayerController player;
}

/// Layer above the navigator that hosts the mini window.
class MiniPlayerHost extends StatelessWidget {
  const MiniPlayerHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Obx(() {
          final session = MiniPlayer._session.value;
          return session == null
              ? const SizedBox.shrink()
              : _MiniPlayerWindow(key: ObjectKey(session), session: session);
        }),
      ],
    );
  }
}

class _MiniPlayerWindow extends StatefulWidget {
  const _MiniPlayerWindow({super.key, required this.session});

  final MiniPlayerSession session;

  @override
  State<_MiniPlayerWindow> createState() => _MiniPlayerWindowState();
}

class _MiniPlayerWindowState extends State<_MiniPlayerWindow>
    with WidgetsBindingObserver {
  static const double _barHeight = 36;
  static const double _margin = 12;

  /// Where the last window was left, kept across sessions.
  static Offset? _lastOffset;

  Offset? _offset;

  PlPlayerController get _player => widget.session.player;

  bool _pausedForBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Same background rule as the player page, which is gone while the
  /// window is shown.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_player.continuePlayInBackground.value) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_player.videoPlayerController?.state.playing ?? false) {
        _pausedForBackground = true;
        _player.pause();
      }
    } else if (_pausedForBackground) {
      _pausedForBackground = false;
      _player.play();
    }
  }

  Size _windowSize(Size screen) {
    final state = _player.videoPlayerController?.state;
    final w = state?.width ?? 0;
    final h = state?.height ?? 0;
    final ratio = w > 0 && h > 0 ? w / h : 16 / 9;
    final width = screen.shortestSide * (ratio >= 1 ? 0.55 : 0.32);
    return Size(width, width / ratio + _barHeight);
  }

  Rect _bounds(Size screen, EdgeInsets padding, Size size) => Rect.fromLTRB(
    padding.left + _margin,
    padding.top + _margin,
    max(
      padding.left + _margin,
      screen.width - padding.right - _margin - size.width,
    ),
    max(
      padding.top + _margin,
      screen.height - padding.bottom - _margin - size.height,
    ),
  );

  Offset _clamp(Offset offset, Rect bounds) => Offset(
    offset.dx.clamp(bounds.left, bounds.right),
    offset.dy.clamp(bounds.top, bounds.bottom),
  );

  void _seekBy(int milliseconds) {
    final int target = (_player.positionInMilliseconds + milliseconds).clamp(
      0,
      max(0, _player.durationInMilliseconds),
    );
    _player.seekTo(Duration(milliseconds: target));
  }

  @override
  Widget build(BuildContext context) {
    final videoController = _player.videoController;
    final nativePlayer = _player.videoPlayerController;
    if (videoController == null || nativePlayer == null) {
      return const SizedBox.shrink();
    }

    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final size = _windowSize(screen);
    final bounds = _bounds(screen, padding, size);
    final offset = _clamp(
      _offset ?? _lastOffset ?? Offset(bounds.right, bounds.bottom - 80),
      bounds,
    );
    final colorScheme = ColorScheme.of(context);

    Widget button(IconData icon, VoidCallback onPressed) => Expanded(
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20, color: colorScheme.onSurface),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );

    return Positioned(
      left: offset.dx,
      top: offset.dy,
      width: size.width,
      height: size.height,
      child: GestureDetector(
        onPanUpdate: (details) => setState(
          () => _offset = _clamp(offset + details.delta, bounds),
        ),
        onPanEnd: (_) {
          final center = offset.dx + size.width / 2;
          setState(() {
            _offset = _lastOffset = Offset(
              center < screen.width / 2 ? bounds.left : bounds.right,
              offset.dy,
            );
          });
        },
        child: Material(
          elevation: 6,
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: MiniPlayer.restore,
                  child: ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: FittedBox(
                        child: SimpleVideo(controller: videoController),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: _barHeight,
                child: Row(
                  children: [
                    button(Icons.replay_10, () => _seekBy(-10000)),
                    Expanded(
                      child: StreamBuilder<bool>(
                        stream: nativePlayer.stream.playing,
                        initialData: nativePlayer.state.playing,
                        builder: (context, snapshot) {
                          final playing = snapshot.data ?? false;
                          return IconButton(
                            onPressed: playing ? _player.pause : _player.play,
                            icon: Icon(
                              playing ? Icons.pause : Icons.play_arrow,
                              size: 20,
                              color: colorScheme.onSurface,
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          );
                        },
                      ),
                    ),
                    button(Icons.forward_10, () => _seekBy(10000)),
                    button(Icons.close, MiniPlayer.close),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
