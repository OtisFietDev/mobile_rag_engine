제공해주신 파일들을 바탕으로 `ai_edge_rag` 패키지의 **핵심 기술**과 **아키텍처/베이스 언어**를 분석한 결과입니다.

이 패키지는 구글의 **MediaPipe GenAI** 프레임워크를 기반으로, 모바일 기기(현재는 Android 중심)에서 **온디바이스 RAG (Retrieval Augmented Generation, 검색 증강 생성)** 기능을 구현하도록 돕는 Flutter 플러그인입니다.

---

### 1. 아키텍처 및 베이스 언어 (Architecture & Base Language)

이 프로젝트는 전형적인 **Flutter Federated Plugin** 아키텍처를 따르고 있으며, Dart와 Native(Kotlin) 간의 통신을 통해 온디바이스 AI 기능을 수행합니다.

* **베이스 언어 (Base Languages):**
    * **Dart (Flutter):** 앱 개발자가 사용하는 상위 레벨 API 및 인터페이스 정의. (`lib/` 디렉토리)
    * **Kotlin (Android):** 실제 MediaPipe RAG 엔진을 구동하는 핵심 로직 구현. (`android/src/main/kotlin/` 디렉토리)
    * **참고:** iOS 관련 코드는 `ai_edge_rag` 패키지 내에 존재하지 않으며, 문서상으로도 Android 전용(또는 iOS 추후 지원)으로 보입니다.

* **아키텍처 구조:**
    1.  **Dart Layer (Client):** `AiEdgeRag` 클래스(Singleton)가 사용자 인터페이스 역할을 합니다. 사용자는 여기서 모델 초기화, 텍스트 청크 저장(Memorize), 질문(Generate) 등의 메서드를 호출합니다.
    2.  **Platform Interface Layer:** `AiEdgeRagPlatform`을 통해 기능을 추상화하고 `MethodChannelAiEdgeRag`에서 실제 채널 통신을 담당합니다.
    3.  **Method/Event Channel:**
        * `MethodChannel` (`ai_edge_rag/methods`): 모델 생성, 세션 초기화, 데이터 저장 등 명령 전달에 사용됩니다.
        * `EventChannel` (`ai_edge_rag/events`): LLM이 생성하는 답변을 스트리밍(Streaming) 방식으로 실시간 수신하는 데 사용됩니다.
    4.  **Native Layer (Android):** `AiEdgeRagPlugin.kt`가 핵심입니다. 여기서 Google의 `localagents-rag` 라이브러리를 사용하여 실제 임베딩 생성, 벡터 저장, 검색 및 답변 생성을 수행합니다.

---

### 2. 핵심 기술 (Core Technologies)

`ai_edge_rag`는 단순히 LLM을 돌리는 것을 넘어, 외부 데이터를 참조하여 답변하는 **RAG 시스템의 전체 파이프라인**을 모바일 기기 내에서 구현합니다.

#### A. 하이브리드 임베딩 모델 (Hybrid Embedding Support)
사용자의 텍스트 데이터를 벡터화(Embedding)하는 방식에 있어 두 가지 옵션을 제공합니다.
* **Local Embeddings (On-Device):** 인터넷 연결 없이 기기 내부에서 처리합니다.
    * **Gemma Embedding Model:** 구글의 Gemma 모델 기반.
    * **Gecko Embedding Model:** 모바일에 최적화된 경량 임베딩 모델.
    * 참고 파일: `AiEdgeRagPlugin.kt` 내 `GemmaEmbeddingModel`, `GeckoEmbeddingModel` 초기화 로직.
* **Cloud Embeddings:**
    * **Gemini Embedder:** 구글의 Gemini API를 사용하여 더 고품질의 임베딩을 생성할 수 있습니다 (API Key 필요).

#### B. 유연한 벡터 저장소 (Flexible Vector Store)
임베딩된 벡터 데이터를 저장하고 검색하는 저장소를 선택할 수 있습니다.
* **In-Memory (DefaultVectorStore):** RAM에 저장하여 속도가 빠르지만 앱 종료 시 데이터가 휘발됩니다.
* **SQLite (SqliteVectorStore):** SQLite 데이터베이스를 사용하여 데이터를 영구적으로 저장합니다. 앱을 재시작해도 기억된 데이터(Context)가 유지됩니다.
    * 참고 파일: `AiEdgeRagPlugin.kt`에서 `SqliteVectorStore` 사용 확인.

#### C. 시맨틱 메모리 및 검색 (Semantic Memory & Retrieval)
단순 키워드 매칭이 아닌 의미 기반 검색을 수행합니다.
* **Memorize:** `memorizeChunk`, `memorizeChunkedText` 등을 통해 텍스트를 벡터로 변환하여 저장합니다.
* **Retrieval:** 질문이 들어오면 `DefaultSemanticTextMemory`를 통해 유사도(Similarity)가 높은 청크를 검색합니다.
* **Chain 구성:** 검색된 정보와 사용자 질문을 결합하여 `RetrievalAndInferenceChain`을 통해 LLM에 전달, 최종 답변을 생성합니다.

#### D. 자동 텍스트 청킹 (Text Chunking)
긴 문서를 한 번에 처리하기 어렵기 때문에 자동으로 적절한 크기로 자르는 기능을 내장하고 있습니다.
* `TextChunker`를 사용하여 `chunkSize`(청크 크기)와 `chunkOverlap`(중복 구간)을 설정해 문맥 손실을 최소화하며 텍스트를 분할합니다.

#### E. 시스템 명령어 주입 (System Instruction)
RAG 동작 방식을 제어하기 위해 프롬프트 엔지니어링을 적용할 수 있습니다.
* `PromptBuilder`를 통해 "검색된 문맥을 바탕으로 답변하라"는 등의 시스템 지시어를 LLM에 주입하여 답변의 정확도를 높입니다.

### 요약

`ai_edge_rag` 레포지토리는 **Flutter(Dart)**와 **Android(Kotlin)**을 기반으로 **Google MediaPipe Local Agents** 라이브러리를 래핑한 구조입니다. 핵심은 **서버 없이 모바일 기기 자체적으로(On-Device)** 벡터 DB(SQLite)와 임베딩 모델(Gecko/Gemma)을 구동하여 개인정보 보호가 강력한 **RAG 시스템**을 구축하는 기술입니다.