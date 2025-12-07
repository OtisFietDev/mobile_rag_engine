# Mobile RAG Engine

[![pub package](https://img.shields.io/pub/v/mobile_rag_engine.svg)](https://pub.dev/packages/mobile_rag_engine)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A high-performance, on-device Retrieval-Augmented Generation (RAG) engine for Flutter. Run semantic search completely offline on iOS and Android.

## Features

- 🚀 **High Performance** - HNSW vector indexing for O(log n) search
- 📱 **Fully Offline** - No internet required after initial setup
- 🔒 **Privacy First** - All data stays on device
- 🌍 **Cross-Platform** - iOS and Android support
- ⚡ **Rust-Powered** - Native performance via Flutter Rust Bridge
- 🔍 **Semantic Search** - Find documents by meaning, not just keywords
- 📊 **Deduplication** - SHA256 content hashing prevents duplicates

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter (Dart)                       │
│  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │ EmbeddingService│  │   Your Application          │  │
│  │ (ONNX Runtime)  │  │   - addDocument()           │  │
│  └────────┬────────┘  │   - searchSimilar()         │  │
│           │           └─────────────────────────────┘  │
├───────────┼─────────────────────────────────────────────┤
│           │           Rust (via FFI)                    │
│  ┌────────▼────────┐  ┌─────────────────────────────┐  │
│  │   Tokenizer     │  │   SQLite + HNSW Index       │  │
│  │  (HuggingFace)  │  │   - Vector Storage          │  │
│  └─────────────────┘  │   - Fast ANN Search         │  │
│                       └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  mobile_rag_engine: ^1.0.0
```

### Requirements

- Flutter 3.9+
- iOS 13.0+ / Android API 21+
- ONNX embedding model (e.g., all-MiniLM-L6-v2)
- Tokenizer JSON file

## Quick Start

### 1. Initialize

```dart
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

// Initialize tokenizer
await initTokenizer(tokenizerPath: 'path/to/tokenizer.json');

// Initialize ONNX model
final modelBytes = await rootBundle.load('assets/model.onnx');
await EmbeddingService.init(modelBytes.buffer.asUint8List());

// Initialize database
await initDb(dbPath: 'path/to/rag.db');
```

### 2. Add Documents

```dart
// Single document
final embedding = await EmbeddingService.embed("Your document text");
final result = await addDocument(
  dbPath: dbPath,
  content: "Your document text",
  embedding: embedding,
);

if (result.isDuplicate) {
  print("Document already exists!");
}

// Batch documents
final embeddings = await EmbeddingService.embedBatch(
  ["Doc 1", "Doc 2", "Doc 3"],
  onProgress: (done, total) => print("$done / $total"),
);
```

### 3. Search

```dart
final queryEmbedding = await EmbeddingService.embed("search query");

final results = await searchSimilar(
  dbPath: dbPath,
  queryEmbedding: queryEmbedding,
  topK: 5,
);

for (final doc in results) {
  print(doc);
}
```

### 4. Rebuild Index (after bulk inserts)

```dart
// Call after adding multiple documents
await rebuildHnswIndex(dbPath: dbPath);
```

## API Reference

### Core Functions

| Function | Description |
|----------|-------------|
| `initDb(dbPath)` | Initialize SQLite database |
| `addDocument(dbPath, content, embedding)` | Add document with deduplication |
| `searchSimilar(dbPath, queryEmbedding, topK)` | Semantic search |
| `rebuildHnswIndex(dbPath)` | Rebuild HNSW index |
| `getDocumentCount(dbPath)` | Get total document count |
| `clearAllDocuments(dbPath)` | Delete all documents |

### EmbeddingService

| Method | Description |
|--------|-------------|
| `init(modelBytes)` | Load ONNX model |
| `embed(text)` | Generate 384-dim embedding |
| `embedBatch(texts, onProgress)` | Batch embedding |
| `dispose()` | Release resources |

### Tokenizer (Rust)

| Function | Description |
|----------|-------------|
| `initTokenizer(path)` | Load tokenizer.json |
| `tokenize(text)` | Get token IDs |
| `decodeTokens(ids)` | Decode to text |
| `getVocabSize()` | Get vocabulary size |

## Performance

Tested on iPhone 15 Pro Max (Simulator):

| Operation | Time |
|-----------|------|
| Tokenization (7 chars) | 0.8ms |
| Embedding (7 chars) | 4.1ms |
| Embedding (120 chars) | 36ms |
| HNSW Search (100 docs) | 1.0ms |

## Model Requirements

This package requires:

1. **ONNX Model** - Sentence transformer model exported to ONNX format
   - Recommended: `sentence-transformers/all-MiniLM-L6-v2`
   - Output: 384-dimensional embeddings

2. **Tokenizer** - HuggingFace tokenizer.json file

### Getting the Model

```bash
# Install optimum
pip install optimum[exporters]

# Export to ONNX
optimum-cli export onnx \
  --model sentence-transformers/all-MiniLM-L6-v2 \
  ./model_output
```

## License

MIT License - see [LICENSE](LICENSE) file.

## Contributing

Contributions welcome! Please read the contributing guidelines first.

## Acknowledgments

- [flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge) - Rust/Dart FFI
- [instant-distance](https://crates.io/crates/instant-distance) - HNSW implementation
- [onnxruntime](https://pub.dev/packages/onnxruntime) - ONNX inference
- [sentence-transformers](https://www.sbert.net/) - Embedding models
