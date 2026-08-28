import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../error/failures.dart';

/// Central error handler that maps low-level Dart/Flutter exceptions, Dio errors,
/// and Supabase errors into human-readable domain [Failure] objects.
///
/// Ensures raw technical stack traces and exception strings are never directly
/// displayed in user-facing dialogs or SnackBars.
class ErrorHandler {
  /// Maps any caught error or exception into a strongly-typed domain [Failure].
  /// Logs diagnostic details to debugPrint while ensuring user-facing messages
  /// remain sanitized, human-readable, and free of technical stack traces.
  static Failure mapException(Object error, [StackTrace? stackTrace]) {
    // 1. Diagnostic Logging
    if (kDebugMode) {
      debugPrint('ErrorHandler [DIAGNOSTIC]: $error');
      if (stackTrace != null) {
        debugPrint('ErrorHandler [STACK]: $stackTrace');
      }
    }

    // 2. If already a Failure, return directly
    if (error is Failure) {
      return error;
    }

    // 3. Socket / Network Exceptions
    if (error is SocketException) {
      return const NetworkFailure(
        'Unable to connect to the server. Please check your internet connection.',
      );
    }

    if (error is TimeoutException) {
      return const NetworkFailure(
        'The operation timed out. Please check your connection and try again.',
      );
    }

    if (error is HandshakeException || error is CertificateException) {
      return const ServerFailure(
        'Security handshake failed. Please ensure your connection and device time are secure.',
      );
    }

    if (error is HttpException) {
      return const ServerFailure(
        'HTTP communication failed. The remote server could not be reached.',
      );
    }

    if (error is FormatException) {
      return const ParsingFailure(
        'Data format is invalid or corrupted.',
      );
    }

    if (error is FileSystemException) {
      return const CacheFailure(
        'File storage error. Please check storage permissions or free space.',
      );
    }

    // 4. Dio Exceptions (Webhooks, downloads, HTTP clients)
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          return const NetworkFailure('Connection timed out. Check your network.');
        case DioExceptionType.sendTimeout:
          return const NetworkFailure('Request timed out while sending data.');
        case DioExceptionType.receiveTimeout:
          return const NetworkFailure('Server took too long to respond.');
        case DioExceptionType.connectionError:
          return const NetworkFailure('Connection refused. Verify the destination is reachable.');
        case DioExceptionType.badCertificate:
          return const ServerFailure('SSL certificate error. The endpoint may be insecure.');
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          if (statusCode != null && statusCode >= 500) {
            return WebhookFailure('Server error ($statusCode). Please try again later.', statusCode);
          } else if (statusCode == 401 || statusCode == 403) {
            return WebhookFailure('Access denied ($statusCode). Please check your authorization.', statusCode);
          } else if (statusCode == 404) {
            return WebhookFailure('Endpoint not found ($statusCode). Please check the configured URL.', statusCode);
          }
          return WebhookFailure('Request rejected with status $statusCode.', statusCode);
        case DioExceptionType.cancel:
          return const ServerFailure('Request was cancelled.');
        case DioExceptionType.unknown:
          if (error.error != null) {
            return mapException(error.error!);
          }
          return const NetworkFailure('An unexpected network error occurred.');
      }
    }

    // 5. Supabase Auth / Postgrest Exceptions
    if (error is AuthException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('invalid login') || msg.contains('invalid credentials')) {
        return const InvalidCredentialsFailure();
      }
      if (msg.contains('user not found')) {
        return const UserNotFoundFailure();
      }
      if (msg.contains('already registered') || msg.contains('email already in use')) {
        return const EmailAlreadyInUseFailure();
      }
      return ServerFailure(error.message);
    }

    if (error is PostgrestException) {
      return ServerFailure(
        error.message.isNotEmpty ? error.message : 'Database query failed.',
      );
    }

    if (error is StorageException) {
      return ServerFailure(
        error.message.isNotEmpty ? error.message : 'Cloud storage operation failed.',
      );
    }

    // 6. Generic fallback
    return const ServerFailure('An unexpected error occurred. Please try again.');
  }

  /// Extracts a clean user-facing message from a [Failure] or raw error object.
  static String getUserMessage(Object error) {
    if (error is Failure) {
      return error.message;
    }
    final failure = mapException(error);
    return failure.message;
  }

  /// Displays a standardized user-friendly error dialog with contextual action buttons.
  static Future<void> showErrorDialog({
    required BuildContext context,
    required String title,
    required Object error,
    String primaryActionText = 'Dismiss',
    VoidCallback? onPrimaryAction,
    String? secondaryActionText,
    VoidCallback? onSecondaryAction,
  }) async {
    final message = getUserMessage(error);

    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          if (secondaryActionText != null)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                if (onSecondaryAction != null) onSecondaryAction();
              },
              child: Text(secondaryActionText),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (onPrimaryAction != null) onPrimaryAction();
            },
            child: Text(primaryActionText),
          ),
        ],
      ),
    );
  }

  /// Displays a standardized user-friendly error SnackBar with an action button.
  static void showErrorSnackBar({
    required BuildContext context,
    required Object error,
    String actionLabel = 'Dismiss',
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    final message = getUserMessage(error);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFD4183D),
        duration: duration,
        action: SnackBarAction(
          label: actionLabel,
          textColor: Colors.white,
          onPressed: () {
            if (onAction != null) {
              onAction();
            } else {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            }
          },
        ),
      ),
    );
  }
}
