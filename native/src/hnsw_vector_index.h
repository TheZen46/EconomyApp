#ifndef HNSW_VECTOR_INDEX_H
#define HNSW_VECTOR_INDEX_H

#include <vector>
#include <unordered_map>
#include <queue>
#include <cmath>
#include <random>
#include <algorithm>
#include <shared_mutex>
#include <cstring>
#include <fstream>
#include <cstdint>

#if defined(__AVX2__)
#include <immintrin.h>
#elif defined(__ARM_NEON)
#include <arm_neon.h>
#endif

namespace receipt {

struct HNSWQueryHit {
    int32_t id;
    float distance; // Cosine distance D_C in [0.0, 2.0]
    float similarity; // Cosine similarity in [0.0, 1.0]
};

/**
 * SIMD-Accelerated Cosine Distance between two 128-dimensional L2-normalized float arrays.
 * D_C(u, v) = 1.0 - (u . v)
 */
inline float compute_cosine_distance_128(const float* a, const float* b) {
    float dot = 0.0f;

#if defined(__AVX2__)
    __m256 sum256 = _mm256_setzero_ps();
    for (size_t i = 0; i < 128; i += 8) {
        __m256 va = _mm256_loadu_ps(a + i);
        __m256 vb = _mm256_loadu_ps(b + i);
        sum256 = _mm256_fmadd_ps(va, vb, sum256);
    }
    // Horizontal sum of 8 floats in sum256
    __m128 lo = _mm256_castps256_ps128(sum256);
    __m128 hi = _mm256_extractf128_ps(sum256, 1);
    __m128 s128 = _mm_add_ps(lo, hi);
    s128 = _mm_hadd_ps(s128, s128);
    s128 = _mm_hadd_ps(s128, s128);
    dot = _mm_cvtss_f32(s128);
#elif defined(__ARM_NEON)
    float32x4_t sum0 = vdupq_n_f32(0.0f);
    float32x4_t sum1 = vdupq_n_f32(0.0f);
    float32x4_t sum2 = vdupq_n_f32(0.0f);
    float32x4_t sum3 = vdupq_n_f32(0.0f);

    for (size_t i = 0; i < 128; i += 16) {
        sum0 = vmlaq_f32(sum0, vld1q_f32(a + i), vld1q_f32(b + i));
        sum1 = vmlaq_f32(sum1, vld1q_f32(a + i + 4), vld1q_f32(b + i + 4));
        sum2 = vmlaq_f32(sum2, vld1q_f32(a + i + 8), vld1q_f32(b + i + 8));
        sum3 = vmlaq_f32(sum3, vld1q_f32(a + i + 12), vld1q_f32(b + i + 12));
    }
    float32x4_t s01 = vaddq_f32(sum0, sum1);
    float32x4_t s23 = vaddq_f32(sum2, sum3);
    float32x4_t tot = vaddq_f32(s01, s23);
    dot = vgetq_lane_f32(tot, 0) + vgetq_lane_f32(tot, 1) + vgetq_lane_f32(tot, 2) + vgetq_lane_f32(tot, 3);
#else
    for (size_t i = 0; i < 128; ++i) {
        dot += a[i] * b[i];
    }
#endif

    if (dot > 1.0f) dot = 1.0f;
    if (dot < -1.0f) dot = -1.0f;
    return 1.0f - dot;
}

/**
 * High-Performance Native HNSW Vector Graph Index for Sub-2ms On-Device RAG.
 */
class HNSWVectorIndex {
public:
    static constexpr size_t DIM = 128;
    static constexpr size_t DEFAULT_M = 16;
    static constexpr size_t DEFAULT_M0 = 32;
    static constexpr size_t DEFAULT_EF_CONSTRUCTION = 64;
    static constexpr size_t DEFAULT_EF_SEARCH = 32;

