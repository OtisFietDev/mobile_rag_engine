# iOS 빌드 오류 해결 기록

**날짜**: 2025-12-07  
**프로젝트**: mobile_rag_engine (Flutter + Rust via flutter_rust_bridge)

---

## 발생한 오류

```
[ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: 
Invalid argument(s): Failed to load dynamic library 
'rust_lib_mobile_rag_engine.framework/rust_lib_mobile_rag_engine': 
dlopen(...): tried: '...' (no such file)
```

Rust 라이브러리 프레임워크가 iOS 앱 번들에 포함되지 않아 런타임에 동적 라이브러리를 찾을 수 없는 오류.

---

## 원인 분석

### 1. `rust_lib_mobile_rag_engine` 의존성 누락
`rust_builder/` 폴더에 Rust 빌드용 Flutter 플러그인이 정의되어 있었지만, 메인 `pubspec.yaml`에 의존성으로 선언되지 않음.

### 2. iOS Podfile 설정 오류
기본 Flutter pod 설정 스크립트가 누락되어 CocoaPods가 Flutter 플러그인을 인식하지 못함.
```
Pod installation complete! There are 0 dependencies from the Podfile and 0 total pods installed.
```

### 3. `ort` 크레이트 iOS 빌드 실패
ONNX Runtime (`ort`) 크레이트가 iOS 크로스 컴파일 환경에서 빌드되지 않음.

---

## 해결 방법

### 1. pubspec.yaml에 Rust 플러그인 의존성 추가

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_rust_bridge: 2.11.1
  rust_lib_mobile_rag_engine:        # 추가
    path: rust_builder               # 추가
```

### 2. iOS Podfile 수정

기존 Podfile을 Flutter 표준 형식으로 교체:

```ruby
platform :ios, '13.0'

ENV['COCOAPODS_DISABLE_STATS'] = 'true'

project 'Runner', {
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
}

def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings_path)
    raise "#{generated_xcode_build_settings_path} must exist."
  end

  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT\=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found"
end

require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)

flutter_ios_podfile_setup

target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))

  target 'RunnerTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
end
```

### 3. Cargo.toml에서 ort 의존성 비활성화

```toml
[dependencies]
flutter_rust_bridge = "2.11.1"
anyhow = "1.0.100"
rusqlite = "0.32.1"
# ort = "2.0.0-rc.10"  # iOS 크로스 컴파일 문제로 비활성화
ndarray = "0.17.1"
log = "0.4.29"
```

---

## 빌드 명령어

```bash
# 클린 빌드
flutter clean
flutter pub get
cd ios && pod install

# 실행
flutter run
```

---

## 결과

```
✅ Xcode build done.
✅ Syncing files to device iPhone 15 Pro Max... 32ms
✅ flutter: 사과 vs 배 유사도: 0.9977626204490662
✅ flutter: 사과 vs 차 유사도: 0.14946147799491882
```

iOS 시뮬레이터에서 Rust 함수(`calculate_cosine_similarity`) 정상 동작 확인.

---

## 향후 참고사항

- `ort` (ONNX Runtime) 사용 시 iOS용 pre-built 바이너리 사용 또는 별도 크로스 컴파일 설정 필요
- flutter_rust_bridge v2 프로젝트에서는 반드시 `rust_builder`를 path 의존성으로 추가해야 함
