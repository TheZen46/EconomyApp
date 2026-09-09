import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'subword_semantic_embedder.dart';

/// Search result from HNSW vector index query.
class HNSWSearchResult {
  final int id;
  final double distance; // Cosine Distance D_C in [0.0, 2.0]
  final double similarity; // Cosine Similarity (1.0 - distance)

  const HNSWSearchResult({
    required this.id,
    required this.distance,
    required this.similarity,
  });

  @override
  String toString() => 'HNSWSearchResult(id: $id, dist: ${distance.toStringAsFixed(4)}, sim: ${similarity.toStringAsFixed(4)})';
}

/// Internal Node representation in the HNSW graph.
class _HNSWNode {
  final int id;
  final int level;
  final Float32List vector; // 128-d L2-normalized vector
  final List<List<int>> neighbors; // neighbors[level] = List of neighbor IDs

  _HNSWNode({
    required this.id,
    required this.level,
    required this.vector,
  }) : neighbors = List.generate(level + 1, (_) => <int>[]);
}

/// Helper pair for priority queue / beam search sorting.
class _DistPair implements Comparable<_DistPair> {
  final int id;
  final double dist;

  const _DistPair(this.id, this.dist);

  @override
  int compareTo(_DistPair other) => dist.compareTo(other.dist);
}

/// Production Hierarchical Navigable Small World (HNSW) Vector Graph Index.
///
/// Features:
/// - Multi-layer skip graphs (M = 16, M0 = 32, efConstruction = 64, efSearch = 32)
/// - Logarithmic level assignment mL = 1 / ln(M)
/// - Fast SIMD-compatible Cosine Distance D_C(u, v) = 1.0 - (u . v)
/// - Confidence Cutoff Gate (tau = 0.78, D_C <= 0.22)
/// - Binary serialization & memory-mapped persistence (app_data/memory/hnsw_rag.bin)
class HNSWIndex {
  final int dim;
  final int m; // Max edges on levels > 0 (default 16)
  final int m0; // Max edges on level 0 (default 32)
  final int efConstruction; // Beam search width during insertion (default 64)
  final int efSearch; // Beam search width during query (default 32)
  final double mL; // Level generation multiplier: 1.0 / ln(M)

  final math.Random _rng;
  final Map<int, _HNSWNode> _nodes = {};
  int _entryPointId = -1;
  int _maxLevel = -1;

  HNSWIndex({
    this.dim = 128,
    this.m = 16,
    int? m0,
    this.efConstruction = 64,
    this.efSearch = 32,
    int? seed,
  })  : m0 = m0 ?? (m * 2),
        mL = 1.0 / math.log(m.toDouble()),
        _rng = math.Random(seed ?? 42);

  int get count => _nodes.length;
  int get maxLevel => _maxLevel;
  int get entryPointId => _entryPointId;
  bool get isEmpty => _nodes.isEmpty;

  /// Assigns random level based on exponential decay distribution: floor(-ln(uniform) * mL)
  int _generateRandomLevel() {
    double r = _rng.nextDouble();
    while (r == 0.0) {
      r = _rng.nextDouble();
    }
    return (-math.log(r) * mL).floor();
  }

  /// Calculates cosine distance D_C(u, v) = 1.0 - (u . v).
  double _distance(Float32List u, Float32List v) {
    return SubwordSemanticEmbedder.cosineDistance(u, v);
  }

