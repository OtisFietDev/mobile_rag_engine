# LLM 응답 처리 문제 해결

## 원 이슈

### 이슈 1: TextResponse("...") 형식 그대로 출력
```
TextResponse("I am Gemma, an open-weights AI assistant.")
```

### 이슈 2: Input too long 에러
```
OUT_OF_RANGE: Input is too long for the model to process:
input_size(723) was not less than maxTokens(512)
```

### 이슈 3: 대화 히스토리 미유지
"yes"라고 답변해도 이전 맥락을 기억하지 못함

### 이슈 4: LLM 반복 출력
```
This would allow an aircraft... This would allow an aircraft... This would allow an aircraft...
```

---

## 해결 과정

### 이슈 1 해결: TextResponse 파싱

**수정 파일**: `test_app/lib/screens/rag_chat_screen.dart`

```dart
// Extract text from response
String responseText = 'No response generated.';
if (response != null) {
  if (response is TextResponse) {
    // 직접 token 프로퍼티 사용
    responseText = response.token;
  } else {
    // Fallback: toString()에서 추출
    final raw = response.toString();
    final match = RegExp(r'TextResponse\("(.*)"\)$', dotAll: true).firstMatch(raw);
    if (match != null) {
      responseText = match.group(1) ?? raw;
    } else {
      responseText = raw;
    }
  }
}
```

---

### 이슈 2 해결: maxTokens 증가

모델 파일명에서 용량 확인:
- `Gemma3-1B-IT_multi-prefill-seq_q4_ekv2048.task`
- `ekv2048` = 2048 토큰 지원

```dart
final model = await FlutterGemma.getActiveModel(
  maxTokens: 2048,  // 512 → 2048
  preferredBackend: PreferredBackend.gpu,
);
```

---

### 이슈 3 해결: 영구 채팅 세션

**문제**: 매 메시지마다 새 세션 생성 → 히스토리 소실

**해결**: 클래스 레벨에서 세션 유지

```dart
class _RagChatScreenState extends State<RagChatScreen> {
  // LLM 모델과 채팅 세션 (영구 유지)
  InferenceModel? _llmModel;
  InferenceChat? _chatSession;
  
  Future<String> _generateLlmResponse(String query, RagSearchResult ragResult) async {
    // 세션이 없으면 생성
    if (_llmModel == null) {
      _llmModel = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        preferredBackend: PreferredBackend.gpu,
      );
      _chatSession = await _llmModel!.createChat();
    }
    
    // 기존 세션에 메시지 추가
    await _chatSession!.addQueryChunk(Message.text(
      text: prompt,
      isUser: true,
    ));
    
    // 응답 생성 (세션이 히스토리 유지)
    final response = await _chatSession!.generateChatResponse();
    
    // 모델 닫지 않음! (세션 유지)
    return responseText;
  }
  
  // 에러 시 세션 리셋
  Future<void> _resetChatSession() async {
    if (_llmModel != null) {
      await _llmModel!.close();
      _llmModel = null;
    }
    _chatSession = null;
  }
}
```

---

### 이슈 4 해결: 반복 출력 정리

작은 LLM에서 흔히 발생하는 반복 루프 문제.

```dart
String _cleanRepetition(String text) {
  if (text.length < 100) return text;
  
  // 문장 단위 반복 감지
  final sentences = text.split(RegExp(r'[.!?\n]'));
  final seenPhrases = <String, int>{};
  final cleanedSentences = <String>[];
  
  for (final sentence in sentences) {
    final key = sentence.trim().toLowerCase();
    final count = (seenPhrases[key] ?? 0) + 1;
    seenPhrases[key] = count;
    
    if (count <= 2) {
      cleanedSentences.add(sentence.trim());
    } else if (count == 3) {
      cleanedSentences.add('...');
      break;  // 더 이상의 반복은 무시
    }
  }
  
  // 단어 시퀀스 반복 감지
  // e.g., "This would allow This would allow This would allow"
  // → 패턴 3회 이상 반복 시 2회로 잘라냄
  
  return result;
}
```

---

## 에러 로깅 개선

상세 에러는 터미널에, 간단한 메시지는 UI에:

```dart
} catch (e, stackTrace) {
  // 터미널에 상세 로그
  debugPrint('🔴 LLM Error: $e');
  debugPrint('🔴 Stack Trace: $stackTrace');
  
  // UI에는 간단한 메시지
  String errorType = 'Unknown error';
  if (e.toString().contains('PlatformException')) {
    errorType = 'Model session error';
  } else if (e.toString().contains('OUT_OF_RANGE')) {
    errorType = 'Context too long';
  }
  
  return '⚠️ LLM Error: $errorType\n\n'
         'The model encountered an issue. Please try again.\n'
         '(Check console for details)';
}
```
