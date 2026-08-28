import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:t_aidy/core/error/failures.dart';
import 'package:t_aidy/core/utils/error_handler.dart';

void main() {
  group('ErrorHandler - Exception Mapping & Sanitization', () {
    test('returns original Failure if error is already a Failure domain object', () {
      const original = ServerFailure('Custom server error');
      final result = ErrorHandler.mapException(original);
      expect(result, equals(original));
      expect(result.message, 'Custom server error');
    });

    test('maps SocketException to NetworkFailure with clean user message', () {
      final socketError = const SocketException('Connection refused, errno = 111');
      final result = ErrorHandler.mapException(socketError);

      expect(result, isA<NetworkFailure>());
      expect(result.message, isNot(contains('errno')));
      expect(result.message, isNot(contains('SocketException')));
      expect(result.message, contains('internet connection'));
    });

    test('maps TimeoutException to NetworkFailure', () {
      final timeoutError = TimeoutException('Operation timed out after 10000ms');
      final result = ErrorHandler.mapException(timeoutError);

      expect(result, isA<NetworkFailure>());
      expect(result.message, contains('timed out'));
      expect(result.message, isNot(contains('10000ms')));
    });

    test('maps DioException connection errors to NetworkFailure', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/api/v1/webhook'),
        type: DioExceptionType.connectionError,
        error: const SocketException('Connection reset by peer'),
      );
      final result = ErrorHandler.mapException(dioError);

      expect(result, isA<NetworkFailure>());
      expect(result.message, isNot(contains('DioException')));
      expect(result.message, isNot(contains('SocketException')));
      expect(result.message, contains('Connection refused'));
    });

    test('maps DioException HTTP 404/500 bad responses to WebhookFailure', () {
      final dio404 = DioException(
        requestOptions: RequestOptions(path: '/webhook'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/webhook'),
          statusCode: 404,
        ),
      );
      final result404 = ErrorHandler.mapException(dio404);
      expect(result404, isA<WebhookFailure>());
      expect(result404.message, contains('404'));

      final dio500 = DioException(
        requestOptions: RequestOptions(path: '/webhook'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/webhook'),
          statusCode: 500,
        ),
      );
      final result500 = ErrorHandler.mapException(dio500);
      expect(result500, isA<WebhookFailure>());
      expect(result500.message, contains('500'));
    });

    test('maps AuthException to specific AuthFailure domain types', () {
      const invalidCreds = AuthException('Invalid login credentials');
      expect(ErrorHandler.mapException(invalidCreds), isA<InvalidCredentialsFailure>());

      const userNotFound = AuthException('User not found');
      expect(ErrorHandler.mapException(userNotFound), isA<UserNotFoundFailure>());

      const emailTaken = AuthException('User already registered');
      expect(ErrorHandler.mapException(emailTaken), isA<EmailAlreadyInUseFailure>());
    });

    test('maps raw unhandled exceptions to generic ServerFailure without leaking stack details', () {
      final rawException = Exception('FATAL: corrupted memory pointer at 0xdeadbeef in postgres.c:144');
      final result = ErrorHandler.mapException(rawException);

      expect(result, isA<ServerFailure>());
      expect(result.message, 'An unexpected error occurred. Please try again.');
      expect(result.message, isNot(contains('0xdeadbeef')));
      expect(result.message, isNot(contains('postgres.c')));
    });

    test('getUserMessage returns sanitized user string for any raw exception', () {
      final msg = ErrorHandler.getUserMessage(const SocketException('Failed host lookup'));
      expect(msg, isNotEmpty);
      expect(msg, isNot(contains('SocketException')));
      expect(msg, contains('internet connection'));
    });
  });

  group('ErrorHandler UI - Dialogs and SnackBars', () {
    testWidgets('showErrorDialog displays sanitized message and action buttons', (tester) async {
      bool retryClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                ErrorHandler.showErrorDialog(
                  context: context,
                  title: 'Connection Failed',
                  error: const SocketException('Connection refused'),
                  primaryActionText: 'Dismiss',
                  secondaryActionText: 'Retry',
                  onSecondaryAction: () => retryClicked = true,
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Ensure raw error is not rendered
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.textContaining('Connection refused'), findsNothing);

      // Ensure clean explanation and buttons are present
      expect(find.text('Connection Failed'), findsOneWidget);
      expect(find.textContaining('internet connection'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Tap Retry
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(retryClicked, isTrue);
      expect(find.text('Connection Failed'), findsNothing);
    });

    testWidgets('showErrorSnackBar displays message and action button', (tester) async {
      bool actionClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ErrorHandler.showErrorSnackBar(
                    context: context,
                    error: const ServerFailure('Database save failed'),
                    actionLabel: 'Check Settings',
                    onAction: () => actionClicked = true,
                  );
                },
                child: const Text('Show SnackBar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show SnackBar'));
      await tester.pumpAndSettle();

      expect(find.text('Database save failed'), findsOneWidget);
      expect(find.text('Check Settings'), findsOneWidget);

      await tester.tap(find.text('Check Settings'));
      await tester.pumpAndSettle();

      expect(actionClicked, isTrue);
    });
  });
}
