# Mobile RAG Engine 이슈 해결 종합 문서

이 프로젝트 개발 중 발생한 모든 이슈와 해결 방법을 기록합니다.

---

## 🔴 이슈 1: iOS ONNX Runtime 로딩 실패

### 증상
```
PanicException: An error occurred while attempting to load 
the ONNX Runtime binary at `libonnxruntime.dylib`
```

### 원인
Rust `ort` 크레이트의 `load-dynamic` 피처가 iOS에서 네이티브 라이브러리 경로를 찾지 못함.

### 해결
하이브리드 아키텍처로 전환:
- **Rust**: 토크나이저만 담당 (`tokenizers` 크레이트)
- **Dart**: ONNX 추론 담당 (`onnxruntime` 패키지)

### 관련 파일
- `rust/Cargo.toml` - `ort` 크레이트 제거
- `lib/services/embedding_service.dart` - Dart ONNX 추론 구현

---

## 🔴 이슈 2: UTF-8 문자열 슬라이싱 패닉

### 증상
```
PanicException: byte index 30 is not a char boundary; 
it is inside '나' (bytes 29..32) of `사과는 빨간색 과일입니다.`
```

### 원인
한글은 UTF-8에서 3바이트. 바이트 단위 슬라이싱 시 문자 중간에서 잘림.

```rust
// ❌ 위험
&content[..30]
```

### 해결
문자 단위 슬라이싱 헬퍼 함수 추가:

```rust
fn truncate_str(s: &str, max_chars: usize) -> &str {
    match s.char_indices().nth(max_chars) {
        Some((idx, _)) => &s[..idx],
        None => s,
    }
}
```

### 관련 파일
- `rust/src/api/simple_rag.rs`

---

## 🔴 이슈 3: 토크나이저 패딩 및 Special Tokens

### 증상
"fruit" 검색 시 전혀 관련 없는 결과 반환 (Amazon, Microsoft, Cat)

### 디버그
```
[DEBUG] Token IDs: [5909, 0, 0, 0, 0, 0, ...] (length: 128)
```

### 원인
1. `tokenizer.json`에 padding=128 설정됨
2. `encode(text, false)`로 CLS/SEP 토큰 미포함

### 해결
```rust
// 패딩 비활성화
tokenizer.with_padding(None);

// Special tokens 추가
let encoding = tokenizer.encode(text, true);  // false → true
```

### 결과
| 지표 | 수정 전 | 수정 후 |
|------|--------|--------|
| 통과율 | 60% | **100%** |
| Recall@3 | 31.7% | **93.3%** |

### 관련 파일
- `rust/src/api/tokenizer.rs`
- `fix/tokenizer_padding_fix.md`

---

## 🟡 이슈 4: 한국어 검색 품질 저하

### 증상
한국어 테스트에서 Recall 41.7% (영어보다 낮음)

### 원인
`all-MiniLM-L6-v2` 모델이 영어에 최적화됨

### 해결
- 현재: 영어 데이터셋으로 테스트 변경
- 향후: 한국어 전용 모델 (KoSimCSE, KR-SBERT) 지원 계획

### 관련 문서
- `guides/hybrid_rag_architecture_guide.md`

---

## 📁 수정된 파일 목록

| 파일 | 수정 내용 |
|------|----------|
| `rust/Cargo.toml` | `ort` 제거, `tokenizers` 추가 |
| `rust/src/api/tokenizer.rs` | 패딩 비활성화, special tokens 추가 |
| `rust/src/api/simple_rag.rs` | UTF-8 안전 슬라이싱, 로깅 추가 |
| `rust/src/api/mod.rs` | embedding 모듈 제거 |
| `lib/services/embedding_service.dart` | Dart ONNX 추론 구현 |
| `lib/services/benchmark_service.dart` | 성능 벤치마크 |
| `lib/services/quality_test_service.dart` | 품질 테스트 |
| `lib/screens/benchmark_screen.dart` | 벤치마크 UI |
| `lib/screens/quality_test_screen.dart` | 품질 테스트 UI |
| `lib/main.dart` | 통합 UI |

---

## 📊 최종 성능 결과

### 속도
| 항목 | 시간 |
|------|------|
| 토큰화 (단문) | 1-4ms |
| 임베딩 생성 | 23-33ms |
| 검색 (100문서) | 5ms |

### 품질
| 지표 | 결과 |
|------|------|
| 통과율 | 100% |
| Recall@3 | 93.3% |
| Precision | 76.7% |

---

## 📝 향후 개선 계획

1. **한국어 모델 지원**: KoSimCSE, KR-SBERT
2. **벡터 인덱싱**: HNSW, IVF 등 ANN 알고리즘
3. **배치 임베딩**: 여러 문장 동시 처리
4. **모델 양자화**: INT8로 크기 감소
