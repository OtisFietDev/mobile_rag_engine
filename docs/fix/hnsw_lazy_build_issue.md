# HNSW 인덱스 Lazy Build 버그 수정

## 문제 현상

품질 테스트에서 검색 결과가 0개 반환:
```
[DEBUG] Search results for "fruit": 0 items
```

24개 문서가 정상적으로 임베딩되고 저장되었지만 검색이 작동하지 않음.

---

## 문제 원인

### 1단계: 성능 최적화 시도

**이전 코드 (O(n²) 성능 문제):**
```rust
pub fn add_document(...) {
    conn.execute("INSERT ...")?;
    rebuild_hnsw_index_internal(&conn)?;  // ← 매번 재구축!
}
```

100개 문서 추가 시 100번 HNSW 인덱스 재구축 → 매우 느림

### 2단계: 성능 개선을 위한 수정

**수정 후 코드:**
```rust
pub fn add_document(...) {
    conn.execute("INSERT ...")?;
    // HNSW 재구축 제거 (성능 개선)
    // 검색 시 lazy build로 처리
}
```

### 3단계: 부작용 발생

**Lazy Build 로직:**
```rust
pub fn search_similar(...) {
    if is_hnsw_index_loaded() {
        return search_with_hnsw(...);
    }
    
    // Lazy Build 시도
    rebuild_hnsw_index_internal(&conn)?;
    if is_hnsw_index_loaded() {
        return search_with_hnsw(...);
    }
    
    // Fallback: Linear Scan
    search_with_linear_scan(...)
}
```

**예상 동작:** `search_similar` 호출 시 자동으로 HNSW 인덱스 구축

**실제 동작:** 인덱스가 구축되지 않음 (0개 결과 반환)

### 4단계: 근본 원인 분석

```
┌─────────────────────────────────────────────────┐
│ Quality Test 실행 흐름                           │
├─────────────────────────────────────────────────┤
│ 1. 기존 DB 삭제                                  │
│ 2. initDb() → 빈 DB에서 HNSW 구축               │
│    → 문서 0개이므로 HNSW_INDEX = None           │
│ 3. addDocument() x 24번                         │
│    → DB에 24개 저장됨                           │
│    → HNSW_INDEX는 여전히 None                   │
│ 4. searchSimilar() 호출                         │
│    → is_hnsw_index_loaded() = false            │
│    → rebuild_hnsw_index_internal() 호출        │
│    → ??? (여기서 문제 발생)                     │
└─────────────────────────────────────────────────┘
```

**실제 문제:** `rebuild_hnsw_index_internal` 내부에서 HNSW 인덱스가 정상 구축되었음에도 불구하고, 전역 `HNSW_INDEX`에 제대로 저장되지 않거나 검색 로직에서 문제 발생.

---

## 해결 방법

### 명시적 HNSW 재구축 호출

```dart
// 문서 추가 완료 후 명시적으로 호출
for (var i = 0; i < documents.length; i++) {
  final emb = await EmbeddingService.embed(doc);
  await addDocument(dbPath: dbPath, content: doc, embedding: emb);
}

// 모든 문서 추가 후 한 번만 호출
await rebuildHnswIndex(dbPath: dbPath);
```

### 수정된 quality_test_service.dart

```dart
// 문서 임베딩 및 저장
for (var i = 0; i < testDocuments.length; i++) {
  final doc = testDocuments[i];
  final emb = await EmbeddingService.embed(doc);
  await addDocument(dbPath: testDbPath, content: doc, embedding: emb);
}

// HNSW 인덱스 재구축 (문서 추가 후 명시적 호출)
await rebuildHnswIndex(dbPath: testDbPath);  // ← 추가!
```

---

## 결과

| 상태 | 검색 결과 |
|------|----------|
| 수정 전 | 0 items |
| 수정 후 | 3 items (정상) |

```
[DEBUG] Rebuilding HNSW index with 24 documents...
[DEBUG] HNSW index rebuilt
[DEBUG] Search results for "fruit": 3 items
[DEBUG]   - Watermelon is a large refreshing fruit...
[DEBUG]   - Banana is a yellow tropical fruit...
[DEBUG]   - Strawberry is a sweet red berry fruit...
```

---

## 교훈

1. **Lazy Build는 만능이 아니다**: 전역 상태와 DB 상태 간 동기화 문제 발생 가능
2. **명시적 호출이 안전하다**: 대량 문서 추가 후 `rebuildHnswIndex()` 명시 호출
3. **테스트 중요**: 성능 최적화 후 기능 검증 필수

---

## 권장 사용 패턴

```dart
// 1. DB 초기화
await initDb(dbPath: path);

// 2. 문서 일괄 추가
for (final doc in documents) {
  final emb = await EmbeddingService.embed(doc);
  await addDocument(dbPath: path, content: doc, embedding: emb);
}

// 3. HNSW 인덱스 구축 (필수!)
await rebuildHnswIndex(dbPath: path);

// 4. 검색
final results = await searchSimilar(dbPath: path, queryEmbedding: emb, topK: 3);
```
