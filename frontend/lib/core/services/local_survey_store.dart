import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class LocalSurveyStore {
  LocalSurveyStore._internal();

  static final LocalSurveyStore instance = LocalSurveyStore._internal();

  static const _tableName = 'survey_records';
  static const _webQueueKey = 'survey_records_web_queue';
  static const _webNextIdKey = 'survey_records_web_next_id';
  static const _dbVersion = 4;

  Database? _db;

  Future<Database> _database() async {
    if (_db != null) {
      return _db!;
    }

    final path = p.join(await getDatabasesPath(), 'osteocare_local.db');
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN local_id TEXT',
          );
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN attempt_count INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN next_retry_at TEXT',
          );
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN last_error TEXT',
          );
          await db.execute(
            "UPDATE $_tableName SET local_id = 'legacy_' || id WHERE local_id IS NULL",
          );
          await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_survey_local_id ON $_tableName(local_id)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_survey_pending ON $_tableName(user_id, synced, attempt_count, next_retry_at)',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN synced_at TEXT',
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE $_tableName ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'",
          );
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN failed_permanent_at TEXT',
          );
          await db.execute(
            "UPDATE $_tableName SET status = CASE WHEN synced = 1 THEN 'synced' ELSE 'pending' END WHERE status IS NULL OR status = ''",
          );
        }
      },
    );
    return _db!;
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE $_tableName(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_id TEXT UNIQUE,
        user_id TEXT NOT NULL,
        survey_json TEXT NOT NULL,
        result_json TEXT,
        synced INTEGER NOT NULL DEFAULT 0,
        synced_at TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        failed_permanent_at TEXT,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at TEXT,
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_survey_sync ON $_tableName(user_id, synced, created_at)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_survey_local_id ON $_tableName(local_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_survey_pending ON $_tableName(user_id, synced, attempt_count, next_retry_at)',
    );
  }

  String _makeLocalId(String userId) {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final userHash = userId.hashCode.abs();
    return 'loc_${userHash}_$millis';
  }

  Future<Map<String, dynamic>> insertSurvey({
    required String userId,
    required Map<String, dynamic> surveyData,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final localId = _makeLocalId(userId);

    if (kIsWeb) {
      final id = await _insertWebRecord(
        userId: userId,
        localId: localId,
        surveyData: surveyData,
        nowIso: now,
      );
      return {'id': id, 'local_id': localId};
    }

    final db = await _database();
    final id = await db.insert(_tableName, {
      'local_id': localId,
      'user_id': userId,
      'survey_json': jsonEncode(surveyData),
      'result_json': null,
      'synced': 0,
      'synced_at': null,
      'status': 'pending',
      'failed_permanent_at': null,
      'attempt_count': 0,
      'next_retry_at': null,
      'last_error': null,
      'created_at': now,
      'updated_at': now,
    });
    return {'id': id, 'local_id': localId};
  }

  Future<void> markSynced({
    required int id,
    required Map<String, dynamic> result,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    if (kIsWeb) {
      await _markWebRecordSynced(id: id, result: result, nowIso: now);
      return;
    }

    final db = await _database();
    await db.update(
      _tableName,
      {
        'synced': 1,
        'synced_at': now,
        'status': 'synced',
        'failed_permanent_at': null,
        'result_json': jsonEncode(result),
        'attempt_count': 0,
        'next_retry_at': null,
        'last_error': null,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markSyncedByLocalIds({
    required String userId,
    required List<String> localIds,
  }) async {
    if (localIds.isEmpty) {
      return;
    }

    final now = DateTime.now().toUtc().toIso8601String();

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final records = await _readWebRecords();
      final ids = localIds.toSet();

      for (var i = 0; i < records.length; i++) {
        if (records[i]['user_id'] == userId && ids.contains(records[i]['local_id'])) {
          records[i]['synced'] = 1;
          records[i]['synced_at'] = now;
          records[i]['status'] = 'synced';
          records[i]['failed_permanent_at'] = null;
          records[i]['attempt_count'] = 0;
          records[i]['next_retry_at'] = null;
          records[i]['last_error'] = null;
          records[i]['updated_at'] = now;
        }
      }

      await prefs.setString(_webQueueKey, jsonEncode(records));
      return;
    }

    final db = await _database();
    final placeholders = List.filled(localIds.length, '?').join(', ');
    await db.rawUpdate(
      "UPDATE $_tableName SET synced = 1, synced_at = ?, status = 'synced', failed_permanent_at = NULL, attempt_count = 0, next_retry_at = NULL, last_error = NULL, updated_at = ? "
      'WHERE user_id = ? AND local_id IN ($placeholders)',
      [now, now, userId, ...localIds],
    );
  }

  Future<void> markPermanentFailed({
    required String userId,
    required String localId,
    required String error,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final records = await _readWebRecords();
      for (var i = 0; i < records.length; i++) {
        if (records[i]['user_id'] == userId && records[i]['local_id'] == localId) {
          records[i]['status'] = 'failed_permanent';
          records[i]['failed_permanent_at'] = now;
          records[i]['last_error'] = error;
          records[i]['next_retry_at'] = null;
          records[i]['updated_at'] = now;
          break;
        }
      }
      await prefs.setString(_webQueueKey, jsonEncode(records));
      return;
    }

    final db = await _database();
    await db.update(
      _tableName,
      {
        'status': 'failed_permanent',
        'failed_permanent_at': now,
        'last_error': error,
        'next_retry_at': null,
        'updated_at': now,
      },
      where: 'user_id = ? AND local_id = ?',
      whereArgs: [userId, localId],
    );
  }

  Future<void> scheduleRetry({
    required String userId,
    required String localId,
    required int nextAttemptCount,
    required DateTime nextRetryAt,
    required String error,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final retryIso = nextRetryAt.toUtc().toIso8601String();

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final records = await _readWebRecords();
      for (var i = 0; i < records.length; i++) {
        if (records[i]['user_id'] == userId && records[i]['local_id'] == localId) {
          records[i]['attempt_count'] = nextAttemptCount;
          records[i]['status'] = 'pending';
          records[i]['failed_permanent_at'] = null;
          records[i]['next_retry_at'] = retryIso;
          records[i]['last_error'] = error;
          records[i]['updated_at'] = now;
          break;
        }
      }
      await prefs.setString(_webQueueKey, jsonEncode(records));
      return;
    }

    final db = await _database();
    await db.update(
      _tableName,
      {
        'attempt_count': nextAttemptCount,
        'status': 'pending',
        'failed_permanent_at': null,
        'next_retry_at': retryIso,
        'last_error': error,
        'synced_at': null,
        'updated_at': now,
      },
      where: 'user_id = ? AND local_id = ?',
      whereArgs: [userId, localId],
    );
  }

  Future<List<Map<String, dynamic>>> getPendingSurveys(
    String userId, {
    int limit = 50,
    int maxAttempts = 5,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();

    if (kIsWeb) {
      return _getPendingWebRecords(
        userId,
        nowIso: nowIso,
        maxAttempts: maxAttempts,
        limit: limit,
      );
    }

    final db = await _database();
    final rows = await db.query(
      _tableName,
      where:
          "user_id = ? AND status = 'pending' AND synced = 0 AND attempt_count < ? AND (next_retry_at IS NULL OR next_retry_at <= ?)",
      whereArgs: [userId, maxAttempts, nowIso],
      orderBy: 'created_at ASC',
      limit: limit,
    );

    return rows
        .map((row) => {
              'id': row['id'],
              'local_id': row['local_id'],
              'survey_data': jsonDecode((row['survey_json'] ?? '{}').toString()),
              'attempt_count': row['attempt_count'] ?? 0,
              'created_at': row['created_at'],
            })
        .toList();
  }

  Future<int> countPendingSurveys(String userId, {int maxAttempts = 5}) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();

    if (kIsWeb) {
      final records = await _readWebRecords();
      return records.where((item) {
        if (item['user_id'] != userId || item['synced'] != 0 || item['status'] != 'pending') {
          return false;
        }
        final attemptCount = (item['attempt_count'] as num?)?.toInt() ?? 0;
        if (attemptCount >= maxAttempts) {
          return false;
        }
        final nextRetry = item['next_retry_at']?.toString();
        return nextRetry == null || nextRetry.isEmpty || nextRetry.compareTo(nowIso) <= 0;
      }).length;
    }

    final db = await _database();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_tableName '
      "WHERE user_id = ? AND status = 'pending' AND synced = 0 AND attempt_count < ? "
      'AND (next_retry_at IS NULL OR next_retry_at <= ?)',
      [userId, maxAttempts, nowIso],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<int> countPermanentFailures(String userId) async {
    if (kIsWeb) {
      final records = await _readWebRecords();
      return records.where((item) => item['user_id'] == userId && item['status'] == 'failed_permanent').length;
    }

    final db = await _database();
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS count FROM $_tableName WHERE user_id = ? AND status = 'failed_permanent'",
      [userId],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getPermanentFailures(
    String userId, {
    int limit = 100,
  }) async {
    if (kIsWeb) {
      final records = await _readWebRecords();
      return records
          .where((item) => item['user_id'] == userId && item['status'] == 'failed_permanent')
          .take(limit)
          .map((item) => {
                'id': item['id'],
                'local_id': item['local_id'],
                'error': item['last_error'],
                'failed_permanent_at': item['failed_permanent_at'],
              })
          .toList();
    }

    final db = await _database();
    final rows = await db.query(
      _tableName,
      columns: ['id', 'local_id', 'last_error', 'failed_permanent_at'],
      where: "user_id = ? AND status = 'failed_permanent'",
      whereArgs: [userId],
      orderBy: 'failed_permanent_at DESC',
      limit: limit,
    );
    return rows
        .map((row) => {
              'id': row['id'],
              'local_id': row['local_id'],
              'error': row['last_error'],
              'failed_permanent_at': row['failed_permanent_at'],
            })
        .toList();
  }

  Future<void> requeuePermanentFailure({
    required String userId,
    required String localId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final records = await _readWebRecords();
      for (var i = 0; i < records.length; i++) {
        if (records[i]['user_id'] == userId && records[i]['local_id'] == localId) {
          records[i]['status'] = 'pending';
          records[i]['failed_permanent_at'] = null;
          records[i]['attempt_count'] = 0;
          records[i]['next_retry_at'] = now;
          records[i]['updated_at'] = now;
          break;
        }
      }
      await prefs.setString(_webQueueKey, jsonEncode(records));
      return;
    }

    final db = await _database();
    await db.update(
      _tableName,
      {
        'status': 'pending',
        'failed_permanent_at': null,
        'attempt_count': 0,
        'next_retry_at': now,
        'updated_at': now,
      },
      where: 'user_id = ? AND local_id = ?',
      whereArgs: [userId, localId],
    );
  }

  Future<DateTime?> getLastSyncedAt(String userId) async {
    if (kIsWeb) {
      final records = await _readWebRecords();
      DateTime? latest;
      for (final item in records) {
        if (item['user_id'] != userId || item['synced'] != 1) {
          continue;
        }
        final updatedAt = DateTime.tryParse(item['updated_at']?.toString() ?? '');
        if (updatedAt == null) {
          continue;
        }
        if (latest == null || updatedAt.isAfter(latest)) {
          latest = updatedAt;
        }
      }
      return latest;
    }

    final db = await _database();
    final rows = await db.rawQuery(
      'SELECT updated_at FROM $_tableName WHERE user_id = ? AND synced = 1 ORDER BY updated_at DESC LIMIT 1',
      [userId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return DateTime.tryParse((rows.first['updated_at'] ?? '').toString());
  }

  Future<Map<String, dynamic>?> getLatestSyncedResult(String userId) async {
    if (kIsWeb) {
      final records = await _readWebRecords();
      for (final item in records.reversed) {
        if (item['user_id'] == userId && item['synced'] == 1 && item['result_json'] != null) {
          return jsonDecode(item['result_json'].toString()) as Map<String, dynamic>;
        }
      }
      return null;
    }

    final db = await _database();
    final rows = await db.query(
      _tableName,
      where: 'user_id = ? AND synced = 1 AND result_json IS NOT NULL',
      whereArgs: [userId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return jsonDecode((rows.first['result_json'] ?? '{}').toString()) as Map<String, dynamic>;
  }

  Future<int> _insertWebRecord({
    required String userId,
    required String localId,
    required Map<String, dynamic> surveyData,
    required String nowIso,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await _readWebRecords();
    final nextId = (prefs.getInt(_webNextIdKey) ?? 1);

    records.add({
      'id': nextId,
      'local_id': localId,
      'user_id': userId,
      'survey_json': jsonEncode(surveyData),
      'result_json': null,
      'synced': 0,
      'synced_at': null,
      'status': 'pending',
      'failed_permanent_at': null,
      'attempt_count': 0,
      'next_retry_at': null,
      'last_error': null,
      'created_at': nowIso,
      'updated_at': nowIso,
    });

    await prefs.setString(_webQueueKey, jsonEncode(records));
    await prefs.setInt(_webNextIdKey, nextId + 1);
    return nextId;
  }

  Future<void> _markWebRecordSynced({
    required int id,
    required Map<String, dynamic> result,
    required String nowIso,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await _readWebRecords();

    for (var i = 0; i < records.length; i++) {
      if (records[i]['id'] == id) {
        records[i]['synced'] = 1;
        records[i]['synced_at'] = nowIso;
        records[i]['status'] = 'synced';
        records[i]['failed_permanent_at'] = null;
        records[i]['result_json'] = jsonEncode(result);
        records[i]['updated_at'] = nowIso;
        break;
      }
    }

    await prefs.setString(_webQueueKey, jsonEncode(records));
  }

  Future<List<Map<String, dynamic>>> _getPendingWebRecords(
    String userId, {
    required String nowIso,
    required int maxAttempts,
    required int limit,
  }) async {
    final records = await _readWebRecords();

    return records
        .where((item) {
          if (item['user_id'] != userId || item['synced'] != 0 || item['status'] != 'pending') {
            return false;
          }
          final attemptCount = (item['attempt_count'] as num?)?.toInt() ?? 0;
          if (attemptCount >= maxAttempts) {
            return false;
          }
          final nextRetry = item['next_retry_at']?.toString();
          return nextRetry == null || nextRetry.isEmpty || nextRetry.compareTo(nowIso) <= 0;
        })
        .take(limit)
        .map((item) => {
              'id': item['id'],
              'local_id': item['local_id'],
              'survey_data': jsonDecode((item['survey_json'] ?? '{}').toString()),
              'attempt_count': item['attempt_count'] ?? 0,
              'created_at': item['created_at'],
            })
        .toList();
  }

  Future<List<Map<String, dynamic>>> _readWebRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_webQueueKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return [];
    }

    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
