# 하이브리드 RAG 아키텍처 가이드

iOS에서 Rust `ort` 크레이트의 `libonnxruntime.dylib` 로딩 문제를 해결하기 위해 채택한 하이브리드 아키텍처입니다.

---

## 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────┐
│                     Flutter UI (Dart)                        │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │ EmbeddingService │  │   main.dart   │  │    검색 결과 표시    │  │
│  └───────┬─────┘  └──────────────┘  └────────────────────┘  │
└──────────┼──────────────────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────────────────┐
│              Flutter onnxruntime 패키지                        │
│            (iOS: ObjC binding, Android: JNI)                 │
│                    ↓ ONNX 추론                                │
│              384차원 벡터 생성                                 │
└──────────────────────────────────────────────────────────────┘
           │
           ▼ (FFI)
┌──────────────────────────────────────────────────────────────┐
│                      Rust Core                                │
├────────────────────┬─────────────────────────────────────────┤
│    tokenizer.rs    │              simple_rag.rs              │
│  (HuggingFace      │         (rusqlite + ndarray)            │
│   tokenizers)      │                                         │
│  • tokenize()      │  • init_db()                            │
│  • decode_tokens() │  • add_document()                       │
│                    │  • search_similar()                     │
└────────────────────┴─────────────────────────────────────────┘
```

---

## 왜 하이브리드인가?

### 문제: Rust `ort` 크레이트 iOS 호환성

```
PanicException: An error occurred while attempting to load 
the ONNX Runtime binary at `libonnxruntime.dylib`
```

- `ort` 크레이트의 `load-dynamic` 피처는 런타임에 ONNX 라이브러리를 찾음
- iOS 시뮬레이터에서는 경로가 달라 `libonnxruntime.dylib`를 찾지 못함

### 해결: 역할 분리

| 레이어 | 담당 | 라이브러리 |
|--------|------|-----------|
| Dart | ONNX 추론 | `onnxruntime` 패키지 |
| Rust | 토큰화, DB | `tokenizers`, `rusqlite` |

---

## 1. Flutter 의존성

### `pubspec.yaml`

```yaml
dependencies:
  flutter:
    sdk: flutter
  path_provider: ^2.1.1
  onnxruntime: ^1.19.2

  # Rust 브릿지
  rust_lib_mobile_rag_engine:
    path: rust_builder

flutter:
  assets:
    - assets/tokenizer.json
    - assets/model.onnx
```

---

## 2. Dart EmbeddingService

### `lib/services/embedding_service.dart`

```dart
import 'dart:typed_data';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:mobile_rag_engine/src/rust/api/tokenizer.dart';

class EmbeddingService {
  static OrtSession? _session;
  
  /// ONNX 모델 초기화
  static Future<void> init(Uint8List modelBytes) async {
    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();
    _session = OrtSession.fromBuffer(modelBytes, sessionOptions);
  }
  
  /// 텍스트 → 384차원 임베딩
  static Future<List<double>> embed(String text) async {
    // 1. Rust 토크나이저로 토큰화 (FFI)
    final tokenIds = tokenize(text: text);
    
    // 2. 텐서 생성
    final seqLen = tokenIds.length;
    final inputIdsData = Int64List.fromList(
      tokenIds.map((e) => e.toInt()).toList()
    );
    final attentionMaskData = Int64List.fromList(
      List.filled(seqLen, 1)
    );
    final tokenTypeIdsData = Int64List.fromList(
      List.filled(seqLen, 0)
    );
    
    final shape = [1, seqLen];
    final inputs = {
      'input_ids': OrtValueTensor.createTensorWithDataList(inputIdsData, shape),
      'attention_mask': OrtValueTensor.createTensorWithDataList(attentionMaskData, shape),
      'token_type_ids': OrtValueTensor.createTensorWithDataList(tokenTypeIdsData, shape),
    };
    
    // 3. 추론 실행
    final outputs = await _session!.runAsync(OrtRunOptions(), inputs);
    
    // 4. Mean Pooling
    final outputData = outputs?[0]?.value as List;
    // ... (pooling 로직)
    
    return embedding;
  }
}
```

---

## 3. Rust 토크나이저

### `rust/src/api/tokenizer.rs`

Rust에서 HuggingFace `tokenizers` 크레이트 사용:

```rust
use tokenizers::Tokenizer;
use once_cell::sync::Lazy;
use std::sync::Mutex;