    HNSWVectorIndex(
        size_t m = DEFAULT_M,
        size_t m0 = DEFAULT_M0,
        size_t ef_construction = DEFAULT_EF_CONSTRUCTION,
        size_t ef_search = DEFAULT_EF_SEARCH
    ) : m_(m),
        m0_(m0),
        ef_construction_(ef_construction),
        ef_search_(ef_search),
        m_l_(1.0 / std::log(static_cast<double>(m))),
        entry_point_id_(-1),
        max_level_(-1),
        rng_(42) {}

    ~HNSWVectorIndex() = default;

    size_t size() const {
        std::shared_lock<std::shared_mutex> lock(mutex_);
        return nodes_.size();
    }

    void add_point(int32_t id, const float* vector) {
        std::unique_lock<std::shared_mutex> lock(mutex_);
        if (!vector) return;

        int node_level = generate_random_level();
        Node node;
        node.id = id;
        node.level = node_level;
        std::memcpy(node.vector, vector, DIM * sizeof(float));
        node.neighbors.resize(node_level + 1);

        nodes_[id] = node;

        if (entry_point_id_ == -1) {
            entry_point_id_ = id;
            max_level_ = node_level;
            return;
        }

        int32_t curr_obj = entry_point_id_;
        float curr_dist = compute_cosine_distance_128(vector, nodes_[curr_obj].vector);

        // 1. Greedy 1-NN traversal on upper layers
        for (int lc = max_level_; lc > node_level; --lc) {
            bool changed = true;
            while (changed) {
                changed = false;
                for (int32_t neighbor_id : nodes_[curr_obj].neighbors[lc]) {
                    auto it = nodes_.find(neighbor_id);
                    if (it == nodes_.end()) continue;
                    float d = compute_cosine_distance_128(vector, it->second.vector);
                    if (d < curr_dist) {
                        curr_dist = d;
                        curr_obj = neighbor_id;
                        changed = true;
                    }
                }
            }
        }

        // 2. Beam search down to layer 0
        for (int lc = std::min(max_level_, node_level); lc >= 0; --lc) {
            auto candidates = search_layer(vector, {curr_obj}, ef_construction_, lc);
            size_t max_m = (lc == 0) ? m0_ : m_;

            std::vector<int32_t> selected;
            for (size_t i = 0; i < std::min(max_m, candidates.size()); ++i) {
                selected.push_back(candidates[i].id);
            }

            nodes_[id].neighbors[lc] = selected;

            for (int32_t neighbor_id : selected) {
                auto& neighbor_node = nodes_[neighbor_id];
                neighbor_node.neighbors[lc].push_back(id);

                if (neighbor_node.neighbors[lc].size() > max_m) {
                    shrink_neighbors(neighbor_node, lc, max_m);
                }
            }

            if (!candidates.empty()) {
                curr_obj = candidates.front().id;
            }
        }

        if (node_level > max_level_) {
            max_level_ = node_level;
            entry_point_id_ = id;
        }
    }

    std::vector<HNSWQueryHit> search_knn(
        const float* query,
        size_t k,
        float max_distance = 0.22f, // Cosine threshold tau=0.78
        size_t custom_ef = 0
    ) const {
        std::shared_lock<std::shared_mutex> lock(mutex_);
        if (nodes_.empty() || entry_point_id_ == -1 || !query) {
            return {};
        }

        size_t ef = custom_ef > 0 ? custom_ef : std::max(ef_search_, k);
        int32_t curr_obj = entry_point_id_;
        float curr_dist = compute_cosine_distance_128(query, nodes_.at(curr_obj).vector);

        // 1. Greedy top-down traversal
        for (int lc = max_level_; lc >= 1; --lc) {
            bool changed = true;
            while (changed) {
                changed = false;
                for (int32_t neighbor_id : nodes_.at(curr_obj).neighbors[lc]) {
                    auto it = nodes_.find(neighbor_id);
                    if (it == nodes_.end()) continue;
                    float d = compute_cosine_distance_128(query, it->second.vector);
                    if (d < curr_dist) {
                        curr_dist = d;
                        curr_obj = neighbor_id;
                        changed = true;
                    }
                }
            }
        }

        // 2. Layer 0 beam search
        auto candidates = search_layer(query, {curr_obj}, ef, 0);

        // 3. Filter by distance threshold and return top-k
        std::vector<HNSWQueryHit> results;
        for (const auto& pair : candidates) {
            if (pair.dist <= max_distance) {
                float sim = std::max(0.0f, std::min(1.0f, 1.0f - pair.dist));
                results.push_back({pair.id, pair.dist, sim});
            }
            if (results.size() >= k) break;
        }

        return results;
    }

