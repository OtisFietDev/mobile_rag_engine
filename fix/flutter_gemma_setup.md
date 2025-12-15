# FlutterGemma 초기화 및 모델 설정

## 원 이슈

### 이슈 1: FlutterGemma not initialized
```
Bad state: FlutterGemma not initialized!
You must call FlutterGemma.initialize() in main() before using the plugin.
```

### 이슈 2: HuggingFace 인증 필요 (HTTP 401/403)
```
DownloadException: Authentication required (HTTP 401).
Please provide a valid HuggingFace token
```

### 이슈 3: 모델 URL 404 에러
```
Model not found (HTTP 404)
```

### 이슈 4: 앱 재시작 시 모델 다시 다운로드
모델이 이미 다운로드되어 있어도 매번 다운로드 화면 표시

---

## 해결 과정

### 이슈 1 해결: FlutterGemma 초기화

**수정 파일**: `test_app/lib/main.dart`

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // .env 파일 로드
  await dotenv.load(fileName: 'assets/.env');
  
  // RustLib 초기화 (iOS/macOS용)
  if (Platform.isIOS || Platform.isMacOS) {
    await RustLib.init(
      externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
    );
  } else {
    await RustLib.init();
  }
  
  // FlutterGemma 초기화 (HuggingFace 토큰 포함)
  final hfToken = dotenv.env['HUGGINGFACE_TOKEN'];
  await FlutterGemma.initialize(
    huggingFaceToken: hfToken,
  );
  
  runApp(const TestApp());
}
```

---

### 이슈 2 해결: HuggingFace 토큰 설정

**1. 환경 변수 파일 생성**

`test_app/assets/.env.sample`:
```
# HuggingFace API Token
# Get your token from: https://huggingface.co/settings/tokens
HUGGINGFACE_TOKEN=hf_your_token_here
```

**2. pubspec.yaml에 assets 추가**
```yaml
flutter:
  assets:
    - assets/
    - assets/.env
```

**3. .gitignore 추가**
```
# Environment files
assets/.env
```

**4. flutter_dotenv 의존성 추가**
```bash
flutter pub add flutter_dotenv
```

---

### 이슈 3 해결: 올바른 모델 URL

**수정 파일**: `test_app/lib/screens/model_setup_screen.dart`

잘못된 URL (404):
```
https://huggingface.co/nicholasKluge/Gemma-2b-It-Task/resolve/main/gemma-2b-it-gpu-int8.task
```

올바른 URL:
```
https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv2048.task
```

> **참고**: litert-community 모델은 Gated Model이므로:
> 1. https://huggingface.co/litert-community/Gemma3-1B-IT 방문
> 2. 라이선스 동의 ("Request access" 클릭)
> 3. 승인 후 다운로드 가능

---

### 이슈 4 해결: 모델 활성화 로직

**수정 파일**: `test_app/lib/main.dart`

```dart
Future<void> _checkAndActivateModel() async {
  try {
    // 설치된 모델 목록 확인
    final installedModels = await FlutterGemma.listInstalledModels();
    
    if (installedModels.isNotEmpty) {
      setState(() => _statusMessage = 'Activating model...');
      
      // 로컬 파일에서 모델 활성화
      final modelId = installedModels.first;
      final dir = await getApplicationDocumentsDirectory();
      final modelPath = '${dir.path}/$modelId';
      
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
      ).fromFile(modelPath).install();
      
      setState(() {
        _isModelInstalled = true;
      });
    }
  } catch (e) {
    debugPrint('🔴 Model activation error: $e');
  }
}
```

---

## 설정 체크리스트

- [ ] HuggingFace 토큰 발급: https://huggingface.co/settings/tokens
- [ ] 모델 라이선스 동의: https://huggingface.co/litert-community/Gemma3-1B-IT
- [ ] `assets/.env` 파일 생성 (`.env.sample` 복사)
- [ ] 토큰 입력: `HUGGINGFACE_TOKEN=hf_xxxxx`
