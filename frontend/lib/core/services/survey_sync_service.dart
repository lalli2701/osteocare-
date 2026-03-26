import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_service.dart';
import 'local_survey_store.dart';

class SurveySyncService {
  SurveySyncService._internal();

  static final SurveySyncService instance = SurveySyncService._internal();

  static const _anonymousUserIdKey = 'anonymous_user_id';
  static const _lastSyncedAtKey = 'sync_last_synced_at';
  static const _maxAttempts = 5;
  static const _maxBatchSize = 25;
  static const _schemaVersion = 1;
  static const _compressionThresholdBytes = 2 * 1024;
  static const _activeSignatureVersion = '1';
  static const _signingKeys = {
    '1': 'dev-sync-signing-key',
  };

  Future<String> resolveEffectiveUserId() async {
    final userData = await AuthService.instance.getUserData();
    final authUserId = userData?['id']?.toString().trim();
    if (authUserId != null && authUserId.isNotEmpty) {
      return authUserId;
    }

    final prefs = await SharedPreferences.getInstance();
    final existingAnonymous = prefs.getString(_anonymousUserIdKey);
    if (existingAnonymous != null && existingAnonymous.isNotEmpty) {
      return existingAnonymous;
    }

    final anonymousId = 'anon_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString(_anonymousUserIdKey, anonymousId);
    return anonymousId;
  }

  Future<Map<String, dynamic>> getSyncStatus({String? userId}) async {
    final effectiveUserId = userId ?? await resolveEffectiveUserId();
    final pendingCount = await LocalSurveyStore.instance.countPendingSurveys(effectiveUserId);
    final failedPermanentCount = await LocalSurveyStore.instance.countPermanentFailures(effectiveUserId);

    final prefs = await SharedPreferences.getInstance();
    final lastSyncedAtRaw = prefs.getString(_lastSyncedAtKey);
    final lastSyncedAt =
        (lastSyncedAtRaw != null && lastSyncedAtRaw.isNotEmpty) ? DateTime.tryParse(lastSyncedAtRaw) : null;

    return {
      'user_id': effectiveUserId,
      'pending_count': pendingCount,
      'failed_permanent_count': failedPermanentCount,
      'last_synced_at': lastSyncedAt,
    };
  }

