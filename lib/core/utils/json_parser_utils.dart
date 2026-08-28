import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import '../error/failures.dart';

/// Robust JSON extraction, repair, and parsing utility for LLM outputs.
///
/// LLMs frequently emit malformed or noisy JSON, such as:
///   • Markdown code fences (```json ... ```)
///   • Conversational commentary before or after the JSON payload
///   • Trailing commas before closing brackets (`,}` or `,]`)
///   • Unescaped newlines and tabs inside string literals
///   • Unclosed quotes or unclosed outer/nested brackets from token truncation
///
/// This utility extracts, repairs, and safely parses JSON without throwing uncaught exceptions.
class JsonParserUtils {
  JsonParserUtils._();

  /// Parses raw LLM text into a typed JSON map, returning an [Either] with [ParsingFailure]
  /// or the successfully parsed [Map<String, dynamic>].
  static Either<ParsingFailure, Map<String, dynamic>> parseJsonSafe(String response) {
    if (response.trim().isEmpty) {
      return const Left(ParsingFailure('Response is empty'));
    }

    final rawBlock = extractJsonBlock(response);
    if (rawBlock == null) {
      return Left(ParsingFailure('No JSON block found in response', response));
    }

    // 1. Direct parse attempt
    try {
      final decoded = jsonDecode(rawBlock);
      if (decoded is Map<String, dynamic>) {
        return Right(decoded);
      } else if (decoded is Map) {
        return Right(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Proceed to repair
    }

    // 2. Repair and parse attempt
    try {
      final repaired = repairJson(rawBlock);
      final decoded = jsonDecode(repaired);
      if (decoded is Map<String, dynamic>) {
        return Right(decoded);
      } else if (decoded is Map) {
        return Right(Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      debugPrint('JsonParserUtils: Repaired JSON decode failed: $e');
    }

    // 3. Fallback: try parsing with aggressive normalization
    try {
      final aggressive = _aggressiveRepair(rawBlock);
      final decoded = jsonDecode(aggressive);
      if (decoded is Map<String, dynamic>) {
        return Right(decoded);
      } else if (decoded is Map) {
        return Right(Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      debugPrint('JsonParserUtils: Aggressive repair decode failed: $e');
    }

    return Left(ParsingFailure('Failed to decode JSON after repair attempts', rawBlock));
  }

  /// Extracts the primary JSON map from raw LLM output.
  /// Returns `null` if parsing and repair fails. Never throws.
  static Map<String, dynamic>? extractJsonMap(String response) {
    return parseJsonSafe(response).fold(
      (failure) => null,
      (data) => data,
    );
  }

  /// Extracts the outermost JSON block using regex and brace indexing.
  /// Locates the first outer `{` and matching/last `}`.
  static String? extractJsonBlock(String response) {
    if (response.trim().isEmpty) return null;

    // 1. Check for markdown code fences first
    final fencedRegex = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      multiLine: true,
      caseSensitive: false,
    );
    final fencedMatch = fencedRegex.firstMatch(response);
    if (fencedMatch != null) {
      final inner = fencedMatch.group(1)!.trim();
      final firstBrace = inner.indexOf('{');
      final lastBrace = inner.lastIndexOf('}');
      if (firstBrace != -1) {
        if (lastBrace > firstBrace) {
          return inner.substring(firstBrace, lastBrace + 1).trim();
        }
        return inner.substring(firstBrace).trim();
      }
    }

    // 2. Find first '{' and last '}'
    final start = response.indexOf('{');
    if (start == -1) return null;

    final end = response.lastIndexOf('}');
    if (end > start) {
      return response.substring(start, end + 1).trim();
    }

    // Truncated block without closing brace
    return response.substring(start).trim();
  }

  /// Repairs common LLM output defects:
  /// - Strips single-line and multi-line comments
  /// - Removes trailing commas before `}` and `]`
  /// - Fixes unclosed quotes before commas on key-value lines
  /// - Escapes raw control characters in string literals
  /// - Closes missing outer and nested brackets/braces
  static String repairJson(String raw) {
    var text = raw.trim();

    // 1. Remove comments
    text = text.replaceAll(RegExp(r'//.*$', multiLine: true), '');
    text = text.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');

    // 2. Replace Python/JS literals (None -> null, True -> true, False -> false)
    text = text.replaceAll(RegExp(r'\bNone\b'), 'null');
    text = text.replaceAll(RegExp(r'\bTrue\b'), 'true');
    text = text.replaceAll(RegExp(r'\bFalse\b'), 'false');

    // 3. Fix unclosed quotes before commas (e.g. "key": "value, -> "key": "value",)
    text = _fixUnclosedQuotesBeforeCommas(text);

    // 4. Sanitize unescaped newlines / tabs inside string literals
    text = _sanitizeStringLiterals(text);

    // 5. Remove trailing commas before closing braces/brackets
    text = text.replaceAllMapped(RegExp(r',\s*([\}\]])'), (m) => m.group(1)!);

    // 6. Balance unclosed brackets and braces
    text = _balanceBrackets(text);

    // 7. Final trailing comma cleanup after balancing
    text = text.replaceAllMapped(RegExp(r',\s*([\}\]])'), (m) => m.group(1)!);

    return text;
  }

  /// Fixes missing closing quotes on string values that end with a comma:
  /// e.g. `"merchantName": "Whole Foods Market,` -> `"merchantName": "Whole Foods Market",`
  static String _fixUnclosedQuotesBeforeCommas(String input) {
    return input.replaceAllMapped(
      RegExp(r'(\s*"[^"]+"\s*:\s*")([^"\n\r]+)(,)\s*$', multiLine: true),
      (m) => '${m.group(1)}${m.group(2)}"${m.group(3)}',
    );
  }

  /// Scans string literals to escape unescaped control characters and close trailing open quotes.
  static String _sanitizeStringLiterals(String input) {
    final buffer = StringBuffer();
    bool inString = false;
    bool escaped = false;

    for (int i = 0; i < input.length; i++) {
      final char = input[i];

      if (escaped) {
        buffer.write(char);
        escaped = false;
        continue;
      }

      if (char == r'\') {
        buffer.write(char);
        escaped = true;
        continue;
      }

      if (char == '"') {
        inString = !inString;
        buffer.write(char);
        continue;
      }

      if (inString) {
        if (char == '\n') {
          buffer.write(r'\n');
        } else if (char == '\r') {
          buffer.write(r'\r');
        } else if (char == '\t') {
          buffer.write(r'\t');
        } else {
          buffer.write(char);
        }
      } else {
        buffer.write(char);
      }
    }

    if (inString) {
      buffer.write('"');
    }

    return buffer.toString();
  }

  /// Balances unclosed `{` and `[` by appending missing `}` and `]`.
  static String _balanceBrackets(String input) {
    final stack = <String>[];
    bool inString = false;
    bool escaped = false;

    for (int i = 0; i < input.length; i++) {
      final char = input[i];

      if (escaped) {
        escaped = false;
        continue;
      }

      if (char == r'\') {
        escaped = true;
        continue;
      }

      if (char == '"') {
        inString = !inString;
        continue;
      }

      if (inString) continue;

      if (char == '{') {
        stack.add('}');
      } else if (char == '[') {
        stack.add(']');
      } else if (char == '}' || char == ']') {
        if (stack.isNotEmpty && stack.last == char) {
          stack.removeLast();
        }
      }
    }

    final buffer = StringBuffer(input);
    while (stack.isNotEmpty) {
      buffer.write(stack.removeLast());
    }

    return buffer.toString();
  }

  /// Aggressive fallback repair: handles single quotes used as keys/values
  static String _aggressiveRepair(String raw) {
    var text = repairJson(raw);
    text = text.replaceAllMapped(
      RegExp(r"(?<=\{|\[|,|:)\s*'([^'\\]*(?:\\.[^'\\]*)*)'\s*(?=\}|\]|,|:)"),
      (m) => ' "${m.group(1)}" ',
    );
    return repairJson(text);
  }

  /// Generates a structured fallback receipt map for partial/failed extractions.
  static Map<String, dynamic> createFallbackReceiptMap({
    String merchantName = 'Unknown Merchant',
    double totalAmount = 0.0,
    String currency = 'USD',
    DateTime? date,
    List<Map<String, dynamic>> items = const [],
  }) {
    return {
      'merchantName': merchantName,
      'date': (date ?? DateTime.now()).toIso8601String().split('T').first,
      'totalAmount': totalAmount,
      'currency': currency,
      'items': items,
    };
  }
}
