# Rails 8 Development Guardrails Draft

Rails Symphony에서 Rails 8 기본선과 37signals/Basecamp식 작업 방식을 어기지 않기 위한 초안이다.
기존 [AGENTS.md](/Users/hc/Repository/rails/rails-symphony/AGENTS.md)를 직접 수정하지 않고, 원본을 보존한 뒤 요약·개선한 작업 문서다.

원본 스냅샷: [docs/_archive/2026-03-19-AGENTS-original.md](/Users/hc/Repository/rails/rails-symphony/docs/_archive/2026-03-19-AGENTS-original.md)

## 목적

- Rails 8의 기본 동작과 현재 스택 가정을 유지한다.
- 프론트엔드와 애플리케이션 구조를 "vanilla Rails" 기준으로 통제한다.
- 사람이든 AI 에이전트든 같은 제약 아래에서 작업하게 만든다.

## 현재 프로젝트 기본선

이 프로젝트는 이미 다음 조합을 사용한다.

- Rails 8
- SQLite
- Propshaft
- Importmap
- Turbo
- Stimulus
- Solid Queue / Solid Cache / Solid Cable
- ERB 기반 서버 렌더링

이 기본선을 바꾸는 제안은 예외로 다룬다. 편의나 취향만으로 바꾸지 않는다.

## 성공 기준

다음이 만족되면 가드레일이 제대로 작동한 것으로 본다.

- 새 UI 작업이 기본적으로 ERB + Turbo + Stimulus 안에서 해결된다.
- 새 기능 때문에 Node 번들러, SPA 프레임워크, API-first 구조를 도입하지 않는다.
- 컨트롤러, 모델, 잡, 뷰가 Rails 관용구 안에서 유지된다.
- AI 에이전트가 문서만 읽고도 "기본 선택"과 "예외 조건"을 구분할 수 있다.

## 기본 원칙

### 1. Vanilla Rails First

Rails가 이미 제공하는 기능을 먼저 쓴다.

- RESTful routes
- Active Record
- Action Controller / Action View
- Active Job
- Turbo / Stimulus
- Rails helpers, partials, form builders

새 추상화나 외부 프레임워크는 Rails 기본 기능으로 해결이 안 될 때만 검토한다.

### 2. Frontend Defaults Stay Simple

프론트 기본값은 서버 렌더링이다.

- HTML 응답이 기본이다.
- 부분 갱신은 Turbo Frame / Turbo Stream을 우선한다.
- 클라이언트 상호작용은 Stimulus controller로 제한한다.
- JavaScript 의존성 관리는 Importmap 기준으로 생각한다.

다음은 기본 선택이 아니다.

- React / Vue / Svelte 도입
- Vite, esbuild, Webpack 계열 번들러 추가
- JSON API를 먼저 만들고 프론트를 따로 붙이는 구조
- 단순 화면 요구사항에 대한 과도한 Stimulus 사용

이런 선택은 "왜 Rails 8 기본선으로는 안 되는가"를 먼저 설명해야 한다.

### 3. Architecture Follows Rails

- 컨트롤러는 얇게 유지한다.
- 도메인 규칙은 모델 또는 도메인 객체에 둔다.
- Job은 비동기 경계에만 사용한다.
- Service object는 기본 단위가 아니다.

Service object를 써도 되는 경우:

- 외부 시스템 경계가 분명할 때
- 복수 모델/트랜잭션 조합을 독립적으로 캡슐화해야 할 때
- 재사용보다 명확한 경계가 더 중요한 경우

그 외에는 controller -> model 흐름을 우선한다.

### 4. Built-ins Before New Dependencies

새 gem이나 새 인프라를 추가하기 전에 먼저 확인한다.

- Rails 내장 기능으로 가능한가?
- 이미 프로젝트에 있는 라이브러리로 가능한가?
- 단기 편의 대신 장기 유지비를 늘리는 선택 아닌가?

특히 프론트엔드 스택 변경은 의존성 추가보다 아키텍처 변경으로 취급한다.