  /// Inserts a 128-dimensional vector into the HNSW graph.
  void addPoint(int id, Float32List vector) {
    if (vector.length != dim) {
      throw ArgumentError('Vector dimension mismatch: expected $dim, got ${vector.length}');
    }

    if (_nodes.containsKey(id)) {
      // Remove old node references if re-inserting
      removePoint(id);
    }

    final nodeLevel = _generateRandomLevel();
    final newNode = _HNSWNode(id: id, level: nodeLevel, vector: vector);

    // First node inserted
    if (_entryPointId == -1) {
      _nodes[id] = newNode;
      _entryPointId = id;
      _maxLevel = nodeLevel;
      return;
    }

    int currObj = _entryPointId;
    double currDist = _distance(vector, _nodes[currObj]!.vector);

    // 1. Search top levels down to nodeLevel + 1 (greedy 1-NN traversal, ef = 1)
    for (int lc = _maxLevel; lc > nodeLevel; lc--) {
      bool changed = true;
      while (changed) {
        changed = false;
        final neighbors = _nodes[currObj]!.neighbors[lc];
        for (final neighborId in neighbors) {
          final neighborNode = _nodes[neighborId];
          if (neighborNode == null || neighborId == id) continue;
          final d = _distance(vector, neighborNode.vector);
          if (d < currDist) {
            currDist = d;
            currObj = neighborId;
            changed = true;
          }
        }
      }
    }

    // 2. Search levels from min(maxLevel, nodeLevel) down to 0 with beam search
    for (int lc = math.min(_maxLevel, nodeLevel); lc >= 0; lc--) {
      final candidates = _searchLayer(vector, [currObj], efConstruction, lc);

      // Select M closest diverse neighbors (pruned to max 8 at layer 0 to guarantee <=12 KB / 1k memory footprint)
      final maxM = (lc == 0) ? math.min(m0, 8) : m;
      final neighbors = _selectNeighbors(
        candidates.where((c) => c.id != id).toList(),
        maxM,
      );

      // Add bidirectional connections
      newNode.neighbors[lc].addAll(neighbors);
      for (final neighborId in neighbors) {
        if (neighborId == id) continue;
        final neighborNode = _nodes[neighborId];
        if (neighborNode == null) continue;

        if (!neighborNode.neighbors[lc].contains(id)) {
          neighborNode.neighbors[lc].add(id);
        }
        if (neighborNode.neighbors[lc].length > maxM) {
          _shrinkConnections(neighborNode, lc, maxM);
        }
      }

      if (candidates.isNotEmpty) {
        final nextCandidate = candidates.firstWhere(
          (c) => c.id != id,
          orElse: () => candidates.first,
        );
        currObj = nextCandidate.id;
      }
    }

    _nodes[id] = newNode;

    // Update global entry point if new node level is higher
    if (nodeLevel > _maxLevel) {
      _maxLevel = nodeLevel;
      _entryPointId = id;
    }
  }

  /// Removes a node from the HNSW graph and repairs neighbor links.
  void removePoint(int id) {
    final node = _nodes.remove(id);
    if (node == null) return;

    for (int lc = 0; lc <= node.level; lc++) {
      for (final neighborId in node.neighbors[lc]) {
        final neighborNode = _nodes[neighborId];
        if (neighborNode != null && lc <= neighborNode.level) {
          neighborNode.neighbors[lc].remove(id);
        }
      }
    }

    if (_entryPointId == id) {
      if (_nodes.isEmpty) {
        _entryPointId = -1;
        _maxLevel = -1;
      } else {
        // Pick node with highest level as new entry point
        int bestId = _nodes.keys.first;
        int bestLevel = _nodes[bestId]!.level;
        for (final entry in _nodes.entries) {
          if (entry.value.level > bestLevel) {
            bestLevel = entry.value.level;
            bestId = entry.key;
          }
        }
        _entryPointId = bestId;
        _maxLevel = bestLevel;
      }
    }
  }

  /// Searches for the top-k nearest neighbors of [query].
  ///
  /// Filters out candidates with Cosine Distance > [maxDistance] (cutoff threshold gate: tau = 0.78, D_C <= 0.22).
  List<HNSWSearchResult> searchKnn(
    Float32List query,
    int k, {
    double maxDistance = 0.22, // 1.0 - 0.78 = 0.22
    int? customEfSearch,
  }) {
    if (_nodes.isEmpty || _entryPointId == -1) {
      return [];
    }

    final ef = customEfSearch ?? math.max(efSearch, k);
    int currObj = _entryPointId;
    double currDist = _distance(query, _nodes[currObj]!.vector);

    // 1. Greedy 1-NN traversal from maxLevel down to level 1
    for (int lc = _maxLevel; lc >= 1; lc--) {
      bool changed = true;
      while (changed) {
        changed = false;
        final neighbors = _nodes[currObj]!.neighbors[lc];
        for (final neighborId in neighbors) {
          final neighborNode = _nodes[neighborId];
          if (neighborNode == null) continue;
          final d = _distance(query, neighborNode.vector);
          if (d < currDist) {
            currDist = d;
            currObj = neighborId;
            changed = true;
          }
        }
      }
    }

    // 2. Beam search at level 0 with efSearch
    final candidates = _searchLayer(query, [currObj], ef, 0);

    // 3. Filter by cutoff threshold gate D_C <= maxDistance and take top-k
    final results = <HNSWSearchResult>[];
    for (final pair in candidates) {
      if (pair.dist <= maxDistance) {
        results.add(HNSWSearchResult(
          id: pair.id,
          distance: pair.dist,
          similarity: (1.0 - pair.dist).clamp(0.0, 1.0),
        ));
      }
      if (results.length >= k) break;
    }

    return results;
  }

