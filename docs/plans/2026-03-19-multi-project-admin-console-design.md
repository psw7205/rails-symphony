# Multi-Project Admin Console Design

## Summary

Rails Symphony를 단일 workflow runtime 대시보드에서, 여러 project/workflow를 한곳에서 관리하는 멀티-프로젝트 어드민 콘솔로 확장한다.

상세 실행 계획은 `docs/plans/2026-03-19-multi-project-admin-console-implementation.md`를 따른다.

핵심 방향은 다음과 같다.

- 운영 설정의 source of truth를 `WORKFLOW.md`에서 어드민 DB(SQLite)로 이동한다.
- tracker는 `linear`, `github`, `database` 등 다양한 어댑터로 유지한다.
- 어드민 콘솔은 공통 운영 화면을 제공하되, tracker별 capability에 따라 가능한 작업만 노출한다.
- 실행 중 runtime 상태와 tracker 원본 데이터는 분리해서 관리한다.

## Assumptions

- 기존 `Symphony.orchestrator` 단일 singleton 구조는 멀티-프로젝트 요구사항에 맞지 않으므로 점진적으로 해체한다.
- `database` tracker는 외부 시스템 없이 콘솔 내부에서 직접 이슈를 관리하는 용도다.
- `linear`와 `github`는 외부 연동형 tracker로 유지한다.
- 초기 단계에서 외부 tracker mutation은 필수가 아니다. 조회와 동기화가 우선이다.
- 기존 `symphony_issues`는 runtime persistence 성격이 강하므로, 내부 tracker 원장과 같은 의미로 재사용하지 않는 방향을 우선 검토한다.

## Success Criteria

- 여러 `project`와 여러 `workflow`를 DB에서 생성, 수정, 비활성화할 수 있다.
- 각 workflow는 서로 다른 tracker 종류와 tracker 설정을 가질 수 있다.
- 콘솔에서 workflow별 issue 상태, runtime 상태, retry 상태, token usage를 분리해서 볼 수 있다.
- tracker별 capability에 따라 UI 동작이 분기된다.
- 새 tracker를 추가할 때 orchestrator와 UI 변경 범위가 제한적이다.
- 운영 문서가 DB 기반 관리 모델을 반영한다.

## Current Constraints

현재 구조는 단일 runtime 전제가 강하다.

- `Symphony.orchestrator`, `Symphony.tracker`, `Symphony.workflow_store`가 전역 singleton처럼 동작한다.
- 설정 로딩은 `WORKFLOW.md` 중심이다.
- 대시보드는 현재 runtime 하나의 snapshot만 표시한다.
- tracker 구현은 `Trackers::Base` 기반으로 잘 분리되어 있으나, 멀티-workflow lifecycle을 수용하는 상위 계층은 없다.

관련 주요 파일:

- `app/models/symphony.rb`
- `app/models/symphony/service_config.rb`
- `app/models/symphony/orchestrator.rb`
- `app/models/symphony/trackers/base.rb`
- `app/controllers/symphony/dashboard_controller.rb`
- `app/views/symphony/dashboard/show.html.erb`

## Recommended Direction

권장안은 "콘솔용 관리 도메인을 추가하고, 기존 orchestrator를 workflow 단위 runtime으로 감싸는 점진 확장"이다.

이 방향은 다음 이유로 적절하다.

- 기존 tracker adapter 패턴을 유지할 수 있다.
- 현재 orchestrator 로직을 전부 버리지 않아도 된다.
- 멀티-프로젝트 요구사항에 맞는 엔티티 경계를 새로 세울 수 있다.
- `database` tracker와 외부 tracker를 같은 콘솔 아래에 통합할 수 있다.

## Domain Model

최소 관리 엔티티:

- `Project`
  - 콘솔에서 관리하는 상위 단위
  - 이름, slug, 상태
- `Workflow`
  - project 소속 실행 단위
  - tracker kind, agent kind, 실행 설정, 활성 여부
- `TrackerConnection`
  - 외부 tracker 연결 정보
  - endpoint, auth reference, 외부 project/repo 식별자
- `AgentConnection`
  - workflow별 agent 연결 정보
  - agent kind (codex, claude_code 등), command, 설정
- `ManagedIssue`
  - `database` tracker의 내부 이슈 원장
- runtime persistence
  - 실행 중/재시도/usage/snapshot 계열 저장소

핵심 원칙:

- 관리용 원장과 실행 상태 저장소를 분리한다.
- 외부 tracker 원본과 내부 runtime bookkeeping을 같은 테이블에 섞지 않는다.

## Tracker Model

tracker는 공통 인터페이스 + capability 기반으로 확장한다.

공통 capability:

- candidate issues 조회
- issue 상태 조회
- 수동 refresh

선택 capability:

- issue 생성
- issue 수정
- 상태 변경
- 라벨/코멘트 변경

예상 tracker별 역할:

- `database`: full CRUD + 상태 변경
- `linear`: 조회/동기화 우선, mutation은 후속 검토
- `github`: 조회/동기화 우선, mutation은 별도 판단

UI는 tracker kind 하드코딩보다 capability 기반 분기를 우선한다.

## Agent Model

agent도 tracker와 마찬가지로 workflow별로 다를 수 있다.

현재는 Codex(codex-rs) 전용이지만, 멀티-프로젝트에서는:

- 프로젝트 A: Codex (JSON-RPC over stdio)
- 프로젝트 B: Claude Code (CLI subprocess)
- 프로젝트 C: 다른 에이전트

기존 `Agents::Base` 어댑터 패턴은 유지하되, agent 설정(command, timeout, approval policy 등)을 `ServiceConfig` 전역이 아니라 workflow/project 단위로 관리한다.

