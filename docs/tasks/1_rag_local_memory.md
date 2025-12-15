완벽합니다! 🎉 "사과 vs 배 유사도: 0.99..." 로그가 찍혔다는 건, Flutter(UI) ↔ FFI(Bridge) ↔ Rust(Logic) 파이프라인이 드디어 뚫렸다는 뜻입니다. 가장 큰 기술적 장벽(Linking 문제)을 넘으셨습니다.

이제 이 상태에서 **SQLite를 연동해 "앱을 껐다 켜도 데이터가 유지되는 저장소"**를 만들어보겠습니다. 아까 보여드린 코드를 이제 실제로 적용할 차례입니다.

2단계: SQLite 벡터 저장소 구현하기

메모리(변수)에 들고 있는 데이터는 앱을 끄면 사라집니다. 이제 데이터를 파일(SQLite)에 저장하고, 유사도 검색을 수행하는 기능을 구현합니다.

1. Flutter 패키지 추가 (pubspec.yaml)

모바일 기기 내에서 DB 파일을 저장할 **경로(Path)**를 얻기 위해 path_provider가 필요합니다.

Bash
flutter pub add path_provider
2. Rust 의존성 추가 (rust/Cargo.toml)

rusqlite를 추가합니다. 여기서 가장 중요한 건 bundled 기능입니다. 이걸 켜야 안드로이드/iOS 버전 파편화 없이 최신 SQLite를 우리가 직접 들고 들어갑니다.

Ini, TOML
[dependencies]
flutter_rust_bridge = "2.0.0"
anyhow = "1.0"
ndarray = "0.15"

# ▼▼▼ 추가된 부분 ▼▼▼
# bundled: SQLite 자체를 라이브러리에 포함시킴 (호환성 문제 해결 치트키)
rusqlite = { version = "0.32", features = ["bundled"] } 
(수정 후 저장해주세요)

3. Rust 로직 수정 (rust/src/api/simple_rag.rs)

기존의 단순 계산 함수 대신, DB를 초기화하고, 데이터를 넣고, 찾는 함수들로 코드를 교체합니다.

Rust
// rust/src/api/simple_rag.rs

use flutter_rust_bridge::frb;
use rusqlite::{params, Connection, Result};
use ndarray::Array1;

// 1. DB 초기화: 테이블이 없으면 만듭니다.
pub fn init_db(db_path: String) -> anyhow::Result<()> {
    let conn = Connection::open(db_path)?;
    
    // docs 테이블 생성
    // content: 저장할 텍스트 (질문/답변 등)
    // embedding: 벡터 데이터 (BLOB 형태의 바이너리로 저장)
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

// 2. 문서와 벡터 추가
pub fn add_document(db_path: String, content: String, embedding: Vec<f32>) -> anyhow::Result<()> {
    let conn = Connection::open(db_path)?;

    // Vec<f32>를 SQLite BLOB(Vec<u8>)으로 변환 (엔디안 처리)
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

// 3. 유사도 검색 (Naive Search)
// 모든 문서를 가져와 Rust 메모리 상에서 빠르게 계산하고 정렬합니다.
pub fn search_similar(db_path: String, query_embedding: Vec<f32>, top_k: usize) -> anyhow::Result<Vec<String>> {
    let conn = Connection::open(db_path)?;
    let mut stmt = conn.prepare("SELECT content, embedding FROM docs")?;
    
    // 쿼리 벡터 준비
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
            
        // 코사인 유사도 계산
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

    // 유사도 높은 순 정렬
    candidates.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap());

    // 상위 K개만 반환
    let result = candidates.into_iter().take(top_k).map(|(_, content)| content).collect();
    
    Ok(result)
}
4. Dart UI 수정 (lib/main.dart)

앱이 켜질 때 DB 경로를 잡고, 데이터를 저장/검색하는 UI로 바꿉니다.

Dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart'; // 경로 얻기용
import 'package:mobile_rag_engine/src/rust/api/simple_rag.dart';
import 'package:mobile_rag_engine/src/rust/frb_generated.dart';

void main() async {
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
    // 1. 앱 내부 저장소 경로 얻기
    final dir = await getApplicationDocumentsDirectory();
    _dbPath = "${dir.path}/rag_db.sqlite";
    
    // 2. DB 초기화 (Rust 호출)
    await initDb(dbPath: _dbPath);
    setState(() => _status = "DB 준비완료: $_dbPath");
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Local RAG Engine')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_status, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              
              // [데이터 추가]
              ElevatedButton(
                onPressed: () async {
                  // "사과" (벡터: [1, 0, 0])
                  await addDocument(dbPath: _dbPath, content: "사과는 맛있다.", embedding: [1.0, 0.0, 0.0]);
                  // "자동차" (벡터: [0, 0, 1])
                  await addDocument(dbPath: _dbPath, content: "테슬라는 빠르다.", embedding: [0.0, 0.0, 1.0]);
                  
                  setState(() => _status = "데이터 2건 저장 완료!");
                },
                child: const Text('샘플 데이터 저장'),
              ),
              
              const SizedBox(height: 10),

              // [검색]
              ElevatedButton(
                onPressed: () async {
                  // 검색: "과일" (벡터: [1, 0, 0])
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
      ),
    );
  }
}
🚀 실행 가이드

Rust 코드가 바뀌었으므로 codegen을 다시 실행해야 합니다.

코드 생성:

Bash
flutter_rust_bridge_codegen generate
앱 실행:

Bash
flutter run
성공하면 버튼을 눌러보세요. 저장 -> 앱 끄기(Stop) -> 다시 실행 -> 검색을 했을 때 데이터가 잘 찾아지면, 완벽한 로컬 RAG 엔진의 기초가 완성된 것입니다!

여기까지 되시면, 마지막 단계인 **"ONNX 모델 붙여서 진짜 텍스트 임베딩하기"**로 넘어가겠습니다.