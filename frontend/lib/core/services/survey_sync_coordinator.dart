import 'dart:async';

import 'package:flutter/widgets.dart';

import 'survey_sync_service.dart';

class SurveySyncCoordinator with WidgetsBindingObserver {
  SurveySyncCoordinator._internal();

  static final SurveySyncCoordinator instance = SurveySyncCoordinator._internal();

  Timer? _timer;
  bool _started = false;
  bool _isSyncing = false;
  static const _maxGuaranteeInterval = Duration(minutes: 5);

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);

    _scheduleNext(const Duration(seconds: 5));
  }

  void stop() {
    if (!_started) {
      return;
    }
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerSync();
    }
  }

  void _scheduleNext(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      _triggerSync();
    });
  }

  Duration _nextIntervalForPending(int pendingCount) {
    if (pendingCount > 20) {
      return const Duration(seconds: 20);
    }
    if (pendingCount > 0) {
      return const Duration(seconds: 45);
    }
    return const Duration(minutes: 3);
  }

  Future<void> _triggerSync() async {
    if (_isSyncing) {
      return;
    }
    _isSyncing = true;
    var pendingAfterSync = 0;
    try {
      await SurveySyncService.instance.syncPendingSurveys();
      final status = await SurveySyncService.instance.getSyncStatus();
      pendingAfterSync = (status['pending_count'] as num?)?.toInt() ?? 0;
    } finally {
      _isSyncing = false;
      if (_started) {
        final nextInterval = _nextIntervalForPending(pendingAfterSync);
        _scheduleNext(
          nextInterval <= _maxGuaranteeInterval ? nextInterval : _maxGuaranteeInterval,
        );
      }
    }
  }
}