## Trigger Model

현재는 poll 기반(sleep → tick 루프)이다.

멀티-프로젝트로 가면 workflow 수 × poll interval의 부하가 커지므로, webhook 수신을 방향으로 고려한다.

- `linear`: webhook → workflow 식별 → 즉시 tick
- `github`: webhook → workflow 식별 → 즉시 tick
- `database`: 콘솔 UI에서 직접 생성 시 즉시 tick
- fallback: poll은 webhook 누락 대비 보조 수단으로 유지

webhook 수신은 Rails controller endpoint로 자연스럽게 구현 가능하다. 초기에는 poll만으로 시작하되, 스키마와 runtime manager 설계 시 webhook trigger를 수용할 여지를 남긴다.

## Runtime Architecture

목표 구조:

- `Admin Console`
- `WorkflowRuntimeManager`
- workflow별 `Orchestrator`
- workflow별 `Tracker`

즉, 전역 singleton runtime 대신 workflow 단위 runtime registry가 필요하다.

상위 manager 책임:

- 활성 workflow 목록 관리
- workflow별 orchestrator 인스턴스 lifecycle 관리
- snapshot 집계
- start/stop/reload/refresh 같은 운영 명령 전달

## Console Information Architecture

전역 콘솔:

- 프로젝트 목록
- workflow health
- retry pressure
- token usage
- tracker sync 오류

프로젝트 화면:

- workflow 목록
- tracker 연결 상태
- 최근 실행 이력

workflow 화면:

- issue 목록
- runtime 상태
- retry queue
- 수동 refresh / start / stop
- 설정 편집

issue 화면:

- 공통 상세 정보
- tracker capability에 따른 편집 또는 읽기 전용 화면

완료 작업 리뷰:

- agent 실행 결과 요약 (성공/실패, token usage, 소요 시간)
- 생성된 PR 링크, diff 요약
- 재실행 / 수동 개입 액션

## Completion Pipeline

agent가 작업을 완료한 뒤의 output 흐름을 정의한다.

현재는 orchestrator가 worker exit만 처리하고 끝나지만, 멀티-프로젝트 콘솔에서는:

- PR 생성 여부 확인 및 링크 수집
- tracker 상태 업데이트 (완료/리뷰 대기 등)
- 알림 발송 (webhook, Slack 등)
- 콘솔 리뷰 큐에 결과 표시

초기에는 콘솔 내 결과 표시만으로 시작하고, tracker 상태 업데이트와 알림은 후속 확장한다.

## Access Control

멀티-프로젝트 콘솔이 되면 접근 제어가 필요해진다.

초기에는 단일 사용자/셀프호스팅 전제로 인증 없이 시작한다. 단, 스키마 설계 시 향후 확장 여지를 남긴다:

- Project/Workflow에 owner 또는 team 참조 가능한 구조
- 콘솔 접근 시 인증 미들웨어 삽입 지점 확보

팀 사용 시나리오가 구체화되면 별도 설계한다.

## Phased Delivery

### Phase 1: Data Model

- `Project`, `Workflow`, `TrackerConnection`, `ManagedIssue` 스키마 설계
- 기존 runtime persistence 테이블과 역할 분리
- DB 기반 설정을 읽는 config 계층 설계

### Phase 2: Runtime Multiplexing

- singleton 지점 식별 및 workflow 단위 runtime manager 도입
- workflow scope snapshot / refresh / control API 설계

### Phase 3: Tracker Expansion

- `database` tracker 도입
- `github` tracker 추가
- capability 모델 정리

### Phase 4: Admin UI

- 프로젝트/워크플로 CRUD
- workflow 운영 대시보드
- `database` tracker 이슈 CRUD
- 외부 tracker 연결 상태 화면

### Phase 5: Operations and Docs

- 수동 refresh / retry 관찰 / start-stop 제어
- 운영 가이드와 README를 DB 기반 관리 모델에 맞게 업데이트

## Risks

- 현재 singleton 구조를 억지로 유지하면 멀티-프로젝트 요구사항과 충돌한다.
- `symphony_issues`를 내부 tracker 원장으로 재사용하면 의미 충돌이 커진다.
- 외부 tracker write 기능을 초기에 과도하게 넣으면 capability 설계가 흐려진다.
- workflow 설정을 DB로 옮기면 reload, validation, credential 관리 경계도 함께 재정의해야 한다.
- webhook 수신을 도입하면 인증/검증(signature verification) 경계가 생긴다.
- agent 어댑터를 workflow별로 다르게 두면 설정/credential 조합이 복잡해진다.

## Open Decisions

- `ManagedIssue`를 별도 테이블로 둘지, 기존 테이블을 확장할지
- credential 저장 방식을 어떻게 둘지
- workflow start/stop을 web 요청에서 직접 할지, job/manager를 경유할지
- 외부 tracker mutation 범위를 1차 릴리스에 포함할지
- agent 완료 후 PR 생성/tracker 상태 업데이트를 자동화할 범위
- webhook trigger를 어느 phase에서 도입할지
- 접근 제어가 필요해지는 시점과 인증 방식

## Session Recommendation

이 설계를 기준으로 실제 구현을 시작할 때는 새 세션으로 전환하는 편이 낫다.

이유:

- 현재 대화는 문제 정의와 방향 결정에 집중되어 있다.
- 다음 단계는 스키마 설계, singleton 제거 범위 분석, 구현 순서화가 필요하다.
- 새 세션에서 이 문서를 기준으로 implementation plan을 작성하면 문맥이 더 선명해진다.

단, 여기서 추가 설계 질문 몇 개만 더 정리할 생각이면 현재 세션을 이어가도 무방하다.
