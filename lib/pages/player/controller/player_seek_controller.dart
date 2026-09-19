import 'package:wyw/pages/player/controller/player_playback_controller.dart';

class _InteractiveSeekSession {
  _InteractiveSeekSession(this.pauseCompleted, this.target);

  final Future<void> pauseCompleted;
  Duration target;
  Future<bool>? commit;
}

class PlayerSeekController {
  PlayerSeekController({
    required PlayerPlaybackController playback,
    required Future<void> Function({bool enableSync}) pause,
    required Future<void> Function({bool enableSync}) play,
  })  : _playback = playback,
        _pause = pause,
        _play = play;

  final PlayerPlaybackController _playback;
  final Future<void> Function({bool enableSync}) _pause;
  final Future<void> Function({bool enableSync}) _play;

  Future<void> _seekTail = Future<void>.value();
  _InteractiveSeekSession? _interactiveSession;

  bool get hasActiveInteractiveSeek => _interactiveSession != null;

  Future<void> seekTo(
    Duration target, {
    bool enableSync = true,
  }) {
    final player = _playback.mediaPlayer;
    if (player == null) {
      return Future<void>.value();
    }

    final normalizedTarget = _normalize(target);
    _playback.currentPosition = normalizedTarget;

    final operation = _seekTail.then((_) async {
      if (!_playback.isCurrentPlayer(player)) {
        return;
      }
      try {
        await player.seek(normalizedTarget);
      } catch (_) {
        return;
      }
    });
    _seekTail = _settle(operation);
    return operation;
  }

  Future<void> seekBy(
    Duration offset, {
    bool enableSync = true,
  }) =>
      seekTo(
        _playback.currentPosition + offset,
        enableSync: enableSync,
      );

  void beginInteractiveSeek() {
    _interactiveSession = _InteractiveSeekSession(
      _pause(enableSync: false),
      _playback.currentPosition,
    );
  }

  bool updateInteractiveSeek(Duration target) {
    final session = _interactiveSession;
    if (session == null) {
      return false;
    }
    session.target = _normalize(target);
    _playback.currentPosition = session.target;
    return true;
  }

  Future<bool> commitInteractiveSeek() {
    final session = _interactiveSession;
    if (session == null) {
      return Future<bool>.value(false);
    }
    return session.commit ??= _commitInteractiveSeek(session);
  }

  void invalidateInteractiveSeek() {
    _interactiveSession = null;
  }

  Future<bool> _commitInteractiveSeek(
    _InteractiveSeekSession session,
  ) async {
    try {
      await session.pauseCompleted;
      if (!_isCurrent(session)) {
        return false;
      }

      await seekTo(session.target);
      if (!_isCurrent(session)) {
        return false;
      }

      await _play(enableSync: false);
      return _isCurrent(session);
    } finally {
      if (_isCurrent(session)) {
        _interactiveSession = null;
      }
    }
  }

  Duration _normalize(Duration target) {
    var milliseconds = target.inMilliseconds;
    if (milliseconds < 0) {
      milliseconds = 0;
    }
    final duration = _playback.duration;
    if (duration > Duration.zero && milliseconds > duration.inMilliseconds) {
      milliseconds = duration.inMilliseconds;
    }
    return Duration(milliseconds: milliseconds);
  }

  bool _isCurrent(_InteractiveSeekSession session) =>
      identical(_interactiveSession, session);

  Future<void> _settle(Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      // The caller receives the error; the queue only needs to remain usable.
    }
  }
}
