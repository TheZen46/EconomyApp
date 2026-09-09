/// Vector Clock for multi-peer causal dependency tracking.
///
/// Tracks logical causal history across distributed nodes to determine whether
/// operations are causally related (A -> B), ancestors/descendants, or concurrent (A || B).
class VectorClock {
  final Map<String, int> entries;

  const VectorClock([this.entries = const {}]);

  /// Returns a new VectorClock with the specified [nodeId] counter incremented.
  VectorClock copyWithIncrement(String nodeId) {
    final newEntries = Map<String, int>.from(entries);
    newEntries[nodeId] = (newEntries[nodeId] ?? 0) + 1;
    return VectorClock(newEntries);
  }

  /// Merges two vector clocks by computing the component-wise supremum (maximum).
  VectorClock merge(VectorClock other) {
    final merged = Map<String, int>.from(entries);
    for (final entry in other.entries.entries) {
      final current = merged[entry.key] ?? 0;
      if (entry.value > current) {
        merged[entry.key] = entry.value;
      }
    }
    return VectorClock(merged);
  }

  /// Returns `true` if this clock is strictly greater than (a causal descendant of) [other].
  bool isDescendantOf(VectorClock other) {
    bool strictlyGreater = false;
    final allKeys = {...entries.keys, ...other.entries.keys};

    for (final key in allKeys) {
      final vSelf = entries[key] ?? 0;
      final vOther = other.entries[key] ?? 0;
      if (vSelf < vOther) return false;
      if (vSelf > vOther) strictlyGreater = true;
    }

    return strictlyGreater;
  }

  /// Returns `true` if this clock is less than or equal to [other].
  bool isAncestorOrEqual(VectorClock other) {
    final allKeys = {...entries.keys, ...other.entries.keys};
    for (final key in allKeys) {
      final vSelf = entries[key] ?? 0;
      final vOther = other.entries[key] ?? 0;
      if (vSelf > vOther) return false;
    }
    return true;
  }

  /// Returns `true` if this clock is concurrent with [other] (neither is an ancestor of the other).
  bool isConcurrentWith(VectorClock other) {
    return !isDescendantOf(other) && !other.isDescendantOf(this) && this != other;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! VectorClock) return false;
    final allKeys = {...entries.keys, ...other.entries.keys};
    for (final k in allKeys) {
      if ((entries[k] ?? 0) != (other.entries[k] ?? 0)) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    int h = 0;
    for (final entry in entries.entries) {
      if (entry.value != 0) {
        h ^= Object.hash(entry.key, entry.value);
      }
    }
    return h;
  }

  Map<String, dynamic> toJson() => entries;

  factory VectorClock.fromJson(Map<String, dynamic> json) =>
      VectorClock(json.map((k, v) => MapEntry(k, v as int)));

  @override
  String toString() => entries.toString();
}
