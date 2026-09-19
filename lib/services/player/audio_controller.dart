import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/utils/async_session.dart';

typedef AudioCallback = Future<void> Function();
typedef AudioSeekCallback = Future<void> Function(Duration position);

class AudioController {
  AudioController();

  _WywAudioHandler? _handler;
  Future<void>? _initFuture;
  String? _lastMediaItemCacheKey;
  AudioSession? _audioSession;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _becomingNoisySubscription;
  AudioCallback? _onPlay;
  AudioCallback? _onPause;
  bool _playInterrupted = false;
  bool? _lastAudioSessionActive;
  final AsyncSessionOwner _sessions = AsyncSessionOwner();
  AsyncSession? _boundSession;

  Future<void> ensureInitialized() {
    _initFuture ??= _initialize();
    return _initFuture!;
  }

  Future<void> _initialize() async {
    late _WywAudioHandler rawHandler;
    if (Platform.isLinux) {
      AudioServiceMpris.init(
        dBusName: 'com.yi.wyw.channel.audio',
        identity: 'Wyw Playback',
        canControl: true,
        canPlay: true,
        canPause: true,
        canGoNext: true,
        canGoPrevious: true,
      );
    }
    await AudioService.init(
      builder: () {
        rawHandler = _WywAudioHandler();
        return rawHandler;
      },
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.yi.wyw.channel.audio',
        androidNotificationChannelName: 'Wyw Playback',
        androidNotificationOngoing: true,
      ),
    );
    _handler = rawHandler;
    await _initializeAudioSession();
  }

  Future<void> _initializeAudioSession() async {
    try {
      _audioSession = await AudioSession.instance;
      await _audioSession!.configure(const AudioSessionConfiguration.music());

      _interruptionSubscription?.cancel();
      _interruptionSubscription = _audioSession!.interruptionEventStream.listen(
        _handleInterruptionEvent,
      );

      if (Platform.isAndroid || Platform.isIOS) {
        _becomingNoisySubscription?.cancel();
        _becomingNoisySubscription =
            _audioSession!.becomingNoisyEventStream.listen((_) {
          if (_handler?.playbackState.value.playing ?? false) {
            unawaited(_safePause());
          }
        });
      }
    } catch (e, s) {
      WywLogger()
          .w('${LogTag.player} audio_session 初始化失败', error: e, stackTrace: s);
    }
  }

  void _handleInterruptionEvent(AudioInterruptionEvent event) {
    final isPlaying = _handler?.playbackState.value.playing ?? false;
    if (event.begin) {
      if (!isPlaying) return;
      switch (event.type) {
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          _playInterrupted = true;
          unawaited(_safePause());
          break;
        case AudioInterruptionType.duck:
          break;
      }
      return;
    }

    if (event.type == AudioInterruptionType.pause && _playInterrupted) {
      _playInterrupted = false;
      unawaited(_safePlay());
      return;
    }
    _playInterrupted = false;
  }

  Future<void> _safePause() async {
    try {
      if (_onPause != null) {
        await _onPause!();
      }
    } catch (e, s) {
      WywLogger().w('${LogTag.player} 音频焦点中断后暂停回调失败', error: e, stackTrace: s);
    }
  }

  Future<void> _safePlay() async {
    try {
      if (_onPlay != null) {
        await _onPlay!();
      }
    } catch (e, s) {
      WywLogger()
          .w('${LogTag.player} 音频焦点中断结束后恢复播放失败', error: e, stackTrace: s);
    }
  }

  Future<void> _setAudioSessionActive(bool active) async {
    if (_lastAudioSessionActive == active) return;
    _lastAudioSessionActive = active;
    try {
      await _audioSession?.setActive(active);
    } catch (e, s) {
      WywLogger().w('${LogTag.player} audio_session setActive($active) 失败',
          error: e, stackTrace: s);
    }
  }

  Future<void> bindCallbacks({
    required AudioCallback onPlay,
    required AudioCallback onPause,
    required AudioSeekCallback onSeek,
  }) async {
    final binding = _sessions.begin();
    _boundSession = null;
    _clearCallbacks();
    await ensureInitialized();
    if (binding.isStale) {
      return;
    }
    _onPlay = onPlay;
    _onPause = onPause;
    _handler?.bindCallbacks(
      onPlay: onPlay,
      onPause: onPause,
      onSeek: onSeek,
    );
    _boundSession = binding;
  }

  void _clearCallbacks() {
    _onPlay = null;
    _onPause = null;
    _handler?.clearCallbacks();
  }

  Future<void> updateSession({
    required String mediaId,
    required String title,
    Duration? duration,
    required bool playing,
    required bool loading,
    required bool buffering,
    required bool completed,
    required Duration updatePosition,
    required Duration bufferedPosition,
    required double speed,
    String cover = '',
  }) async {
    final binding = _boundSession;
    if (binding == null || binding.isStale) return;
    await ensureInitialized();
    if (binding.isStale) return;
    await _setAudioSessionActive(playing);
    if (binding.isStale) return;
    final handler = _handler;
    if (handler == null) return;

    final mediaItemCacheKey = [
      mediaId,
      title,
      (duration ?? Duration.zero).inMilliseconds.toString(),
    ].join('|');

    if (_lastMediaItemCacheKey != mediaItemCacheKey) {
      _lastMediaItemCacheKey = mediaItemCacheKey;
      // artUri 必须给有效值：audio_service_win 对 null 会做
      // null.toString() → "null" 并当本地路径读取缩略图报错；
      // 无封面时传空 URI（toString() 为空串），插件会跳过缩略图。
      final coverTrimmed = cover.trim();
      final Uri? artUri =
          coverTrimmed.isEmpty ? Uri() : Uri.tryParse(coverTrimmed);
      handler.publishMediaItem(
        MediaItem(
          id: mediaId,
          title: '',
          duration: duration,
          artUri: artUri ?? Uri(),
        ),
      );
    }

    final controls = <MediaControl>[
      if (playing) MediaControl.pause else MediaControl.play,
    ];

    final compactActionIndices = controls.isEmpty
        ? null
        : List<int>.generate(
            controls.length > 3 ? 3 : controls.length,
            (index) => index,
          );

    final processingState = completed
        ? AudioProcessingState.completed
        : loading
            ? AudioProcessingState.loading
            : buffering
                ? AudioProcessingState.buffering
                : AudioProcessingState.ready;

    final normalizedPosition = duration == null
        ? updatePosition
        : updatePosition > duration
            ? duration
            : updatePosition;
    final normalizedBufferedPosition = duration == null
        ? bufferedPosition
        : bufferedPosition > duration
            ? duration
            : bufferedPosition;

    handler.updatePlaybackState(
      PlaybackState(
        controls: controls,
        androidCompactActionIndices: compactActionIndices,
        systemActions: duration == null || duration == Duration.zero
            ? const {}
            : const {
                MediaAction.seek,
              },
        processingState: processingState,
        playing: playing,
        updatePosition: normalizedPosition,
        bufferedPosition: normalizedBufferedPosition,
        speed: speed,
      ),
    );
  }

  Future<void> deactivate() {
    final deactivation = _sessions.begin();
    _boundSession = null;
    _clearCallbacks();
    _playInterrupted = false;
    final initialization = _initFuture;
    if (initialization == null) {
      return Future<void>.value();
    }
    return _deactivate(deactivation, initialization);
  }

  Future<void> _deactivate(
    AsyncSession deactivation,
    Future<void> initialization,
  ) async {
    await initialization;
    if (deactivation.isStale) return;
    _lastMediaItemCacheKey = null;
    _lastAudioSessionActive = null;
    await _setAudioSessionActive(false);
    if (deactivation.isStale) return;
    _handler?.updatePlaybackState(
      PlaybackState(
        controls: [],
        systemActions: const {},
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
      ),
    );
  }
}

class _WywAudioHandler extends BaseAudioHandler with SeekHandler {
  AudioCallback? _onPlay;
  AudioCallback? _onPause;

  AudioSeekCallback? _onSeek;

  void bindCallbacks({
    required AudioCallback onPlay,
    required AudioCallback onPause,
    required AudioSeekCallback onSeek,
  }) {
    _onPlay = onPlay;
    _onPause = onPause;

    _onSeek = onSeek;
  }

  void clearCallbacks() {
    _onPlay = null;
    _onPause = null;
    _onSeek = null;
  }

  void publishMediaItem(MediaItem item) {
    mediaItem.add(item);
  }

  void updatePlaybackState(PlaybackState state) {
    playbackState.add(state);
  }

  @override
  Future<void> play() async {
    if (_onPlay != null) {
      await _onPlay!();
    }
  }

  @override
  Future<void> pause() async {
    if (_onPause != null) {
      await _onPause!();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (_onSeek != null) {
      await _onSeek!(position);
    }
  }
}
