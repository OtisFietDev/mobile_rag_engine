# iOS Rust 라이브러리 링킹 문제 해결

## 원 이슈

### 증상
```
Failed to lookup symbol 'frb_get_rust_content_hash': symbol not found
```

iOS에서 Flutter 앱 실행 시 Rust 라이브러리의 심볼을 찾을 수 없음.

### 원인 분석

1. **podspec에서 `pod_target_xcconfig` 중복 정의**
   - 두 번째 정의가 첫 번째를 덮어씀
   
2. **`-force_load` 경로 오류**
   - 설정: `${BUILT_PRODUCTS_DIR}/librust_lib_mobile_rag_engine.a`
   - 실제: `${BUILT_PRODUCTS_DIR}/rust_lib_mobile_rag_engine/librust_lib_mobile_rag_engine.a`

3. **`user_target_xcconfig` 누락**
   - `pod_target_xcconfig`는 Pod 자체 빌드 설정
   - `user_target_xcconfig`는 앱(Runner) 타겟 설정 ← 이게 필요

---

## 해결 과정

### 수정 파일
`rust_builder/ios/rust_lib_mobile_rag_engine.podspec`

### 수정 전
```ruby
# Flutter.framework does not contain a i386 slice.
s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
s.swift_version = '5.0'

s.script_phase = { ... }

s.pod_target_xcconfig = {
  'DEFINES_MODULE' => 'YES',
  'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/librust_lib_mobile_rag_engine.a',
}
```

### 수정 후
```ruby
s.swift_version = '5.0'

s.script_phase = {
  :name => 'Build Rust library',
  :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../../rust rust_lib_mobile_rag_engine',
  :execution_position => :before_compile,
  :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
  :output_files => ["${BUILT_PRODUCTS_DIR}/rust_lib_mobile_rag_engine/librust_lib_mobile_rag_engine.a"],
}

# Pod target build settings (한 번만 정의)
s.pod_target_xcconfig = {
  'DEFINES_MODULE' => 'YES',
  'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/rust_lib_mobile_rag_engine/librust_lib_mobile_rag_engine.a',
}

# App target (Runner) build settings - 핵심!
s.user_target_xcconfig = {
  'OTHER_LDFLAGS' => '$(inherited) -force_load ${BUILT_PRODUCTS_DIR}/rust_lib_mobile_rag_engine/librust_lib_mobile_rag_engine.a',
}
```

---

## 검증

### Pod 설치 후 확인
```bash
grep -i "force_load.*rust_lib" ios/Pods/Target\ Support\ Files/Pods-Runner/Pods-Runner.debug.xcconfig
```

예상 결과:
```
OTHER_LDFLAGS = ... -force_load ${BUILT_PRODUCTS_DIR}/rust_lib_mobile_rag_engine/librust_lib_mobile_rag_engine.a
```

---

## 참고

### `pod_target_xcconfig` vs `user_target_xcconfig`
| 설정 | 적용 대상 | 용도 |
|-----|---------|-----|
| `pod_target_xcconfig` | Pod 자체 | Pod 빌드 시 사용 |
| `user_target_xcconfig` | 앱 타겟 (Runner) | 앱 링킹 시 사용 |

### `DynamicLibrary.process()` 사용
iOS에서 정적 라이브러리를 사용하므로 `main.dart`에서:
```dart
if (Platform.isIOS || Platform.isMacOS) {
  await RustLib.init(
    externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
  );
}
```
