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
    return FakeFilterBuilder<PostgrestList>(client.rowsByTable[table] ?? <Map<String, dynamic>>[]);
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
