import 'package:equatable/equatable.dart';

/// Base abstract class representing a domain or operational failure in tAIdy.
///
/// All domain errors extend [Failure] so that repository methods can return
/// an `Either<Failure, T>` rather than throwing uncaught runtime exceptions.
abstract class Failure extends Equatable {
  /// User-facing or log-ready diagnostic message describing the failure.
  final String message;

  /// Creates a [Failure] with the provided [message].
  const Failure(this.message);

  @override
  List<Object> get props => [message];
}

/// Emitted when a remote server or API call fails (HTTP 5xx, timeout, or unexpected server status).
///
/// **Producers:**
/// - `SupabaseDataSourceImpl`: Remote queries, mutations, or auth calls.
/// - `GeminiAiService`: Upstream Google Gemini API errors.
class ServerFailure extends Failure {
  /// Creates a [ServerFailure] with an optional descriptive message.
  const ServerFailure([super.message = 'Server Error']);
}

/// Emitted when a local storage or caching operation fails (Hive read/write error,
/// disk full, or box corruption).
///
/// **Producers:**
/// - `ReceiptRepositoryImpl`: Local Hive operations on the receipt box.
/// - `SyncEngine`: Rehydration and disk writes.
class CacheFailure extends Failure {
  /// Creates a [CacheFailure] with an optional descriptive message.
  const CacheFailure([super.message = 'Cache Error']);
}

/// Emitted when an artificial intelligence extraction pipeline encounters a non-recoverable error.
///
/// **Producers:**
/// - `VlmEngineService`: Native VLM worker crash or timeout.
/// - `GeminiAiService`: Model extraction parse or execution failure.
class AIProcessingFailure extends Failure {
  /// Creates an [AIProcessingFailure] with an optional descriptive message.
  const AIProcessingFailure([super.message = 'AI Processing Error']);
}

/// No extraction backend could read the image (no OCR on this platform, no
/// recognizable text, or no loaded model).
///
/// The caller should offer manual entry instead of presenting any data as extracted.
///
/// **Producers:**
/// - `FallbackAIService`: Desktop or Web execution without on-device OCR.
/// - `ReceiptRepositoryImpl`: Missing image or unrecognized text.
class ExtractionUnavailableFailure extends AIProcessingFailure {
  /// Creates an [ExtractionUnavailableFailure] with a helpful default prompt.
  const ExtractionUnavailableFailure([
    super.message = 'This receipt could not be read automatically. Enter its details manually.',
  ]);
}

/// Emitted when an outgoing webhook dispatch fails to receive a successful HTTP response.
///
/// **Producers:**
/// - `WebhookService`: External HTTP POST delivery to user-configured webhook endpoints.
class WebhookFailure extends Failure {
  /// The HTTP status code returned by the remote webhook receiver, if available.
  final int? statusCode;

  /// Creates a [WebhookFailure] with an optional message and status code.
  const WebhookFailure([super.message = 'Webhook delivery failed.', this.statusCode]);

  @override
  List<Object> get props => [message, statusCode ?? 0];
}

/// Emitted when a JSON or structured AI output payload cannot be parsed.
///
/// **Producers:**
/// - `VlmEngineService`: GBNF output decoding failures.
/// - `GeminiAiService`: Invalid JSON responses from LLM completion.
class ParsingFailure extends Failure {
  /// The raw text content that failed to parse into structured JSON.
  final String? rawContent;

  /// Creates a [ParsingFailure] with optional raw content for diagnostics.
  const ParsingFailure([super.message = 'JSON Parsing Error', this.rawContent]);

  @override
  List<Object> get props => [message, rawContent ?? ''];
}

/// Emitted when parsing tabular CSV data fails due to malformed headers, invalid columns,
/// or type conversion errors.
///
/// **Producers:**
/// - `BankReconciliationService`: Parsing user-imported bank statement CSV files.
class CsvParsingFailure extends Failure {
  /// 1-based index of the line in the CSV file that caused the failure.
  final int? lineNumber;

  /// Raw text content of the row that failed validation.
  final String? rawRow;

  /// Creates a [CsvParsingFailure] with optional line number and raw row content.
  const CsvParsingFailure([super.message = 'CSV Parsing Error', this.lineNumber, this.rawRow]);

  @override
  List<Object> get props => [message, lineNumber ?? 0, rawRow ?? ''];
}

/// Emitted when an on-device AI model weights file fails cryptographic hash or size validation.
///
/// **Producers:**
/// - `VlmEngineService`: SHA-256 integrity verification of downloaded GGUF weights.
class ModelValidationFailure extends Failure {
  /// The expected SHA-256 hash digest.
  final String? expectedChecksum;

  /// The actual computed SHA-256 hash digest of the local file.
  final String? actualChecksum;

  /// Creates a [ModelValidationFailure] with optional checksum details.
  const ModelValidationFailure([
    super.message = 'Model file integrity validation failed.',
    this.expectedChecksum,
    this.actualChecksum,
  ]);

  @override
  List<Object> get props => [message, expectedChecksum ?? '', actualChecksum ?? ''];
}

// ── Auth Failures ─────────────────────────────────────────────────────────────

/// Base class for user authentication and session management failures.
abstract class AuthFailure extends Failure {
  /// Creates an [AuthFailure] with the specified error message.
  const AuthFailure(super.message);
}

/// Emitted when the user provides an invalid password or email mismatch during login.
///
/// **Producers:**
/// - `AuthRepositoryImpl`: Sign-in credential verification.
class InvalidCredentialsFailure extends AuthFailure {
  /// Creates an [InvalidCredentialsFailure] with standard user-facing message.
  const InvalidCredentialsFailure([super.message = 'Invalid email or password.']);
}

/// Emitted when attempting to authenticate or reset password for an email that does not exist.
///
/// **Producers:**
/// - `AuthRepositoryImpl`: User lookup in local or remote authentication directories.
class UserNotFoundFailure extends AuthFailure {
  /// Creates a [UserNotFoundFailure] with standard user-facing message.
  const UserNotFoundFailure([super.message = 'No account found with this email.']);
}

/// Emitted during user registration if an account already exists with the requested email address.
///
/// **Producers:**
/// - `AuthRepositoryImpl`: Sign-up conflict detection.
class EmailAlreadyInUseFailure extends AuthFailure {
  /// Creates an [EmailAlreadyInUseFailure] with standard conflict message.
  const EmailAlreadyInUseFailure([super.message = 'An account already exists with this email.']);
}

/// Emitted during authentication when the network is unreachable or socket connections time out.
///
/// **Producers:**
/// - `AuthRepositoryImpl`: Remote authentication endpoint connectivity.
class NetworkFailure extends AuthFailure {
  /// Creates a [NetworkFailure] with standard connectivity message.
  const NetworkFailure([super.message = 'Network error. Please check your connection.']);
}
