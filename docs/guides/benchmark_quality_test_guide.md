# 벤치마크 & 품질 테스트 가이드

본 프로젝트에서 개발한 성능 및 품질 테스트 도구에 대한 가이드입니다.

---

## 1. 성능 벤치마크

### 위치
- 서비스: `lib/services/benchmark_service.dart`
- UI: `lib/screens/benchmark_screen.dart`

### 측정 항목

| 항목 | 설명 | 예상 시간 |
|------|------|----------|
| 토큰화 (7/41/120자) | 텍스트 → 토큰 ID | 1-11ms |
| 임베딩 (7/41/120자) | 텍스트 → 384차원 벡터 | 23-33ms |
| 검색 (100문서) | 코사인 유사도 검색 | ~5ms |

### 사용법

```dart
final results = await BenchmarkService.runFullBenchmark(
  dbPath: dbPath,
  onProgress: (msg) => print(msg),
);

for (final r in results) {
  print('${r.name}: avg=${r.avgMs}ms');
}
```

---

## 2. 검색 품질 테스트

### 위치
- 서비스: `lib/services/quality_test_service.dart`
- UI: `lib/screens/quality_test_screen.dart`

### 테스트 데이터셋

24개 문서 (카테고리별 6개):
- **Fruits**: Apple, Banana, Orange, Grape, Watermelon, Strawberry
- **Animals**: Dog, Cat, Rabbit, Monkey, Elephant, Penguin
- **Tech**: Tesla, Apple, Google, Samsung, Microsoft, Amazon
- **Food**: Kimchi, Pizza, Sushi, Hamburger, Pasta, Ramen

### 테스트 쿼리 (10개)

```dart
static final List<TestCase> testCases = [
  TestCase(query: "fruit", ...),
  TestCase(query: "red fruit", ...),
  TestCase(query: "pet animal", ...),
  TestCase(query: "wild animal", ...),
  TestCase(query: "tech company", ...),
  TestCase(query: "phone company", ...),
  TestCase(query: "Italian food", ...),
  TestCase(query: "Asian food", ...),
  TestCase(query: "noodle", ...),
  TestCase(query: "tropical fruit", ...),
];
```

### 측정 지표

| 지표 | 설명 | 목표 |
|------|------|------|
| **통과율** | 1개 이상 관련 문서 반환 비율 | ≥ 90% |
| **Recall@3** | 상위 3개 중 관련 문서 비율 | ≥ 70% |
| **Precision** | 반환된 문서 중 관련 문서 비율 | ≥ 60% |

### 최종 결과 (2024-12-07)

| 지표 | 결과 |
|------|------|
| 통과율 | **100%** ⭐ |
| Recall@3 | **93.3%** |
| Precision | **76.7%** |

---

## 3. 디버그 모드

### 임베딩 디버그

```dart
// 활성화
EmbeddingService.debugMode = true;

// 출력 예시
// [DEBUG] Text: "fruit"
// [DEBUG] Token IDs: [101, 5909, 102] (length: 3)
// [DEBUG] Output shape: [1, 3, 384]
// [DEBUG] Embedding (first 5): [-0.028, 0.166, ...]
```

### 검색 디버그 (Rust)

Rust 코드에 `log` 크레이트로 로깅 추가됨:
```
[search] 검색 시작, query 차원: 384, top_k: 3
[search] 총 24개 문서 검색됨
[search] 결과: 유사도=0.8234, content='Watermelon is...'
```

---

## 4. 테스트 커스터마이징

### 문서 추가

```dart
static final List<String> testDocuments = [
  "Apple is a delicious red fruit",
  // 새 문서 추가
  "Mango is a tropical fruit from Asia",
];
```

### 테스트 케이스 추가

```dart
static final List<TestCase> testCases = [
  // 기존 케이스...
  TestCase(
    query: "mango",
    relevantDocs: ["Mango"],
    category: "Fruits",
  ),
];
```

---

## 5. 결과 해석

### 좋은 결과
- 통과율 100%: 모든 쿼리에서 관련 문서 반환
- Recall ≥ 80%: 대부분의 관련 문서가 상위에 랭크
- Precision ≥ 60%: 반환된 문서 중 절반 이상이 관련

### 나쁜 결과 원인
1. **토크나이저 문제**: special tokens 누락, 패딩
2. **임베딩 모델 한계**: 한국어 최적화 부족
3. **테스트 데이터 품질**: 쿼리-문서 간 어휘 불일치
