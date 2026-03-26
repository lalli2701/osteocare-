import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class TranslationCacheService {
  TranslationCacheService._internal();

  static final TranslationCacheService instance =
      TranslationCacheService._internal();

  static const String _tableName = 'translation_cache';
  static const int _dbVersion = 2;
  static const Duration _cacheRetention = Duration(days: 30);

  Database? _db;

  Future<Database> _database() async {
    if (_db != null) {
      return _db!;
    }

    final path = p.join(await getDatabasesPath(), 'osteocare_translations.db');
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.execute('''
          CREATE TABLE $_tableName(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            lang_code TEXT NOT NULL,
            version TEXT NOT NULL,
            source_hash TEXT NOT NULL,
            original_text TEXT NOT NULL,
            translated_text TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            last_accessed INTEGER NOT NULL DEFAULT $now,
            expires_at INTEGER,
            UNIQUE(lang_code, version, source_hash)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_lang_version ON $_tableName(lang_code, version)',
        );
        await db.execute(
          'CREATE INDEX idx_expires ON $_tableName(expires_at)',
        );
        await db.execute(
          'CREATE INDEX idx_last_accessed ON $_tableName(last_accessed)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN last_accessed INTEGER DEFAULT ${DateTime.now().millisecondsSinceEpoch}',
          );
          await db.execute(
            'CREATE INDEX idx_last_accessed ON $_tableName(last_accessed)',
          );
        }
      },
      onOpen: (db) async {
        final columns = await db.rawQuery('PRAGMA table_info($_tableName)');
        final hasLastAccessed = columns.any(
          (col) => col['name']?.toString() == 'last_accessed',
        );

        if (!hasLastAccessed) {
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN last_accessed INTEGER DEFAULT ${DateTime.now().millisecondsSinceEpoch}',
          );
        }

        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_last_accessed ON $_tableName(last_accessed)',
        );
      },
    );
    return _db!;
  }

  static String _hashText(String text) {
    return text.hashCode.abs().toString();
  }

  Future<String?> get({
    required String langCode,
    required String version,
    required String originalText,
  }) async {
    final db = await _database();
    final sourceHash = _hashText(originalText);
    final now = DateTime.now().millisecondsSinceEpoch;

    final rows = await db.query(
      _tableName,
      where:
          'lang_code = ? AND version = ? AND source_hash = ? AND (expires_at IS NULL OR expires_at > ?)',
      whereArgs: [langCode, version, sourceHash, now],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    // Update last_accessed to track usage for cleanup
    try {
      await db.update(
        _tableName,
        {'last_accessed': now},
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
    } catch (_) {
      // Ignore update failures
    }

    return rows.first['translated_text']?.toString();
  }

  Future<void> set({
    required String langCode,
    required String version,
    required String originalText,
    required String translatedText,
    Duration? ttl,
  }) async {
    final db = await _database();
    final sourceHash = _hashText(originalText);
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    final expiresAt = ttl != null
        ? createdAt + ttl.inMilliseconds
        : null;

    try {
      await db.insert(
        _tableName,
        {
          'lang_code': langCode,
          'version': version,
          'source_hash': sourceHash,
          'original_text': originalText,
          'translated_text': translatedText,
          'created_at': createdAt,
          'last_accessed': createdAt,
          'expires_at': expiresAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Ignore insert failures; cache is best-effort.
    }
  }

  Future<void> evictVersion({required String langCode, String? oldVersion}) async {
    final db = await _database();
    if (oldVersion != null) {
      await db.delete(
        _tableName,
        where: 'lang_code = ? AND version = ?',
        whereArgs: [langCode, oldVersion],
      );
    }
  }

  Future<void> clearExpired() async {
    final db = await _database();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.delete(
      _tableName,
      where: 'expires_at IS NOT NULL AND expires_at <= ?',
      whereArgs: [now],
    );
  }

  /// Cleanup policy: delete translations unused for 30 days or older than 60 days
  Future<int> cleanupOldTranslations() async {
    final db = await _database();
    final now = DateTime.now().millisecondsSinceEpoch;
    final thirtyDaysAgo = now - _cacheRetention.inMilliseconds;
    final sixtyDaysAgo = now - (2 * _cacheRetention.inMilliseconds);

    // Delete unused translations (not accessed in 30 days)
    final deletedUnused = await db.delete(
      _tableName,
      where: 'last_accessed < ?',
      whereArgs: [thirtyDaysAgo],
    );

    // Delete very old translations (created more than 60 days ago) regardless of access
    final deletedOld = await db.delete(
      _tableName,
      where: 'created_at < ? AND last_accessed < ?',
      whereArgs: [sixtyDaysAgo, sixtyDaysAgo],
    );

    return deletedUnused + deletedOld;
  }

  /// Get database stats for monitoring
  Future<Map<String, int>> getStats() async {
    final db = await _database();
    
    final totalRows = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $_tableName'),
    ) ?? 0;

    final expiredRows = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM $_tableName WHERE expires_at IS NOT NULL AND expires_at <= ${DateTime.now().millisecondsSinceEpoch}',
      ),
    ) ?? 0;

    final unusedRows = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM $_tableName WHERE last_accessed < ${DateTime.now().millisecondsSinceEpoch - _cacheRetention.inMilliseconds}',
      ),
    ) ?? 0;

    return {
      'total': totalRows,
      'expired': expiredRows,
      'unused': unusedRows,
    };
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
