# Flutter Rust Bridge v2 프로젝트 설정 가이드

flutter_rust_bridge v2를 사용하여 Flutter + Rust 프로젝트를 올바르게 설정하는 단계별 가이드입니다.

---

## 목차

1. [사전 요구사항](#1-사전-요구사항)
2. [프로젝트 생성](#2-프로젝트-생성)
3. [iOS 설정](#3-ios-설정)
4. [Android 설정](#4-android-설정)
5. [Rust 코드 작성](#5-rust-코드-작성)
6. [코드 생성 및 빌드](#6-코드-생성-및-빌드)
7. [자주 발생하는 오류](#7-자주-발생하는-오류)

---

## 1. 사전 요구사항

```bash
# Flutter 설치 확인
flutter doctor

# Rust 설치
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# iOS/Android 타겟 추가
rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android

# flutter_rust_bridge 코드 생성기 설치
cargo install flutter_rust_bridge_codegen
```

---

## 2. 프로젝트 생성

### 방법 A: flutter_rust_bridge CLI 사용 (권장)

```bash
# 새 프로젝트 생성
flutter_rust_bridge_codegen create my_app

# 기존 Flutter 프로젝트에 Rust 추가
cd existing_flutter_project
flutter_rust_bridge_codegen integrate
```

### 방법 B: 수동 설정

```bash
# 1. Flutter 프로젝트 생성
flutter create my_app
cd my_app

# 2. Rust 프로젝트 생성
mkdir rust
cd rust
cargo init --lib --name rust_lib_my_app
cd ..

# 3. flutter_rust_bridge.yaml 생성
cat > flutter_rust_bridge.yaml << 'EOF'
rust_input: crate::api
rust_root: rust/
dart_output: lib/src/rust
EOF
```

> ⚠️ **중요**: 수동 설정 시 `rust_builder/` 폴더 구성이 복잡합니다. CLI 사용을 강력히 권장합니다.

---

## 3. iOS 설정

### 3.1 pubspec.yaml 확인

**반드시 `rust_lib_*` 의존성이 포함되어야 합니다:**

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_rust_bridge: 2.11.1
  rust_lib_my_app:           # ⬅️ 필수!
    path: rust_builder       # ⬅️ 필수!
```

### 3.2 iOS Podfile 확인

`ios/Podfile`이 Flutter 표준 형식인지 확인:

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
    raise "#{generated_xcode_build_settings_path} must exist. Run flutter pub get first."
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
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
end
```

### 3.3 Pod 설치

```bash
cd ios
rm -rf Podfile.lock Pods
pod install
cd ..
```

---

## 4. Android 설정

### 4.1 NDK 설치

Android Studio > SDK Manager > SDK Tools > NDK (Side by side) 설치

### 4.2 local.properties 확인

```properties
# android/local.properties
ndk.dir=/Users/YOUR_USER/Library/Android/sdk/ndk/VERSION
```

### 4.3 build.gradle 설정

```gradle
// android/app/build.gradle
android {
    ndkVersion flutter.ndkVersion  // 또는 특정 버전 지정
}
```

---

## 5. Rust 코드 작성

### 5.1 디렉토리 구조

```
rust/
├── Cargo.toml
└── src/
    ├── lib.rs
    └── api/
        ├── mod.rs
        └── simple.rs    # 여기에 함수 작성
```

### 5.2 Cargo.toml

```toml
[package]
name = "rust_lib_my_app"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "staticlib"]  # 둘 다 필요!

[dependencies]
flutter_rust_bridge = "2.11.1"

# iOS 빌드 주의가 필요한 크레이트:
# - ort (ONNX Runtime): iOS 크로스컴파일 복잡
# - rusqlite: bundled 피처 필요
# - openssl: 별도 설정 필요
```

### 5.3 함수 작성 예시

```rust
// rust/src/api/simple.rs
use flutter_rust_bridge::frb;

#[frb(sync)]  // 동기 함수 (await 불필요)
pub fn greet(name: String) -> String {
    format!("Hello, {}!", name)
}

pub async fn fetch_data() -> Vec<u8> {  // 비동기 함수
    // ...
}
```

---

## 6. 코드 생성 및 빌드

### 6.1 Dart 바인딩 생성

```bash
flutter_rust_bridge_codegen generate
```

### 6.2 의존성 설치

```bash
flutter pub get
```

### 6.3 iOS Pod 설치

```bash
cd ios && pod install && cd ..
```

### 6.4 실행

```bash
flutter run
```

---

## 7. 자주 발생하는 오류

### 오류 1: Failed to load dynamic library

```
Failed to load dynamic library 'rust_lib_*.framework/rust_lib_*'
```

**원인**: `pubspec.yaml`에 rust_lib 의존성 누락  
**해결**:
```yaml
dependencies:
  rust_lib_my_app:
    path: rust_builder
```

---

### 오류 2: 0 pods installed

```
Pod installation complete! There are 0 dependencies from the Podfile
```

**원인**: Podfile에 Flutter 헬퍼 스크립트 누락  
**해결**: [3.2 iOS Podfile 확인](#32-ios-podfile-확인) 참조

---

### 오류 3: ort-sys build failed

```
failed to run custom build command for `ort-sys`
```

**원인**: ONNX Runtime이 iOS 크로스컴파일을 지원하지 않음  
**해결**:
- 개발 초기에는 ort 제외하고 빌드
- 필요시 pre-built iOS 바이너리 사용

---

### 오류 4: Rust target not found

```
error: target 'aarch64-apple-ios-sim' not found
```

**해결**:
```bash
rustup target add aarch64-apple-ios-sim
```

---

## 체크리스트

새 프로젝트 설정 시 확인할 사항:

- [ ] `flutter_rust_bridge_codegen create` 또는 `integrate` 사용
- [ ] `pubspec.yaml`에 `rust_lib_*` path 의존성 추가됨
- [ ] `rust/Cargo.toml`의 crate-type에 `cdylib`, `staticlib` 포함
- [ ] iOS Podfile에 `flutter_install_all_ios_pods` 포함
- [ ] `flutter pub get` 실행
- [ ] `cd ios && pod install` 실행
- [ ] iOS 크로스컴파일 문제가 있는 크레이트 확인 (ort, openssl 등)

---

## 참고 자료

- [flutter_rust_bridge 공식 문서](https://cjycode.com/flutter_rust_bridge/)
- [flutter_rust_bridge GitHub](https://github.com/aspect-build/rules_swc)
- [Cargokit (iOS/Android 빌드 시스템)](https://github.com/aspect-build/rules_swc)
