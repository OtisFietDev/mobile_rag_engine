# HuggingFace Tokenizers 통합 가이드

flutter_rust_bridge 프로젝트에 HuggingFace `tokenizers` 크레이트를 통합하는 단계별 가이드입니다.

---

## 사전 조건

- flutter_rust_bridge v2 프로젝트 설정 완료
- iOS 시뮬레이터/디바이스 빌드 테스트 완료

---

## 1. Rust 의존성 추가

### `rust/Cargo.toml`

```toml
[dependencies]
flutter_rust_bridge = "=2.11.1"
anyhow = "1.0"
once_cell = "1.21"

# HuggingFace Tokenizers
# default-features=false로 불필요한 의존성 제거
tokenizers = { version = "0.21", default-features = false, features = ["onig"] }
```

### 의존성 업데이트

```bash
cd rust && cargo update && cd ..
```

---

## 2. 토크나이저 모듈 구현

### `rust/src/api/tokenizer.rs`

```rust
use flutter_rust_bridge::frb;
use tokenizers::Tokenizer;
use anyhow::Result;
use std::sync::Mutex;
use once_cell::sync::Lazy;

// 전역 토크나이저 (앱 전체에서 재사용)
static TOKENIZER: Lazy<Mutex<Option<Tokenizer>>> = Lazy::new(|| Mutex::new(None));

/// tokenizer.json 파일로 초기화
pub fn init_tokenizer(tokenizer_path: String) -> Result<()> {
    let tokenizer = Tokenizer::from_file(&tokenizer_path)
        .map_err(|e| anyhow::anyhow!("Failed to load tokenizer: {}", e))?;
    
    let mut global = TOKENIZER.lock().unwrap();
    *global = Some(tokenizer);
    Ok(())
}

/// 텍스트 → 토큰 ID
#[frb(sync)]
pub fn tokenize(text: String) -> Result<Vec<u32>> {
    let guard = TOKENIZER.lock().unwrap();
    let tokenizer = guard.as_ref()
        .ok_or_else(|| anyhow::anyhow!("Tokenizer not initialized"))?;
    
    let encoding = tokenizer.encode(text, false)
        .map_err(|e| anyhow::anyhow!("Tokenization failed: {}", e))?;
    
    Ok(encoding.get_ids().to_vec())
}

/// 토큰 ID → 텍스트
#[frb(sync)]
pub fn decode_tokens(token_ids: Vec<u32>) -> Result<String> {
    let guard = TOKENIZER.lock().unwrap();
    let tokenizer = guard.as_ref()
        .ok_or_else(|| anyhow::anyhow!("Tokenizer not initialized"))?;
    
    let decoded = tokenizer.decode(&token_ids, true)
        .map_err(|e| anyhow::anyhow!("Decoding failed: {}", e))?;
    
    Ok(decoded)
}

/// Vocab 크기
#[frb(sync)]
pub fn get_vocab_size() -> Result<u32> {
    let guard = TOKENIZER.lock().unwrap();
    let tokenizer = guard.as_ref()
        .ok_or_else(|| anyhow::anyhow!("Tokenizer not initialized"))?;
    
    Ok(tokenizer.get_vocab_size(true) as u32)
}
```

### `rust/src/api/mod.rs`

```rust
pub mod simple;
pub(crate) mod simple_rag;
pub mod tokenizer;  // 추가
```

---

## 3. tokenizer.json 다운로드

HuggingFace에서 MiniLM 토크나이저 다운로드:

```bash
wget https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/tokenizer.json
mv tokenizer.json assets/
```

---

## 4. Flutter 설정

### `pubspec.yaml` - assets 선언

```yaml
flutter:
  assets:
    - assets/
```

---

## 5. Dart에서 사용

### Asset → 파일 시스템 복사 (필수)

Rust는 파일 시스템 경로가 필요하므로 asset을 앱 문서 디렉토리로 복사:

```dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

Future<String> _copyAssetToFile(String assetPath) async {
  final dir = await getApplicationDocumentsDirectory();
  final filePath = "${dir.path}/tokenizer.json";
  final file = File(filePath);
  
  if (!await file.exists()) {
    final data = await rootBundle.load(assetPath);
    await file.writeAsBytes(data.buffer.asUint8List());
  }
  return filePath;
}
```

### 초기화 및 사용

```dart
import 'package:mobile_rag_engine/src/rust/api/tokenizer.dart';

// 1. 초기화
final path = await _copyAssetToFile('assets/tokenizer.json');
await initTokenizer(tokenizerPath: path);

// 2. 토큰화
final tokens = tokenize(text: "Hello World");
print(tokens);  // [101, 7592, 2088, 102]

// 3. 디코딩
final text = decodeTokens(tokenIds: tokens);
print(text);  // "hello world"

// 4. Vocab 크기
final vocab = getVocabSize();
print(vocab);  // 30522
```

---

## 6. 빌드 명령어

```bash
# 코드 생성
flutter_rust_bridge_codegen generate

# 실행
flutter run
```

---

## 트러블슈팅

### 오류: `use of unresolved crate once_cell`

```toml
# Cargo.toml에 추가
once_cell = "1.21"
```

### 오류: `Tokenizer not initialized`

`init_tokenizer()`를 먼저 호출했는지 확인.

### 오류: Asset 파일을 찾을 수 없음

1. `pubspec.yaml`에 assets 선언 확인
2. `flutter clean && flutter pub get` 실행

---

## MiniLM 토크나이저 정보

| 항목 | 값 |
|------|-----|
| 모델 | all-MiniLM-L6-v2 |
| Vocab Size | 30,522 tokens |
| 알고리즘 | WordPiece |
| 최대 길이 | 256 tokens |
| 출처 | sentence-transformers |