    bool save_to_file(const char* filepath) const {
        std::shared_lock<std::shared_mutex> lock(mutex_);
        if (!filepath) return false;

        std::ofstream out(filepath, std::ios::binary);
        if (!out.is_open()) return false;

        // Magic: "HNSW"
        const char magic[4] = {'H', 'N', 'S', 'W'};
        out.write(magic, 4);

        int32_t header[9];
        header[0] = 1; // version
        header[1] = static_cast<int32_t>(DIM);
        header[2] = static_cast<int32_t>(m_);
        header[3] = static_cast<int32_t>(m0_);
        header[4] = static_cast<int32_t>(ef_construction_);
        header[5] = static_cast<int32_t>(ef_search_);
        header[6] = entry_point_id_;
        header[7] = max_level_;
        header[8] = static_cast<int32_t>(nodes_.size());
        out.write(reinterpret_cast<const char*>(header), sizeof(header));

        for (const auto& kv : nodes_) {
            const auto& node = kv.second;
            int32_t meta[2] = {node.id, node.level};
            out.write(reinterpret_cast<const char*>(meta), sizeof(meta));
            out.write(reinterpret_cast<const char*>(node.vector), DIM * sizeof(float));

            for (int lc = 0; lc <= node.level; ++lc) {
                int32_t edge_count = static_cast<int32_t>(node.neighbors[lc].size());
                out.write(reinterpret_cast<const char*>(&edge_count), sizeof(int32_t));
                if (edge_count > 0) {
                    out.write(reinterpret_cast<const char*>(node.neighbors[lc].data()), edge_count * sizeof(int32_t));
                }
            }
        }

        return true;
    }

    bool load_from_file(const char* filepath) {
        std::unique_lock<std::shared_mutex> lock(mutex_);
        if (!filepath) return false;

        std::ifstream in(filepath, std::ios::binary);
        if (!in.is_open()) return false;

        char magic[4];
        in.read(magic, 4);
        if (std::memcmp(magic, "HNSW", 4) != 0) return false;

        int32_t header[9];
        in.read(reinterpret_cast<char*>(header), sizeof(header));
        if (header[0] != 1 || header[1] != static_cast<int32_t>(DIM)) return false;

        entry_point_id_ = header[6];
        max_level_ = header[7];
        int32_t num_nodes = header[8];

        nodes_.clear();

        for (int32_t i = 0; i < num_nodes; ++i) {
            int32_t meta[2];
            in.read(reinterpret_cast<char*>(meta), sizeof(meta));
            Node node;
            node.id = meta[0];
            node.level = meta[1];
            in.read(reinterpret_cast<char*>(node.vector), DIM * sizeof(float));

            node.neighbors.resize(node.level + 1);
            for (int lc = 0; lc <= node.level; ++lc) {
                int32_t edge_count = 0;
                in.read(reinterpret_cast<char*>(&edge_count), sizeof(int32_t));
                if (edge_count > 0) {
                    node.neighbors[lc].resize(edge_count);
                    in.read(reinterpret_cast<char*>(node.neighbors[lc].data()), edge_count * sizeof(int32_t));
                }
            }
            nodes_[node.id] = node;
        }

        return true;
    }

private:
    struct DistPair {
        int32_t id;
        float dist;
        bool operator<(const DistPair& other) const { return dist < other.dist; }
        bool operator>(const DistPair& other) const { return dist > other.dist; }
    };

