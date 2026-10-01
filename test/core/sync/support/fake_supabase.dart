import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signed-in user returned by [FakeSupabase].
class FakeAuth extends Fake implements GoTrueClient {
  @override
  User? get currentUser => User(
        id: 'user-1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      );
}

/// A recorded write: the target table and the request body.
class RecordedWrite {
  final String table;
  final Object values;

  const RecordedWrite(this.table, this.values);
}

/// Minimal [SupabaseClient] for SyncManager tests: records upserts, updates and inserts,
/// serves canned rows for selects, and can fail writes to selected tables.
class FakeSupabase extends Fake implements SupabaseClient {
  final Map<String, List<Map<String, dynamic>>> rowsByTable;
  final List<RecordedWrite> upserts = [];
  final List<RecordedWrite> updates = [];
  final List<RecordedWrite> inserts = [];

  /// Number of select queries issued per table.
  final Map<String, int> selectCount = {};

  /// Server-side row cap applied to every select, like PostgREST's max-rows
  /// (1000 on Supabase projects). Null means unlimited.
  int? maxRows;

  /// Error thrown by writes to a table, keyed by table name.
  final Map<String, Object> writeErrors = {};

  FakeSupabase({this.rowsByTable = const {}});

  @override
  GoTrueClient get auth => FakeAuth();

  @override
  SupabaseQueryBuilder from(String table) => FakeQueryBuilder(this, table);
}

class FakeQueryBuilder extends Fake implements SupabaseQueryBuilder {
  final FakeSupabase client;
  final String table;

  FakeQueryBuilder(this.client, this.table);

  @override
  PostgrestFilterBuilder<dynamic> upsert(
    Object values, {
    String? onConflict,
    bool ignoreDuplicates = false,
    bool defaultToNull = true,
  }) {
    client.upserts.add(RecordedWrite(table, values));
    return FakeFilterBuilder<dynamic>(null, error: client.writeErrors[table]);
  }

  @override
  PostgrestFilterBuilder<dynamic> update(Map values) {
    client.updates.add(RecordedWrite(table, values));
    return FakeFilterBuilder<dynamic>(null, error: client.writeErrors[table]);
  }

  @override
  PostgrestFilterBuilder<dynamic> insert(Object values, {bool defaultToNull = true}) {
    client.inserts.add(RecordedWrite(table, values));
    return FakeFilterBuilder<dynamic>(null, error: client.writeErrors[table]);
  }

  @override
  PostgrestFilterBuilder<PostgrestList> select([String columns = '*']) {
    client.selectCount[table] = (client.selectCount[table] ?? 0) + 1;
    return FakeSelectBuilder(client.rowsByTable[table] ?? <Map<String, dynamic>>[], maxRows: client.maxRows);
  }
}

/// Mutable query state of a [FakeSelectBuilder].
class _SelectQuery {
  final List<bool Function(Map<String, dynamic>)> filters = [];
  bool ordered = false;
  int? limit;
}

/// Evaluates the filters SyncManager uses (eq, gt, gte, its keyset `or`,
/// order and limit) against in-memory rows. Rows that omit a filtered column,
/// or hold null in it, are treated as matching, so fixtures may leave out user_id.
class FakeSelectBuilder extends Fake implements PostgrestFilterBuilder<PostgrestList> {
  final List<Map<String, dynamic>> rows;
  final int? maxRows;
  final _SelectQuery _query = _SelectQuery();

  FakeSelectBuilder(this.rows, {this.maxRows});

  static final RegExp _keyset =
      RegExp(r'^updated_at\.gt\."([^"]*)",and\(updated_at\.eq\."([^"]*)",id\.gt\."([^"]*)"\)$');

  static int _compare(Object? a, Object b) {
    final da = DateTime.tryParse('$a');
    final db = DateTime.tryParse('$b');
    if (da != null && db != null) return da.compareTo(db);
    return '$a'.compareTo('$b');
  }

  @override
  PostgrestFilterBuilder<PostgrestList> eq(String column, Object value) {
    _query.filters.add((r) => r[column] == null || r[column] == value);
    return this;
  }

  @override
  PostgrestFilterBuilder<PostgrestList> gt(String column, Object value) {
    _query.filters.add((r) => r[column] == null || _compare(r[column], value) > 0);
    return this;
  }

  @override
  PostgrestFilterBuilder<PostgrestList> gte(String column, Object value) {
    _query.filters.add((r) => r[column] == null || _compare(r[column], value) >= 0);
    return this;
  }

  @override
  PostgrestFilterBuilder<PostgrestList> or(String filters, {String? referencedTable}) {
    final m = _keyset.firstMatch(filters);
    if (m == null) throw UnsupportedError('FakeSelectBuilder cannot evaluate or($filters)');
    _query.filters.add((r) {
      final byTime = _compare(r['updated_at'], m.group(1)!);
      return byTime > 0 || (byTime == 0 && '${r['id']}'.compareTo(m.group(3)!) > 0);
    });
    return this;
  }

  @override
  PostgrestTransformBuilder<PostgrestList> order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
  }) {
    _query.ordered = true; // SyncManager orders by (updated_at, id) ascending
    return this;
  }

  @override
  PostgrestTransformBuilder<PostgrestList> limit(int count, {String? referencedTable}) {
    _query.limit = count;
    return this;
  }

  @override
  Future<R> then<R>(FutureOr<R> Function(PostgrestList value) onValue, {Function? onError}) {
    var result = rows.where((r) => _query.filters.every((f) => f(r))).toList();
    if (_query.ordered) {
      result.sort((a, b) {
        final byTime = _compare(a['updated_at'], b['updated_at'] ?? '');
        return byTime != 0 ? byTime : '${a['id']}'.compareTo('${b['id']}');
      });
    }
    for (final limit in [_query.limit, maxRows]) {
      if (limit != null && result.length > limit) result = result.sublist(0, limit);
    }
    return Future<PostgrestList>.value(result).then(onValue, onError: onError);
  }
}

class FakeFilterBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  final Object? result;
  final Object? error;

  FakeFilterBuilder(this.result, {this.error});

  @override
  PostgrestFilterBuilder<T> eq(String column, Object value) => this;

  @override
  PostgrestFilterBuilder<T> gt(String column, Object value) => this;

  // `await` drives a non-native future through the callbacks passed to `then`,
  // so delegate to a real Future to deliver both results and errors.
  @override
  Future<R> then<R>(FutureOr<R> Function(T value) onValue, {Function? onError}) {
    final future = error != null ? Future<T>.error(error!) : Future<T>.value(result as T);
    return future.then(onValue, onError: onError);
  }
}
