import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  const Failure(this.message);

  @override
  List<Object> get props => [message];
}

class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Server Error']);
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Cache Error']);
}

class AIProcessingFailure extends Failure {
  const AIProcessingFailure([super.message = 'AI Processing Error']);
}

class WebhookFailure extends Failure {
  final int? statusCode;
  const WebhookFailure([super.message = 'Webhook delivery failed.', this.statusCode]);

  @override
  List<Object> get props => [message, statusCode ?? 0];
}

class ParsingFailure extends Failure {
  final String? rawContent;
  const ParsingFailure([super.message = 'JSON Parsing Error', this.rawContent]);

  @override
  List<Object> get props => [message, rawContent ?? ''];
}

class CsvParsingFailure extends Failure {
  final int? lineNumber;
  final String? rawRow;
  const CsvParsingFailure([super.message = 'CSV Parsing Error', this.lineNumber, this.rawRow]);

  @override
  List<Object> get props => [message, lineNumber ?? 0, rawRow ?? ''];
}

class ModelValidationFailure extends Failure {
  final String? expectedChecksum;
  final String? actualChecksum;
  const ModelValidationFailure([
    super.message = 'Model file integrity validation failed.',
    this.expectedChecksum,
    this.actualChecksum,
  ]);

  @override
  List<Object> get props => [message, expectedChecksum ?? '', actualChecksum ?? ''];
}

// ── Auth Failures ─────────────────────────────────────────────────────────────

abstract class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

class InvalidCredentialsFailure extends AuthFailure {
  const InvalidCredentialsFailure([super.message = 'Invalid email or password.']);
}

class UserNotFoundFailure extends AuthFailure {
  const UserNotFoundFailure([super.message = 'No account found with this email.']);
}

class EmailAlreadyInUseFailure extends AuthFailure {
  const EmailAlreadyInUseFailure([super.message = 'An account already exists with this email.']);
}

class NetworkFailure extends AuthFailure {
  const NetworkFailure([super.message = 'Network error. Please check your connection.']);
}

