import 'dart:math' as math;

/// Hybrid Logical Clock (HLC).
///
/// Combines physical UTC wall clock time with a Lamport logical counter and unique node ID.
/// Eliminates reliance on perfectly synchronized NTP clocks while providing a strict,
/// globally consistent total order ($\prec_{\mathcal{H}}$) across all distributed mobile/desktop replicas.
///
/// Total Order Rule:
/// `H1 < H2 iff (millis1 < millis2) || (millis1 == millis2 && counter1 < counter2) || (millis1 == millis2 && counter1 == counter2 && nodeId1 < nodeId2)`
class Hlc implements Comparable<Hlc> {
  /// Physical timestamp in milliseconds since epoch (UTC).
  final int millis;

  /// Monotonically increasing logical counter for events occurring in the same physical millisecond.
  final int counter;

  /// Unique node / device identifier (e.g. UUIDv7).
  final String nodeId;

  const Hlc({
    required this.millis,
    required this.counter,
    required this.nodeId,
  });

  /// Factory for zero/initial clock.
  factory Hlc.zero(String nodeId) => Hlc(millis: 0, counter: 0, nodeId: nodeId);

  /// Factory for generating an HLC timestamp at current wall time.
  factory Hlc.now(String nodeId) {
    return Hlc(
      millis: DateTime.now().toUtc().millisecondsSinceEpoch,
      counter: 0,
      nodeId: nodeId,
    );
  }

  /// Advances the local clock for a local mutation.
  Hlc send(int physicalNowMillis) {
    if (physicalNowMillis > millis) {
      return Hlc(millis: physicalNowMillis, counter: 0, nodeId: nodeId);
    } else {
      return Hlc(millis: millis, counter: counter + 1, nodeId: nodeId);
    }
  }

  /// Updates the local clock upon receiving a remote message with timestamp [remote].
  Hlc receive(Hlc remote, int physicalNowMillis) {
    final maxMillis = [millis, remote.millis, physicalNowMillis].reduce(math.max);
    int newCounter;
    if (maxMillis == millis && maxMillis == remote.millis) {
      newCounter = [counter, remote.counter].reduce(math.max) + 1;
    } else if (maxMillis == millis) {
      newCounter = counter + 1;
    } else if (maxMillis == remote.millis) {
      newCounter = remote.counter + 1;
    } else {
      newCounter = 0;
    }
    return Hlc(millis: maxMillis, counter: newCounter, nodeId: nodeId);
  }

  @override
  int compareTo(Hlc other) {
    if (millis != other.millis) return millis.compareTo(other.millis);
    if (counter != other.counter) return counter.compareTo(other.counter);
    return nodeId.compareTo(other.nodeId);
  }

  bool isAfter(Hlc other) => compareTo(other) > 0;
  bool isBefore(Hlc other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Hlc &&
        other.millis == millis &&
        other.counter == counter &&
        other.nodeId == nodeId;
  }

  @override
  int get hashCode => Object.hash(millis, counter, nodeId);

  Map<String, dynamic> toJson() => {
        'm': millis,
        'c': counter,
        'd': nodeId,
      };

  factory Hlc.fromJson(Map<String, dynamic> json) => Hlc(
        millis: json['m'] as int,
        counter: json['c'] as int,
        nodeId: json['d'] as String,
      );

  @override
  String toString() => '$millis:$counter:$nodeId';
}