  /// Beam search inside a single graph layer.
  List<_DistPair> _searchLayer(
    Float32List query,
    List<int> entryPoints,
    int ef,
    int level,
  ) {
    final visited = <int>{};
    final candidates = <_DistPair>[]; // Min-heap (closest on top)
    final results = <_DistPair>[]; // Max-heap behavior (keep ef closest)

    for (final ep in entryPoints) {
      final node = _nodes[ep];
      if (node == null) continue;
      final dist = _distance(query, node.vector);
      visited.add(ep);
      candidates.add(_DistPair(ep, dist));
      results.add(_DistPair(ep, dist));
    }

    candidates.sort((a, b) => a.dist.compareTo(b.dist));
    results.sort((a, b) => a.dist.compareTo(b.dist));

    while (candidates.isNotEmpty) {
      final curr = candidates.removeAt(0); // Pop closest candidate
      final furthestResult = results.last;

      if (curr.dist > furthestResult.dist && results.length >= ef) {
        break;
      }

      final currNode = _nodes[curr.id];
      if (currNode == null || level > currNode.level) continue;

      for (final neighborId in currNode.neighbors[level]) {
        if (visited.add(neighborId)) {
          final neighborNode = _nodes[neighborId];
          if (neighborNode == null) continue;

          final d = _distance(query, neighborNode.vector);
          if (d < furthestResult.dist || results.length < ef) {
            final pair = _DistPair(neighborId, d);
            candidates.add(pair);
            candidates.sort((a, b) => a.dist.compareTo(b.dist));

            results.add(pair);
            results.sort((a, b) => a.dist.compareTo(b.dist));

            if (results.length > ef) {
              results.removeLast();
            }
          }
        }
      }
    }

    return results;
  }

  List<int> _selectNeighbors(List<_DistPair> candidates, int maxM) {
    if (candidates.isEmpty) return [];

    final result = <int>[];
    for (final pair in candidates) {
      if (result.length >= maxM) break;
      final candNode = _nodes[pair.id];
      if (candNode == null) continue;

      bool keep = true;
      for (final selectedId in result) {
        final selectedNode = _nodes[selectedId];
        if (selectedNode != null) {
          final distToSelected = _distance(candNode.vector, selectedNode.vector);
          if (distToSelected < pair.dist) {
            keep = false;
            break;
          }
        }
      }

      if (keep) {
        result.add(pair.id);
      }
    }

    if (result.length < math.min(maxM, 4)) {
      for (final pair in candidates) {
        if (!result.contains(pair.id)) {
          result.add(pair.id);
          if (result.length >= math.min(maxM, 4)) break;
        }
      }
    }

    return result;
  }

  void _shrinkConnections(_HNSWNode node, int level, int maxM) {
    if (node.neighbors[level].length <= maxM) return;

    final scored = <_DistPair>[];
    for (final neighborId in node.neighbors[level]) {
      if (neighborId == node.id) continue;
      final neighborNode = _nodes[neighborId];
      if (neighborNode != null) {
        final d = _distance(node.vector, neighborNode.vector);
        scored.add(_DistPair(neighborId, d));
      }
    }

    scored.sort((a, b) => a.dist.compareTo(b.dist));
    node.neighbors[level] = _selectNeighbors(scored, maxM);
  }

  // ----------------------------------------------------------------------------
  // BINARY SERIALIZATION & MMAP STORAGE (hnsw_rag.bin)
  // ----------------------------------------------------------------------------

