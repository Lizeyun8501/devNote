# Contributing to DevNote

First off, thank you for your interest in DevNote! We appreciate your time and effort in helping make this project better. Whether you are reporting a bug, proposing a feature, or submitting a pull request, your contribution is welcome.

This document describes how to set up your environment and the conventions we follow. Please also read our [Code of Conduct](CODE_OF_CONDUCT.md) to keep the community welcoming and respectful.

---

## Development Environment

Before you begin, make sure the following toolchains are installed on your machine (these match the prerequisites in the [README](README.md)):

- **Flutter**: >= 3.7.2 (Dart >= 3.7.2)
- **Rust**: >= 1.96.0 (Edition 2021)
- **Go**: >= 1.21
- **Android Studio / Xcode**: required for mobile debugging

See the [README](README.md#开发环境配置) for the full setup and installation steps.

---

## Development Workflow

1. **Fork the repository** on GitHub and clone your fork locally.
2. **Create a branch** for your work:
   ```bash
   git checkout -b feature/your-feature
   ```
3. **Commit your changes** following the [Conventional Commits](#commit-convention) convention.
4. **Run the checks** to make sure your changes are clean (see [Code Standards](#code-standards)):
   ```bash
   dart analyze lib/
   cd rust-core && cargo clippy
   cd sync-server && go vet ./...
   ```
5. **Create a Pull Request** against the `main` branch and fill in the [PR template](.github/PULL_REQUEST_TEMPLATE.md).

---

## Commit Convention

We follow [Conventional Commits](https://www.conventionalcommits.org/). Each commit message should be structured as:

```
<type>(<scope>): <subject>
```

### Supported Types

| Type     | Description                          |
|----------|--------------------------------------|
| `feat`   | A new feature                        |
| `fix`    | A bug fix                            |
| `docs`   | Documentation only changes           |
| `refactor` | A code change that neither fixes a bug nor adds a feature |
| `test`   | Adding or correcting tests           |
| `chore`  | Build, tooling, or maintenance tasks |
| `ci`     | Changes to CI configuration          |

### Scope Examples

The scope is optional but recommended to indicate the affected module. For example:

```
feat(editor): add code block syntax highlighting
fix(sync): resolve conflict on concurrent edits
docs(architecture): update C4 container diagram
refactor(crypto): simplify key derivation flow
test(notes): add folder tree unit tests
chore(deps): bump flutter_bloc to 9.1.0
ci(rust): cache cargo registry in workflow
```

---

## Code Standards

All contributions must pass the linters and formatters for the relevant language(s). Do not introduce new warnings.

- **Dart**: follow `dart format` and ensure `dart analyze` reports no warnings.
  ```bash
  dart format .
  dart analyze lib/
  ```
- **Rust**: follow `cargo fmt` and ensure `cargo clippy` reports no warnings.
  ```bash
  cd rust-core
  cargo fmt --all
  cargo clippy --workspace -- -D warnings
  ```
- **Go**: follow `gofmt` and ensure `go vet` reports no warnings.
  ```bash
  cd sync-server
  gofmt -w .
  go vet ./...
  ```

---

## CI Checks

The repository has three CI workflows under `.github/workflows/`. Each runs on pushes and pull requests targeting the `main` branch, but only when the relevant paths change.

| Workflow          | File                          | Trigger Paths                                                                                       | What it runs                                   |
|-------------------|-------------------------------|-----------------------------------------------------------------------------------------------------|------------------------------------------------|
| **Flutter CI**    | `flutter-ci.yml`              | `lib/**`, `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `.github/workflows/flutter-ci.yml` | `flutter pub get`, `flutter analyze`, `flutter test --no-pub` |
| **Rust CI**       | `rust-ci.yml`                 | `rust-core/**`, `.github/workflows/rust-ci.yml`                                                     | `cargo fmt --check`, `cargo check`, `cargo test`, `cargo clippy -D warnings` |
| **Go CI**         | `go-ci.yml`                   | `sync-server/**`, `business-server/**`, `.github/workflows/go-ci.yml`                               | `go mod download`, `go vet`, `go build`, `go test -race` (matrix over `sync-server` and `business-server`) |

Make sure the CI checks that correspond to your changes pass locally before opening a PR.

---

## Architecture Constraints

DevNote follows a **five-layer architecture** with an **FFI bridge pattern** connecting the Rust core to the Flutter UI. The full model is documented in [docs/c4-architecture.md](docs/c4-architecture.md).

The layers, from bottom to top:

1. **Core Layer (Rust Core)** — pure Rust implementing editor, CRDT, crypto, search, sync, and graph logic, exported via a C FFI interface.
2. **Bridge Layer (FFI Bridge)** — Dart FFI bindings that wrap the Rust C interface into asynchronous Dart calls.
3. **Service Layer** — Flutter-side business logic using the Repository pattern for data persistence.
4. **State Management Layer (BLoC)** — reactive state management based on the BLoC pattern.
5. **Presentation Layer (UI)** — Material Design 3 Flutter widgets.

**Do not break the layering.** Dependencies must flow downward only:

- The UI layer must not call the FFI bridge directly; it goes through BLoC and services.
- Services must not import UI widgets.
- The Rust core must not depend on Dart or Flutter.
- The FFI bridge is the only place that translates between Rust and Dart types.

If your change touches the boundary between layers, please describe the rationale in your PR and reference the relevant ADRs under [docs/adr/](docs/adr/) (e.g. [002-ffi-bridge-pattern.md](docs/adr/002-ffi-bridge-pattern.md), [003-five-layer-architecture.md](docs/adr/003-five-layer-architecture.md)).

---

## Issue Reporting

We use [GitHub Issues](https://github.com/Lizeyun8501/devNote/issues) to track bugs and feature requests.

### Bug Reports

Use the **Bug report** template (`.github/ISSUE_TEMPLATE/bug_report.yml`). Please include:

- A clear description of the bug.
- Step-by-step reproduction instructions.
- The expected and actual behavior.
- The platform(s) you reproduced it on and the app version.

### Feature Requests

Use the **Feature request** template (`.github/ISSUE_TEMPLATE/feature_request.yml`). Please include:

- The problem or motivation the feature addresses.
- Your proposed solution.
- Any alternatives you have considered.

Before opening a new issue, please search existing issues to avoid duplicates.

---

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md). Please be respectful and constructive in all interactions.