  String _signPayload({
    required String secret,
    required int timestampSeconds,
    required String nonce,
    required List<int> bodyBytes,
  }) {
    final bodyHash = sha256.convert(bodyBytes).bytes;
    final bodyHashB64 = base64Encode(bodyHash);
    final message = '$timestampSeconds.$nonce.$bodyHashB64';
    final digest = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(message));
    return digest.toString();
  }

  String _buildDataHash({
    required String localId,
    required String timestamp,
    required Map<String, dynamic> surveyData,
  }) {
    final canonical = {
      'local_id': localId,
      'timestamp': timestamp,
      'schema_version': _schemaVersion,
      'survey_data': surveyData,
    };
    final canonicalJson = jsonEncode(canonical);
    return sha256.convert(utf8.encode(canonicalJson)).toString();
  }

  String _buildBatchHash(List<Map<String, dynamic>> records) {
    final canonicalRecords = records
        .map((record) => {
              'local_id': record['local_id'],
              'timestamp': record['timestamp'],
              'schema_version': record['schema_version'],
              'survey_data': record['survey_data'],
              'data_hash': record['data_hash'],
            })
        .toList();
    final canonicalJson = jsonEncode(canonicalRecords);
    return sha256.convert(utf8.encode(canonicalJson)).toString();
  }

  Future<int> retryPermanentFailures({String? userId, int limit = 20}) async {
    final effectiveUserId = userId ?? await resolveEffectiveUserId();
    final dlqItems = await LocalSurveyStore.instance.getPermanentFailures(
      effectiveUserId,
      limit: limit,
    );
    for (final item in dlqItems) {
      final localId = item['local_id']?.toString() ?? '';
      if (localId.isEmpty) {
        continue;
      }
      await LocalSurveyStore.instance.requeuePermanentFailure(
        userId: effectiveUserId,
        localId: localId,
      );
    }
    if (dlqItems.isEmpty) {
      return 0;
    }
    return syncPendingSurveys(userId: effectiveUserId);
  }

  Duration _delayForAttempt(int attempt) {
    // 2s, 5s, 15s, 30s, 60s
    if (attempt <= 1) {
      return const Duration(seconds: 2);
    }
    if (attempt == 2) {
      return const Duration(seconds: 5);
    }
    if (attempt == 3) {
      return const Duration(seconds: 15);
    }
    if (attempt == 4) {
      return const Duration(seconds: 30);
    }
    return const Duration(seconds: 60);
  }

  Future<void> _setLastSyncedNow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncedAtKey, DateTime.now().toUtc().toIso8601String());
  }

  Future<bool> _hasNetwork() async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      return connectivityResults.any((item) => item != ConnectivityResult.none);
    } catch (_) {
      // Avoid blocking sync on connectivity plugin failures.
      return true;
    }
  }

  Future<http.Response> _postJson(
    String url,
    Map<String, dynamic> payload, {
    required String userId,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final token = await AuthService.instance.getToken();
    final jsonBody = jsonEncode(payload);
    final bytes = utf8.encode(jsonBody);
    final shouldCompress = bytes.length >= _compressionThresholdBytes;
    final timestampSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final nonce = '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
    final rotatedKey = _signingKeys[_activeSignatureVersion] ?? _signingKeys.values.first;

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-User-Id': userId,
      if (token == null) 'X-API-Key': 'dev-key',
      if (token != null) 'Authorization': 'Bearer $token',
      'X-Sync-Timestamp': timestampSeconds.toString(),
      'X-Sync-Nonce': nonce,
      'X-Signature-Version': _activeSignatureVersion,
    };

    List<int> bodyBytes = bytes;
    if (shouldCompress) {
      final compressed = GZipEncoder().encode(bytes);
      if (compressed != null) {
        headers['Content-Encoding'] = 'gzip';
        bodyBytes = compressed;
      }
    }

    final signature = _signPayload(
      secret: token != null ? '$token:$rotatedKey' : rotatedKey,
      timestampSeconds: timestampSeconds,
      nonce: nonce,
      bodyBytes: bodyBytes,
    );
    headers['X-Signature'] = signature;

    return http
        .post(
          Uri.parse(url),
          headers: headers,
          body: bodyBytes,
        )
        .timeout(timeout);
  }

  Future<List<String>> _fetchExistingLocalIds(
    String userId,
    List<String> localIds,
  ) async {
    if (localIds.isEmpty) {
      return const [];
    }

    try {
      final response = await _postJson(
        '${AuthService.baseUrl}/save/status',
        {
          'schema_version': _schemaVersion,
          'local_ids': localIds,
        },
        userId: userId,
        timeout: const Duration(seconds: 12),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }

      final data = Map<String, dynamic>.from(
        (jsonDecode(response.body) as Map?) ?? const <String, dynamic>{},
      );
      return ((data['existing_local_ids'] as List?) ?? const <dynamic>[])
          .whereType<String>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<String?> _startGroupContractToken({
    required String userId,
    required int expectedCount,
  }) async {
    try {
      final response = await _postJson(
        '${AuthService.baseUrl}/sync/group/start',
        {
          'expected_count': expectedCount,
        },
        userId: userId,
        timeout: const Duration(seconds: 12),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final data = Map<String, dynamic>.from(
        (jsonDecode(response.body) as Map?) ?? const <String, dynamic>{},
      );
      final token = data['group_token']?.toString();
      if (token == null || token.isEmpty) {
        return null;
      }
      return token;
    } catch (_) {
      return null;
    }
  }

  Future<int> syncPendingSurveys({
    String? userId,
    int maxBatchSize = _maxBatchSize,
  }) async {
    if (!await _hasNetwork()) {
      return 0;
    }

    final effectiveUserId = userId ?? await resolveEffectiveUserId();
    var pending = await LocalSurveyStore.instance.getPendingSurveys(
      effectiveUserId,
      limit: min(maxBatchSize, _maxBatchSize),
      maxAttempts: _maxAttempts,
    );

    if (pending.isEmpty) {
      return 0;
    }

    final existing = await _fetchExistingLocalIds(
      effectiveUserId,
      pending
          .map((item) => item['local_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(),
    );
    if (existing.isNotEmpty) {
      await LocalSurveyStore.instance.markSyncedByLocalIds(
        userId: effectiveUserId,
        localIds: existing,
      );
      await _setLastSyncedNow();
      final existingSet = existing.toSet();
      pending = pending
          .where((record) => !existingSet.contains(record['local_id']?.toString() ?? ''))
          .toList();
      if (pending.isEmpty) {
        return existing.length;
      }
    }

    final payloadRecords = pending.map((record) {
      return {
        'local_id': record['local_id'],
        'timestamp': record['created_at'],
        'schema_version': _schemaVersion,
        'survey_data': record['survey_data'],
        'data_hash': _buildDataHash(
          localId: record['local_id']?.toString() ?? '',
          timestamp: record['created_at']?.toString() ?? '',
          surveyData: Map<String, dynamic>.from(
            (record['survey_data'] as Map?) ?? const <String, dynamic>{},
          ),
        ),
      };
    }).toList();

    final groupToken = await _startGroupContractToken(
      userId: effectiveUserId,
      expectedCount: payloadRecords.length,
    );
    if (groupToken == null || groupToken.isEmpty) {
      for (final record in pending) {
        final localId = record['local_id']?.toString() ?? '';
        if (localId.isEmpty) {
          continue;
        }
        final currentAttempts = (record['attempt_count'] as num?)?.toInt() ?? 0;
        final nextAttempt = currentAttempts + 1;
        if (nextAttempt >= _maxAttempts) {
          await LocalSurveyStore.instance.markPermanentFailed(
            userId: effectiveUserId,
            localId: localId,
            error: 'Unable to acquire sync group token',
          );
          continue;
        }
        await LocalSurveyStore.instance.scheduleRetry(
          userId: effectiveUserId,
          localId: localId,
          nextAttemptCount: nextAttempt,
          nextRetryAt: DateTime.now().add(_delayForAttempt(nextAttempt)),
          error: 'Unable to acquire sync group token',
        );
      }
      return existing.length;
    }

    try {
      final response = await _postJson(
        '${AuthService.baseUrl}/save/batch',
        {
          'schema_version': _schemaVersion,
          'group_token': groupToken,
          'batch_hash': _buildBatchHash(payloadRecords),
          'records': payloadRecords,
        },
        userId: effectiveUserId,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = Map<String, dynamic>.from(
          (jsonDecode(response.body) as Map?) ?? const <String, dynamic>{},
        );
        final syncedIds = ((data['synced_local_ids'] as List?) ?? const <dynamic>[])
            .whereType<String>()
            .toList();

        if (syncedIds.isNotEmpty) {
          await LocalSurveyStore.instance.markSyncedByLocalIds(
            userId: effectiveUserId,
            localIds: syncedIds,
          );
          await _setLastSyncedNow();
        }

        final failedIds = ((data['failed_local_ids'] as List?) ?? const <dynamic>[])
            .whereType<String>()
            .toSet();

        final syncedSet = syncedIds.toSet();
        for (final record in pending) {
          final localId = record['local_id']?.toString() ?? '';
          if (localId.isEmpty || syncedSet.contains(localId)) {
            continue;
          }
          if (failedIds.isNotEmpty && !failedIds.contains(localId)) {
            continue;
          }
          final currentAttempts = (record['attempt_count'] as num?)?.toInt() ?? 0;
          final nextAttempt = currentAttempts + 1;
          if (nextAttempt >= _maxAttempts) {
            await LocalSurveyStore.instance.markPermanentFailed(
              userId: effectiveUserId,
              localId: localId,
              error: 'Retry limit reached after partial failure',
            );
            continue;
          }
          await LocalSurveyStore.instance.scheduleRetry(
            userId: effectiveUserId,
            localId: localId,
            nextAttemptCount: nextAttempt,
            nextRetryAt: DateTime.now().add(_delayForAttempt(nextAttempt)),
            error: 'Partial batch sync failure',
          );
        }

        return syncedIds.length + existing.length;
      }

      if (response.statusCode == 429) {
        final responseJson = Map<String, dynamic>.from(
          (jsonDecode(response.body) as Map?) ?? const <String, dynamic>{},
        );
        final retryAfter = (responseJson['retry_after'] as num?)?.toInt() ?? 10;
        final nextRetryAt = DateTime.now().add(Duration(seconds: retryAfter));
        for (final record in pending) {
          final localId = record['local_id']?.toString() ?? '';
          if (localId.isEmpty) {
            continue;
          }
          final currentAttempts = (record['attempt_count'] as num?)?.toInt() ?? 0;
          await LocalSurveyStore.instance.scheduleRetry(
            userId: effectiveUserId,
            localId: localId,
            nextAttemptCount: currentAttempts,
            nextRetryAt: nextRetryAt,
            error: 'Backpressure: retry_after=$retryAfter',
          );
        }
        return existing.length;
      }

      final error = 'HTTP ${response.statusCode}';
      for (final record in pending) {
        final localId = record['local_id']?.toString() ?? '';
        if (localId.isEmpty) {
          continue;
        }
        final currentAttempts = (record['attempt_count'] as num?)?.toInt() ?? 0;
        final nextAttempt = currentAttempts + 1;
        if (nextAttempt >= _maxAttempts) {
          await LocalSurveyStore.instance.markPermanentFailed(
            userId: effectiveUserId,
            localId: localId,
            error: error,
          );
          continue;
        }
        await LocalSurveyStore.instance.scheduleRetry(
          userId: effectiveUserId,
          localId: localId,
          nextAttemptCount: nextAttempt,
          nextRetryAt: DateTime.now().add(_delayForAttempt(nextAttempt)),
          error: error,
        );
      }
      return existing.length;
    } catch (e) {
      debugPrint('Survey sync failed: $e');
      for (final record in pending) {
        final localId = record['local_id']?.toString() ?? '';
        if (localId.isEmpty) {
          continue;
        }
        final currentAttempts = (record['attempt_count'] as num?)?.toInt() ?? 0;
        final nextAttempt = currentAttempts + 1;
        if (nextAttempt >= _maxAttempts) {
          await LocalSurveyStore.instance.markPermanentFailed(
            userId: effectiveUserId,
            localId: localId,
            error: e.toString(),
          );
          continue;
        }
        await LocalSurveyStore.instance.scheduleRetry(
          userId: effectiveUserId,
          localId: localId,
          nextAttemptCount: nextAttempt,
          nextRetryAt: DateTime.now().add(_delayForAttempt(nextAttempt)),
          error: e.toString(),
        );
      }
      return existing.length;
    }
  }
}
