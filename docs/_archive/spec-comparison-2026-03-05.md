# Symphony SPEC 대비 구현 비교 (2026-03-05)

## 범위

- 기준 문서: `SPEC.md`
- 대상 구현: 현재 `rails-symphony` 코드베이스
- 검증 방식: 코드 대조 + 테스트 실행 + 외부 레퍼런스 교차검증

## 최종 판정 요약 (재검증 반영)

- 전체: **대부분 충족 (Largely Conformant)**
- 반영 완료: 워크플로 reload 에러 게이팅, runtime 재적용, retry 의미론 보강, token delta 집계, Linear pagination integrity, CLI 플래그 파싱
- 잔여 리스크: 워커 중단은 PID 기반 best-effort(`TERM`)이고, 전체 테스트 병렬 실행에서 기존 persistable 계열 간헐 실패가 드물게 재현됨

## 섹션별 비교

| SPEC 섹션 | 상태 | 근거 구현 | 비고 |
|---|---|---|---|
| 5 Workflow contract | 충족에 가까움 | `app/models/symphony/workflow.rb`, `app/models/symphony/workflow_store.rb`, `app/models/symphony/orchestrator.rb`, `app/models/symphony/prompt_builder.rb` | strict render/파싱 + reload 오류 시 dispatch preflight 차단 반영 |
| 6 Configuration / reload | 충족에 가까움 | `app/models/symphony/service_config.rb`, `app/models/symphony/workflow_store.rb`, `app/models/symphony/orchestrator.rb`, `app/models/symphony/workspace.rb`, `app/models/symphony/trackers/linear.rb` | tick 시 runtime config 재적용 + bare relative workspace root 보존 반영 |
| 7 State machine | 부분 충족 | `app/models/symphony/orchestrator.rb`, `app/jobs/symphony/agent_worker_job.rb` | 상태 전이/클레임/재시도는 정합. 워커 중단은 PID 기반 best-effort |
| 8 Polling / retry / reconciliation | 충족에 가까움 | `app/models/symphony/orchestrator.rb` | retry fetch 실패 재큐잉, 슬롯 부족 attempt 증가 반영 |
| 9 Workspace safety | 충족에 가까움 | `app/models/symphony/workspace.rb` | sanitize, root containment, hook timeout/실패 처리 구현 |
| 10 Agent protocol | 충족에 가까움 | `app/models/symphony/agents/codex.rb`, `app/models/symphony/agent_runner.rb` | handshake 순서 부합 + prompt render 실패 구조화 처리 반영 |
| 11 Linear integration | 충족에 가까움 | `app/models/symphony/trackers/linear.rb` | slug filter/[ID!] refresh/pagination + missing endCursor integrity check 반영 |
| 13.7 Optional HTTP extension | 부분 충족 | `config/routes.rb`, `app/controllers/api/v1/*`, `bin/symphony` | API 표면은 유지. CLI 플래그 선행 파싱 보강 반영 |
| 17~18 Conformance & lifecycle | 부분 충족 | `test/conformance/*`, `test/models/symphony/*`, `test/integration/*` | 다수 conformance 성격 테스트 존재 |

## 확인된 핵심 갭 (재검증 후)

아래 1~9 항목은 이번 패치에서 반영 완료됨.

1. **Workflow 불량 상태에서 dispatch gating 불완전** (해결)
   - 파일: `app/models/symphony/workflow_store.rb`, `app/models/symphony/orchestrator.rb`
   - 현상: reload 실패 시 마지막 정상 config 유지 후 dispatch 지속 가능

2. **동적 리로드가 workspace/hook/tracker 인스턴스에 전파되지 않음** (해결)
   - 파일: `app/models/symphony.rb`, `app/models/symphony/workspace.rb`
   - 현상: `WORKFLOW.md` 변경 후에도 boot 시점 객체가 계속 사용됨

3. **`workspace.root` bare 문자열 보존 규칙 불일치 가능성** (해결)
   - 파일: `app/models/symphony/service_config.rb`
   - 현상: `File.expand_path`로 항상 절대경로화

4. **Retry timer 실패/슬롯 부족 시 의미론 차이** (해결)
   - 파일: `app/models/symphony/orchestrator.rb`
   - 현상: fetch 실패 시 release, 슬롯 부족 시 attempt 증가 누락 가능

5. **Reconciliation에서 실제 실행 중 워커 강제 중단 경로 미흡** (부분 해결)
   - 파일: `app/models/symphony/orchestrator.rb`, `app/jobs/symphony/agent_worker_job.rb`

6. **Prompt render 예외가 오케스트레이터 실패 처리 경로를 우회 가능** (해결)
   - 파일: `app/models/symphony/prompt_builder.rb`, `app/models/symphony/agent_runner.rb`, `app/jobs/symphony/agent_worker_job.rb`

7. **Token accounting이 absolute-total delta 규칙과 불일치 가능성** (해결)
   - 파일: `app/models/symphony/orchestrator.rb`

8. **Linear pagination integrity (`hasNextPage=true` + `endCursor` 없음) 검증 부족** (해결)
   - 파일: `app/models/symphony/trackers/linear.rb`

9. **CLI 인자 파싱 edge case (`--port` 선행) 처리 취약** (해결)
  - 파일: `bin/symphony`

## 잔여 관찰 사항

1. **워크커 강제 중단은 best-effort**
   - 현재는 `codex_app_server_pid`가 알려진 경우 `TERM` 시그널을 요청하는 방식이며, 잡 레벨 취소/보장 중단까지는 아님.

2. **전체 테스트 병렬 실행의 간헐 실패**
   - `test/models/symphony/orchestrator_persistable_test.rb` 계열이 병렬 실행에서 간헐적으로 실패 가능.
   - 단일 워커(`PARALLEL_WORKERS=1`)에서는 안정적으로 통과.

## 테스트 검증 로그 (패치 후)

- 실행: `bin/rails test test/conformance test/models/symphony test/controllers/api/v1 test/integration/symphony_e2e_test.rb`
  - 결과: 통과 (`123 runs`, `0 failures`, `0 errors`)
- 실행: `bin/rails test` (병렬)
  - 결과: 간헐적으로 `orchestrator_persistable` 계열 1건 실패 재현
- 실행: `PARALLEL_WORKERS=1 bin/rails test`
  - 결과: 통과 (`125 runs`, `0 failures`, `0 errors`)

## 외부 교차검증 메모

- Codex app-server: handshake 순서(`initialize -> initialized -> thread/start -> turn/start`)는 구현과 정합
- Linear GraphQL: project slug 필터/ID refresh/pagination 기본형은 정합, pagination integrity 에지 검증 강화 필요

## 결론 (재검증 반영)

현재 구현은 SPEC 목표와 구조를 전반적으로 충실히 따르고 있으며, 기존 핵심 conformance 갭 대부분이 이번 패치로 해소되었다. 남은 이슈는 "중단 보장 수준"과 "병렬 테스트 안정성" 성격이므로, 다음 단계는 강제 중단 경로 고도화와 persistable 테스트의 병렬 안전성 보강이다.
