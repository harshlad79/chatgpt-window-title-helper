# Platform and Feature Constraints

## Windows window constraints

- 하나의 `ChatGPT.exe` 프로세스가 여러 최상위 창을 가질 수 있으므로 PID가 아니라 HWND를 관리 키로 사용한다.
- `MainWindowHandle`은 프로세스 전체의 대표 핸들이거나 0일 수 있으므로 창 목록 탐색 기준으로 사용하지 않는다.
- HWND는 창 수명 동안만 유효하며, 창이 닫힌 뒤 같은 값이 재사용될 수 있다.
- 창 제목은 식별자나 안정적인 키로 사용하지 않는다. Alt+Tab 제목 변경으로 값이 바뀔 수 있다.
- 최소화된 창은 오버레이를 표시하지 않지만, 이미 확보한 Alt+Tab 제목 상태는 유지할 수 있어야 한다.

## UI Automation constraints

- UIA 호출은 WinForms UI 스레드에서 실행하지 않는다.
- UIA 요소는 동적으로 생성·소멸할 수 있으며, 이전에 얻은 요소가 `ElementNotAvailableException`을 일으킬 수 있다.
- UIA 호출 중간 취소는 보장되지 않는다. 이동 중인 작업은 끝난 뒤 결과를 폐기하는 방식으로 처리한다.
- UIA 결과에는 자동으로 애플리케이션의 업무 대상 HWND가 붙지 않으므로, 요청 시 HWND와 작업 순번을 함께 보관해야 한다.
- UIA 구조의 `BoundingRectangle`은 화면 좌표이고, 오버레이 재배치에는 대상 HWND 좌상단 기준 상대좌표가 필요하다.

## Overlay constraints

- 오버레이는 포커스를 가져오거나 대상 창을 전경으로 만들면 안 된다.
- 오버레이는 마우스 입력을 가로채면 안 된다.
- 오버레이 자체가 Alt+Tab이나 작업표시줄 항목으로 나타나면 안 된다.
- UIA 탐색 실패 시 좌표를 화면 좌상단 등 임의 위치로 초기화하지 않고, 마지막 성공 좌표를 유지한다.
- 제목이 이미 SectionHeader 내부 버튼에 표시되는 창에는 오버레이를 추가하지 않는다.

## Build and repository constraints

- 대상은 Windows x64다.
- 소스 빌드에는 .NET 8 SDK x64가 필요하다.
- 배포본은 self-contained single-file EXE를 사용해 사용자별 .NET Runtime 설치를 요구하지 않는다.
- `artifacts/`, `.dotnet-cli/`, `bin/`, `obj/`는 저장소에 포함하지 않는다.
- 로그와 로컬 설정은 저장소에 포함하지 않고 사용자 LocalAppData에 둔다.

