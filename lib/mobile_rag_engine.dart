/// Mobile RAG Engine
///
/// A high-performance, on-device RAG (Retrieval-Augmented Generation) engine
/// for Flutter. Run semantic search completely offline on iOS and Android.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:mobile_rag_engine/mobile_rag_engine.dart';
///
/// // Initialize
/// await initTokenizer(tokenizerPath: 'path/to/tokenizer.json');
/// await EmbeddingService.init(modelBytes);
/// await initDb(dbPath: 'path/to/rag.db');
///
/// // Add documents
/// final embedding = await EmbeddingService.embed("Your text");
/// await addDocument(dbPath: dbPath, content: "Your text", embedding: embedding);
///
/// // Search
/// final queryEmb = await EmbeddingService.embed("query");
/// final results = await searchSimilar(dbPath: dbPath, queryEmbedding: queryEmb, topK: 5);
/// ```
library mobile_rag_engine;

// Core RAG functions
export 'src/rust/api/simple_rag.dart';

// Tokenizer functions
export 'src/rust/api/tokenizer.dart';

// Embedding service
export 'services/embedding_service.dart';

// Rust library initialization
export 'src/rust/frb_generated.dart' show RustLib;
