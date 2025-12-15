# Flutter Rust Bridge + SQLite 벡터 저장소 구현 가이드

flutter_rust_bridge 프로젝트에 SQLite 기반 로컬 벡터 저장소를 추가하는 단계별 가이드입니다.

---

## 사전 조건

- flutter_rust_bridge v2 프로젝트가 iOS/Android에서 정상 빌드되는 상태
- 기본 Rust ↔ Dart FFI 호출이 동작하는 상태

---

## 1. Flutter 의존성 추가

앱 내부 저장소 경로를 얻기 위해 `path_provider` 추가:

```bash
flutter pub add path_provider
```

---

## 2. Rust 의존성 수정

### `rust/Cargo.toml`

```toml
[dependencies]
flutter_rust_bridge = "2.11.1"
anyhow = "1.0"
ndarray = "0.17"

# ⚠️ 핵심: bundled 피처 필수!
# iOS/Android 시스템 SQLite에 의존하지 않고 직접 포함
rusqlite = { version = "0.32", features = ["bundled"] }
```

### Cargo.lock 갱신

의존성 버전 충돌 방지를 위해 반드시 실행:

```bash
cd rust && cargo update && cd ..
```

---

## 3. Rust 함수 구현

### `rust/src/api/simple_rag.rs`

```rust
use flutter_rust_bridge::frb;
use rusqlite::{params, Connection};
use ndarray::Array1;

/// DB 초기화: docs 테이블 생성
pub fn init_db(db_path: String) -> anyhow::Result<()> {
    let conn = Connection::open(&db_path)?;
    
    conn.execute(
        "CREATE TABLE IF NOT EXISTS docs (
            id INTEGER PRIMARY KEY,
            content TEXT NOT NULL,
            embedding BLOB NOT NULL
        )",
        [],
    )?;
    
    Ok(())
}

/// 문서와 벡터 추가
pub fn add_document(db_path: String, content: String, embedding: Vec<f32>) -> anyhow::Result<()> {
    let conn = Connection::open(&db_path)?;

    // Vec<f32> -> BLOB 변환
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

/// 유사도 기반 검색 (상위 K개 반환)
/// ⚠️ top_k는 u32 사용 (usize는 Dart에서 BigInt로 매핑됨)
pub fn search_similar(db_path: String, query_embedding: Vec<f32>, top_k: u32) -> anyhow::Result<Vec<String>> {
    let conn = Connection::open(&db_path)?;
    let mut stmt = conn.prepare("SELECT content, embedding FROM docs")?;
    
    let query_vec = Array1::from(query_embedding);
    let query_norm = query_vec.mapv(|x| x * x).sum().sqrt();

    let mut candidates: Vec<(f64, String)> = Vec::new();

    let rows = stmt.query_map([], |row| {
        let content: String = row.get(0)?;
        let embedding_blob: Vec<u8> = row.get(1)?;
        Ok((content, embedding_blob))
    })?;

    for row in rows {
        let (content, embedding_blob) = row?;
        
        // BLOB -> Vec<f32> 복원
        let embedding_vec: Vec<f32> = embedding_blob
            .chunks(4)
            .map(|chunk| f32::from_ne_bytes(chunk.try_into().unwrap()))
            .collect();
            
        // 코사인 유사도
        let target_vec = Array1::from(embedding_vec);
        let target_norm = target_vec.mapv(|x| x * x).sum().sqrt();
        let dot_product = query_vec.dot(&target_vec);
        
        let similarity = if query_norm == 0.0 || target_norm == 0.0 {
            0.0
        } else {
            dot_product / (query_norm * target_norm)
        };

        candidates.push((similarity as f64, content));
    }

    candidates.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap());
    let result = candidates.into_iter().take(top_k as usize).map(|(_, c)| c).collect();
    
    Ok(result)
}
```

> ⚠️ **타입 주의**: `usize` 대신 `u32` 사용. flutter_rust_bridge가 `usize`를 Dart의 `BigInt`로 매핑하기 때문.

---

## 4. 코드 생성

```bash
flutter_rust_bridge_codegen generate
```

---

## 5. Dart UI 구현

### `lib/main.dart`

```dart
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mobile_rag_engine/src/rust/api/simple_rag.dart';
import 'package:mobile_rag_engine/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = "준비됨";
  String _dbPath = "";

  @override
  void initState() {
    super.initState();
    _setupDb();
  }

  Future<void> _setupDb() async {
    final dir = await getApplicationDocumentsDirectory();
    _dbPath = "${dir.path}/rag_db.sqlite";
    await initDb(dbPath: _dbPath);
    setState(() => _status = "DB 준비완료");
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Local RAG Engine')),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            
            ElevatedButton(
              onPressed: () async {
                await addDocument(dbPath: _dbPath, content: "사과는 맛있다.", embedding: [1.0, 0.0, 0.0]);
                await addDocument(dbPath: _dbPath, content: "테슬라는 빠르다.", embedding: [0.0, 0.0, 1.0]);
                setState(() => _status = "데이터 저장 완료!");
              },
              child: const Text('샘플 데이터 저장'),
            ),
            
            ElevatedButton(
              onPressed: () async {
                final results = await searchSimilar(
                  dbPath: _dbPath, 
                  queryEmbedding: [1.0, 0.0, 0.0], 
                  topK: 1
                );
                setState(() => _status = "검색 결과: $results");
              },
              child: const Text('검색 실행'),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 6. 빌드 및 실행

```bash
# iOS Pod 재설치
cd ios && pod install && cd ..

# 실행
flutter run
```

---

## 7. 테스트 체크리스트

- [ ] "샘플 데이터 저장" 클릭 → "데이터 저장 완료!" 표시
- [ ] "검색 실행" 클릭 → `[사과는 맛있다.]` 표시
- [ ] 앱 완전 종료 후 재실행 → 검색해도 데이터 유지됨

---

## 트러블슈팅

### 오류: `failed to select a version for cc`

```bash
cd rust && cargo update && cd ..
flutter_rust_bridge_codegen generate
```

### 오류: `The argument type 'int' can't be assigned to BigInt`

Rust 함수의 `usize` 파라미터를 `u32`로 변경 후 재생성.

### 오류: `rusqlite` iOS 빌드 실패

`Cargo.toml`에서 `bundled` 피처가 누락되었는지 확인:
```toml
rusqlite = { version = "0.32", features = ["bundled"] }
```