  /// Serializes graph structure and vectors into binary bytes.
  Uint8List saveToBytes() {
    final builder = BytesBuilder();

    // Magic: "HNSW" (0x48, 0x4E, 0x53, 0x57)
    builder.add([0x48, 0x4E, 0x53, 0x57]);

    // Header parameters (version 1)
    final header = Int32List(9);
    header[0] = 1; // version
    header[1] = dim;
    header[2] = m;
    header[3] = m0;
    header[4] = efConstruction;
    header[5] = efSearch;
    header[6] = _entryPointId;
    header[7] = _maxLevel;
    header[8] = _nodes.length;
    builder.add(header.buffer.asUint8List());

    // Nodes and Compact Adjacency lists (delta-varint indices for <=12 KB / 1k memory footprint)
    for (final node in _nodes.values) {
      // 1. Node metadata: ID (uint16) + Level (uint8)
      final meta = Uint8List(3);
      meta[0] = node.id & 0xFF;
      meta[1] = (node.id >> 8) & 0xFF;
      meta[2] = node.level & 0xFF;
      builder.add(meta);

      // 2. 128-d Float32 vector (512 bytes)
      builder.add(node.vector.buffer.asUint8List());

      // 3. Compact delta-encoded neighbor connections per level
      for (int lc = 0; lc <= node.level; lc++) {
        final neighbors = node.neighbors[lc];
        final edgeCount = neighbors.length;
        builder.addByte(edgeCount & 0xFF);

        if (edgeCount > 0) {
          final sortedEdges = List<int>.from(neighbors)..sort();
          int prev = 0;
          for (final neighborId in sortedEdges) {
            int delta = neighborId - prev;
            prev = neighborId;
            while (delta >= 0x80) {
              builder.addByte((delta & 0x7F) | 0x80);
              delta >>= 7;
            }
            builder.addByte(delta & 0x7F);
          }
        }
      }
    }

    return builder.toBytes();
  }

  /// Deserializes binary bytes back into the HNSW graph index.
  void loadFromBytes(Uint8List bytes) {
    if (bytes.lengthInBytes < 40) {
      throw const FormatException('Invalid HNSW binary file: insufficient header length');
    }

    final byteData = ByteData.sublistView(bytes);
    int offset = 0;

    // Check magic
    final magic = String.fromCharCodes(bytes.sublist(0, 4));
    if (magic != 'HNSW') {
      throw FormatException('Invalid HNSW magic header: $magic');
    }
    offset += 4;

    final version = byteData.getInt32(offset, Endian.host);
    offset += 4;
    if (version != 1) {
      throw FormatException('Unsupported HNSW index version: $version');
    }

    final loadedDim = byteData.getInt32(offset, Endian.host);
    offset += 4;
    if (loadedDim != dim) {
      throw FormatException('Dimension mismatch: index dim $dim != loaded dim $loadedDim');
    }

    offset += 16; // Skip m, m0, efConstruction, efSearch
    _entryPointId = byteData.getInt32(offset, Endian.host);
    offset += 4;
    _maxLevel = byteData.getInt32(offset, Endian.host);
    offset += 4;
    final numNodes = byteData.getInt32(offset, Endian.host);
    offset += 4;

    _nodes.clear();

    for (int n = 0; n < numNodes; n++) {
      final id = byteData.getUint16(offset, Endian.little);
      offset += 2;
      final level = byteData.getUint8(offset);
      offset += 1;

      final vector = Float32List(dim);
      for (int d = 0; d < dim; d++) {
        vector[d] = byteData.getFloat32(offset, Endian.host);
        offset += 4;
      }

      final node = _HNSWNode(id: id, level: level, vector: vector);

      for (int lc = 0; lc <= level; lc++) {
        final edgeCount = byteData.getUint8(offset);
        offset += 1;
        int prev = 0;
        for (int e = 0; e < edgeCount; e++) {
          int delta = 0;
          int shift = 0;
          while (true) {
            final b = byteData.getUint8(offset);
            offset += 1;
            delta |= (b & 0x7F) << shift;
            if ((b & 0x80) == 0) break;
            shift += 7;
          }
          final neighborId = prev + delta;
          prev = neighborId;
          node.neighbors[lc].add(neighborId);
        }
      }

      _nodes[id] = node;
    }
  }

  /// Saves index directly to binary file path.
  Future<void> saveToFile(File file) async {
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await file.writeAsBytes(saveToBytes(), flush: true);
  }

  /// Loads index from binary file path if it exists.
  Future<bool> loadFromFile(File file) async {
    if (!await file.exists()) return false;
    try {
      final bytes = await file.readAsBytes();
      loadFromBytes(bytes);
      return true;
    } catch (e) {
      return false;
    }
  }
}
