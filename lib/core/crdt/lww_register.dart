import 'hlc.dart';

/// State-based Last-Write-Wins Register (LWW-Register) CRDT.
///
/// Implements a join-semilattice primitive with verified algebraic properties:
/// 1. Idempotence: `x.merge(x) == x`
/// 2. Commutativity: `x.merge(y) == y.merge(x)`
/// 3. Associativity: `(x.merge(y)).merge(z) == x.merge(y.merge(z))`
class LwwRegister<T> {
  final T value;
  final Hlc hlc;

  const LwwRegister(this.value, this.hlc);

  /// Merges two LWW-Registers by choosing the value with the strictly greater HLC.
  LwwRegister<T> merge(LwwRegister<T> other) {
    return other.hlc.isAfter(hlc) ? other : this;
  }

  Map<String, dynamic> toJson(dynamic Function(T) valueSerializer) => {
        'v': valueSerializer(value),
        'hlc': hlc.toJson(),
      };

  factory LwwRegister.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic) valueDeserializer,
  ) {
    return LwwRegister(
      valueDeserializer(json['v']),
      Hlc.fromJson(json['hlc'] as Map<String, dynamic>),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LwwRegister<T> && other.value == value && other.hlc == hlc;
  }

  @override
  int get hashCode => Object.hash(value, hlc);

  @override
  String toString() => '$value @ $hlc';
}
