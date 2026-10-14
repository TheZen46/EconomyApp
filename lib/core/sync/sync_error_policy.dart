import 'package:supabase_flutter/supabase_flutter.dart';

final RegExp _postgrestRequestOrSchemaError = RegExp(r'^PGRST[12]\d\d$');
final RegExp _permanentSqlState = RegExp(r'^(22|23|42)[0-9A-Z]{3}$');

/// Whether retrying the request that raised [error] cannot succeed without a
/// change to the data or the schema, so the mutation should be dead-lettered
/// at once instead of being retried.
///
/// Permanent:
/// - PostgREST request errors (`PGRST1xx`) and schema-cache errors (`PGRST2xx`,
///   e.g. `PGRST204`, a column that does not exist);
/// - PostgreSQL data exceptions (class 22), integrity constraint violations
///   (class 23) and syntax or access rule violations (class 42, including
///   row-level security rejections, `42501`);
/// - other HTTP 4xx statuses, except 401 (expired session), 408 and 429.
///
/// Everything else, including network errors, connection and authentication
/// errors and 5xx responses, is treated as transient.
bool isPermanentSyncError(Object error) {
  if (error is! PostgrestException) return false;
  final code = error.code;
  if (code == null) return false;
  if (_postgrestRequestOrSchemaError.hasMatch(code)) return true;
  if (_permanentSqlState.hasMatch(code)) return true;

  // PostgrestException carries the bare HTTP status when the body was not a
  // PostgREST error object.
  if (code.length == 3) {
    final status = int.tryParse(code);
    if (status != null && status >= 400 && status < 500) {
      return status != 401 && status != 408 && status != 429;
    }
  }
  return false;
}