## 프로젝트 적용 규칙

### UI / Frontend

- 기본 뷰는 ERB에 둔다.
- 화면 전환은 Turbo를 우선한다.
- 소규모 동작만 Stimulus에 둔다.
- CSS/asset 처리는 현재 Rails 자산 파이프라인 전제를 유지한다.
- 브라우저 상태를 클라이언트 프레임워크에서 장기 보관하지 않는다.

### Routing

- 가능하면 리소스 라우팅으로 모델링한다.
- member/custom action은 새 리소스로 풀 수 없는지 먼저 본다.

### Controllers

- 파라미터 정리, 인증/인가, 응답 조합에 집중한다.
- 도메인 분기와 상태 전이는 모델 계층으로 내린다.

### Models / Domain

- 비즈니스 규칙과 상태 전이를 여기에 둔다.
- 현재 `Symphony::` 네임스페이스 규칙을 유지한다.
- 오케스트레이터/워크스페이스 관련 상태성과 동시성 의미를 깨지 않는다.

### Jobs

- 비동기 실행 경계만 담당한다.
- 재시도, reconciliation, cleanup 의미를 바꾸는 리팩터링은 신중히 다룬다.

## AI 에이전트용 작업 규칙

AI 에이전트는 다음을 기본값으로 가정한다.

- 이 프로젝트는 Rails 8 앱이다.
- 프론트는 ERB + Turbo + Stimulus + Importmap + Propshaft 기준이다.
- API-first, SPA-first, Node bundler-first 제안은 예외다.
- Rails 기본 기능으로 해결 가능한 문제에 새 프레임워크를 추가하지 않는다.
- "요즘 프론트 관행"보다 현재 앱의 Rails 관용구를 우선한다.

AI 에이전트는 다음 행동을 피한다.

- `package.json`이나 JS bundler를 당연한 전제로 추가
- 단순 상호작용에 React 컴포넌트 구조를 들여오는 일
- JSON API를 새 기본 인터페이스처럼 확장하는 일
- 서비스 객체, presenter, facade를 습관적으로 늘리는 일

## 예외 승인 기준

다음 중 하나를 만족하지 못하면 기본선 이탈 제안은 기각한다.

- Rails 기본선으로는 요구사항을 구현하기 어렵다는 구체적 근거가 있다.
- 성능, 복잡한 클라이언트 상태, 외부 라이브러리 제약 같은 명확한 기술 사유가 있다.
- 도입 범위, 유지비, 테스트 전략, 롤백 전략이 함께 제시된다.

## 기존 AGENTS.md에서 유지할 내용

다음 내용은 그대로 유지하는 편이 맞다.

- `WORKFLOW.md` / `Symphony::ServiceConfig` 중심 설정 규칙
- `Symphony SPEC` 정합성 요구
- `Symphony::` 네임스페이스 강제
- workspace safety 규칙
- orchestrator의 stateful / concurrency-sensitive 특성
- structured logging 요구
- 테스트 게이트로 `bin/rails test` 사용

## 기존 AGENTS.md에 추가할 개선 포인트

기존 문서에는 다음 문장이 보강되면 좋다.

- "Frontend defaults to ERB + Turbo + Stimulus + Importmap + Propshaft."
- "Do not introduce SPA frameworks or Node bundlers without explicit architectural approval."
- "Prefer vanilla Rails patterns over service-heavy or API-first designs."
- "Treat frontend stack changes as architectural changes, not implementation details."

## 제안된 통합 방향

원본을 바로 덮어쓰지 말고 다음 순서로 가는 게 맞다.

1. 이 초안에서 문구를 더 줄여서 정책 문장만 남긴다.
2. [AGENTS.md](/Users/hc/Repository/rails/rails-symphony/AGENTS.md)에 들어갈 최소 규칙만 추린다.
3. 필요하면 [README.md](/Users/hc/Repository/rails/rails-symphony/README.md)에는 "현재 스택 기본선" 정도만 반영한다.
4. 세부 설명은 가이드 문서로 남긴다.