    struct Node {
        int32_t id = 0;
        int level = 0;
        float vector[DIM];
        std::vector<std::vector<int32_t>> neighbors;
    };

    int generate_random_level() {
        std::uniform_real_distribution<double> dist(0.0000001, 1.0);
        return static_cast<int>(-std::log(dist(rng_)) * m_l_);
    }

    std::vector<DistPair> search_layer(
        const float* query,
        const std::vector<int32_t>& enter_points,
        size_t ef,
        int level
    ) const {
        std::unordered_map<int32_t, bool> visited;
        std::vector<DistPair> candidates; // Min-heap (closest on top)
        std::vector<DistPair> results;    // Closest elements

        for (int32_t ep : enter_points) {
            auto it = nodes_.find(ep);
            if (it == nodes_.end()) continue;
            float d = compute_cosine_distance_128(query, it->second.vector);
            visited[ep] = true;
            candidates.push_back({ep, d});
            results.push_back({ep, d});
        }

        std::sort(candidates.begin(), candidates.end(), [](const DistPair& a, const DistPair& b) { return a.dist < b.dist; });
        std::sort(results.begin(), results.end(), [](const DistPair& a, const DistPair& b) { return a.dist < b.dist; });

        while (!candidates.empty()) {
            DistPair curr = candidates.front();
            candidates.erase(candidates.begin());
            DistPair furthest = results.back();

            if (curr.dist > furthest.dist && results.size() >= ef) {
                break;
            }

            auto it = nodes_.find(curr.id);
            if (it == nodes_.end() || level > it->second.level) continue;

            for (int32_t neighbor_id : it->second.neighbors[level]) {
                if (!visited[neighbor_id]) {
                    visited[neighbor_id] = true;
                    auto n_it = nodes_.find(neighbor_id);
                    if (n_it == nodes_.end()) continue;

                    float d = compute_cosine_distance_128(query, n_it->second.vector);
                    if (d < furthest.dist || results.size() < ef) {
                        DistPair pair = {neighbor_id, d};
                        candidates.push_back(pair);
                        std::sort(candidates.begin(), candidates.end(), [](const DistPair& a, const DistPair& b) { return a.dist < b.dist; });

                        results.push_back(pair);
                        std::sort(results.begin(), results.end(), [](const DistPair& a, const DistPair& b) { return a.dist < b.dist; });

                        if (results.size() > ef) {
                            results.pop_back();
                        }
                    }
                }
            }
        }

        return results;
    }

    void shrink_neighbors(Node& node, int level, size_t max_m) {
        if (node.neighbors[level].size() <= max_m) return;

        std::vector<DistPair> scored;
        for (int32_t neighbor_id : node.neighbors[level]) {
            auto it = nodes_.find(neighbor_id);
            if (it != nodes_.end()) {
                float d = compute_cosine_distance_128(node.vector, it->second.vector);
                scored.push_back({neighbor_id, d});
            }
        }

        std::sort(scored.begin(), scored.end(), [](const DistPair& a, const DistPair& b) { return a.dist < b.dist; });
        node.neighbors[level].clear();
        for (size_t i = 0; i < std::min(max_m, scored.size()); ++i) {
            node.neighbors[level].push_back(scored[i].id);
        }
    }

    size_t m_;
    size_t m0_;
    size_t ef_construction_;
    size_t ef_search_;
    double m_l_;

    int32_t entry_point_id_;
    int max_level_;

    mutable std::shared_mutex mutex_;
    mutable std::mt19937 rng_;
    std::unordered_map<int32_t, Node> nodes_;
};

} // namespace receipt

#endif // HNSW_VECTOR_INDEX_H
