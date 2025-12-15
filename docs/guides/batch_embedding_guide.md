# 배치 임베딩 (Batch Embedding) 구현 가이드

## 개요

여러 텍스트를 효율적으로 임베딩하기 위한 배치 처리 API 구현 가이드입니다.

---

## 도입 배경

### 기존 방식: 단일 임베딩

```dart
// 10개 문서를 하나씩 처리
for (final doc in documents) {
  final emb = await EmbeddingService.embed(doc);
  // 처리...
}
```

**문제점:**
- 진행 상황 추적 어려움
- API 사용성 떨어짐

---

## 구현 과정

### 1단계: 병렬 처리 시도

**최초 구현 (병렬 처리):**
```dart
static Future<List<List<double>>> embedBatch(
  List<String> texts, {
  int concurrency = 4,  // 동시 처리 수
}) async {
  // 청크 단위로 병렬 처리
  for (var i = 0; i < texts.length; i += concurrency) {
    final futures = chunk.map((text) => embed(text));
    await Future.wait(futures);  // 병렬 실행
  }
}
```

### 2단계: ONNX 세션 동시성 문제 발견

**에러 발생:**
```
오류: code=2, message=the ort_value must contain a 
constructed tensor or sparse tensor
```

**원인:** ONNX Runtime 세션이 thread-safe하지 않음
- 동시에 여러 추론 요청 불가
- Flutter의 `Future.wait`로 병렬 실행 시 충돌

### 3단계: 순차 처리로 변경

**최종 구현:**
```dart
static Future<List<List<double>>> embedBatch(
  List<String> texts, {
  int concurrency = 1,  // ONNX 세션 제한으로 순차 처리
  void Function(int completed, int total)? onProgress,
}) async {
  if (_session == null) {
    throw Exception("EmbeddingService not initialized");
  }
  
  if (texts.isEmpty) return [];
  
  final results = <List<double>>[];
  
  // 순차 처리 (ONNX 세션이 thread-safe하지 않음)
  for (var i = 0; i < texts.length; i++) {
    final embedding = await embed(texts[i]);
    results.add(embedding);
    onProgress?.call(i + 1, texts.length);
  }
  
  return results;
}
```

---

## API 사용법

### 기본 사용

```dart
final texts = ["사과는 맛있다", "바나나는 노랗다", "오렌지는 둥글다"];
final embeddings = await EmbeddingService.embedBatch(texts);

// embeddings[0] = "사과는 맛있다"의 384차원 벡터
// embeddings[1] = "바나나는 노랗다"의 384차원 벡터
// ...
```

### 진행 상황 추적

```dart
final embeddings = await EmbeddingService.embedBatch(
  texts,
  onProgress: (completed, total) {
    print("Processing: $completed / $total");
    // 또는 UI 업데이트
    setState(() => _progress = completed / total);
  },
);
```

---

## 벤치마크 결과

### 테스트 환경
- 10개 문서 (다양한 길이)
- iPhone 15 Pro Max 시뮬레이터

### 결과

| 방식 | 시간 | 비고 |
|------|------|------|
| 순차 임베딩 (for-loop) | 77.1ms | 기존 방식 |
| 배치 임베딩 (embedBatch) | 75.9ms | 새 API |

**분석:**
- 시간 차이 거의 없음 (둘 다 순차 처리)
- 배치 API의 장점은 **사용 편의성**과 **진행 상황 추적**

---

## 수정된 파일

| 파일 | 변경 내용 |
|------|----------|
| `lib/services/embedding_service.dart` | `embedBatch()` 메서드 추가 |
| `lib/services/benchmark_service.dart` | 배치 임베딩 벤치마크 추가 |

---

## 제한 사항

### ONNX 세션 동시성
```
⚠️ ONNX Runtime 세션은 동시 접근을 지원하지 않습니다.
   embedBatch()는 내부적으로 순차 처리됩니다.
```

### 향후 개선 가능성

1. **True Batch Inference**: 여러 시퀀스를 하나의 텐서로 패딩 후 한 번에 추론
   - 장점: ONNX 호출 1회로 처리
   - 단점: 복잡한 패딩/언패딩 로직 필요

2. **Isolate 활용**: 별도 Isolate에서 ONNX 세션 실행
   - 장점: UI 블로킹 방지
   - 단점: ONNX 세션이 isolate 간 공유 불가

---

## 관련 문서

- [HNSW 도입 가이드](./hnsw_integration_guide.md)
- [하이브리드 RAG 아키텍처](./hybrid_rag_architecture_guide.md)
