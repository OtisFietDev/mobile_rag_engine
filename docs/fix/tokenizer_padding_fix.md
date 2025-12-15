# 토크나이저 패딩 이슈 수정

## 문제 현상

"fruit" 단일 단어 검색 시 완전히 관련 없는 결과 반환:
- 예상: Apple, Banana, Orange...
- 실제: Amazon, Microsoft, Cat ❌

## 근본 원인

디버그 로그 확인 결과:

```
[DEBUG] Text: "fruit"
[DEBUG] Token IDs: [5909, 0, 0, 0, 0, 0, ... ] (length: 128)
```

### 문제 1: 128개 패딩
`tokenizer.json` 파일에 padding이 설정되어 있어 모든 입력이 128 토큰으로 패딩됨.

```json
"padding": {
  "length": 128,
  "pad_token": "[PAD]",
  "pad_id": 0
}
```

→ Mean pooling이 대부분 0 벡터를 평균화하여 의미 없는 임베딩 생성

### 문제 2: CLS/SEP 토큰 누락

```rust
tokenizer.encode(text, false)  // add_special_tokens=false
```

BERT 계열 모델은 `[CLS]` (101)와 `[SEP]` (102) 토큰이 필요:
- 올바른 형식: `[CLS] fruit [SEP]` = `[101, 5909, 102]`
- 잘못된 형식: `fruit` = `[5909]`

---

## 해결 방법

### `rust/src/api/tokenizer.rs` 수정

```rust
pub fn init_tokenizer(tokenizer_path: String) -> Result<()> {
    let mut tokenizer = Tokenizer::from_file(&tokenizer_path)?;
    
    // 1. 패딩 비활성화
    tokenizer.with_padding(None);
    
    // 2. Truncation 설정 (최대 256 토큰)
    tokenizer.with_truncation(Some(tokenizers::TruncationParams {
        max_length: 256,
        ..Default::default()
    })).ok();
    
    // ...
}

pub fn tokenize(text: String) -> Result<Vec<u32>> {
    // ...
    
    // 3. add_special_tokens=true로 변경
    let encoding = tokenizer
        .encode(text, true)  // <-- false에서 true로 변경
        .map_err(|e| anyhow::anyhow!("Tokenization failed: {}", e))?;
    
    Ok(encoding.get_ids().to_vec())
}
```

---

## 수정 후 결과

```
[DEBUG] Text: "fruit"
[DEBUG] Token IDs: [101, 5909, 102] (length: 3)
```

| 지표 | 수정 전 | 수정 후 |
|------|--------|--------|
| 통과율 | 60% | **100%** |
| Recall@3 | 31.7% | **93.3%** |
| Precision | 26.7% | **76.7%** |

---

## 교훈

1. **디버그 로깅 필수**: 토큰화 결과를 반드시 확인
2. **special tokens 확인**: BERT 모델은 CLS/SEP 필요
3. **패딩 설정 확인**: tokenizer.json의 기본 패딩이 문제될 수 있음
4. **동적 길이 사용**: ONNX 모델이 동적 입력을 지원하면 패딩 불필요