static TOKENIZER: Lazy<Mutex<Option<Tokenizer>>> = Lazy::new(|| Mutex::new(None));

pub fn init_tokenizer(tokenizer_path: String) -> Result<()> {
    let tokenizer = Tokenizer::from_file(&tokenizer_path)?;
    let mut global = TOKENIZER.lock().unwrap();
    *global = Some(tokenizer);
    Ok(())
}

#[frb(sync)]
pub fn tokenize(text: String) -> Result<Vec<u32>> {
    let guard = TOKENIZER.lock().unwrap();
    let tokenizer = guard.as_ref()?;
    let encoding = tokenizer.encode(text, false)?;
    Ok(encoding.get_ids().to_vec())
}
```

---

## 4. Rust 벡터 저장 및 검색

### `rust/src/api/simple_rag.rs`

```rust
use rusqlite::{params, Connection};
use ndarray::Array1;

pub fn add_document(db_path: String, content: String, embedding: Vec<f32>) -> Result<()> {
    let conn = Connection::open(&db_path)?;
    let embedding_bytes: Vec<u8> = embedding
        .iter()
        .flat_map(|f| f.to_ne_bytes().to_vec())
        .collect();
    
    conn.execute(
        "INSERT INTO docs (content, embedding) VALUES (?1, ?2)",
        params![content, embedding_bytes],
    )?;
    Ok(())
}

pub fn search_similar(db_path: String, query_embedding: Vec<f32>, top_k: u32) -> Result<Vec<String>> {
    // 코사인 유사도 계산 후 상위 K개 반환
    // ...
}
```

---

## 5. UTF-8 문자열 처리 주의사항

한글은 UTF-8에서 3바이트이므로 바이트 단위 슬라이싱 시 패닉 발생:

```rust
// ❌ 위험: 문자 중간에서 잘릴 수 있음
&content[..30]

// ✅ 안전: 문자 단위로 자름
fn truncate_str(s: &str, max_chars: usize) -> &str {
    match s.char_indices().nth(max_chars) {
        Some((idx, _)) => &s[..idx],
        None => s,
    }
}
truncate_str(&content, 15)
```

---

## 6. 초기화 순서

```dart
// main.dart _setup()
await initTokenizer(tokenizerPath: path);       // 1. Rust 토크나이저
await EmbeddingService.init(modelBytes);         // 2. Dart ONNX
await initDb(dbPath: dbPath);                    // 3. Rust SQLite
```

---

## 장단점 비교

### 하이브리드 (현재)

| 장점 | 단점 |
|------|------|
| iOS/Android 안정적 동작 | Rust↔Dart 간 데이터 전달 오버헤드 |
| Flutter 패키지가 네이티브 라이브러리 관리 | 두 레이어에서 로직 분산 |
| 플랫폼별 최적화 활용 가능 | |

### Rust 전용 (`ort` 크레이트)

| 장점 | 단점 |
|------|------|
| 단일 레이어에서 전체 로직 처리 | iOS에서 `libonnxruntime.dylib` 로딩 실패 |
| FFI 호출 최소화 | 크로스컴파일 복잡 |

---

## 검증 결과

**테스트 쿼리: "동물"**
- 1위: 강아지 ✅
- 2위: 원숭이 ✅
- 3위: 사과

MiniLM 모델이 "동물"과 의미적으로 유사한 "강아지", "원숭이"를 정확히 찾아냄!
