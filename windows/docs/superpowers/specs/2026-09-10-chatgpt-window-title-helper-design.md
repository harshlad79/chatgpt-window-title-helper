# ChatGPT Window Title Helper 설계

## 목표

Windows ChatGPT 데스크톱 앱의 여러 최상위 창을 HWND 단위로 추적하고, UI Automation에서 현재 대화 제목을 읽어 오버레이와 Alt+Tab 창 제목에 표시한다.

## 확정된 전제

- 프로세스 후보는 `ChatGPT.exe`이며 설치 경로는 WindowsApps 아래일 수 있다.
- 하나의 PID가 여러 ChatGPT 창을 가질 수 있으므로 PID가 아니라 HWND를 관리 키로 사용한다.
- 실제 창은 `Chrome_WidgetWin_1`일 가능성이 높지만, 클래스명만으로 확정하지 않고 UIA 루트 검증을 추가한다.
- 현재 대화는 `AriaProperties`에 `current=page`가 포함된 요소로 판별한다.
- 해당 요소의 `Name`을 제목으로 사용한다.

## 구조

### WindowDiscovery

Win32 `EnumWindows`로 최상위 HWND를 열거하고, 소유 PID의 프로세스명이 `ChatGPT`인 후보만 남긴다. 보조 창·IME·DDE·트레이 창은 최상위/가시성/클래스 및 UIA 루트 검증으로 제외한다. 창 수명은 주기적으로 재검색해 생성·종료를 반영한다.

### ConversationTitleReader

각 HWND의 UIA 루트에서 `AriaProperties` 조건을 만족하는 요소를 탐색하고 `Name`을 반환한다. 성공한 마지막 제목을 캐시한다. 순간적인 UIA 실패나 빈 제목은 마지막 정상 제목을 유지하며, 최초 값이 없으면 `ChatGPT`를 사용한다.

### ChangeDetection

가능하면 UIA PropertyChanged/StructureChanged 이벤트를 사용한다. 이벤트 연결 또는 수신이 불안정하면 창별 `1000ms` polling을 fallback으로 사용한다. 전체 트리의 불필요한 반복 탐색을 피하고 제목이 실제로 바뀐 창만 갱신한다.

### OverlayWindow

창마다 비활성·포커스 불가·클릭 통과·Alt+Tab/작업표시줄 제외 스타일의 작은 오버레이를 소유한다. Windows non-client metrics에서 시스템 제목 글꼴과 DPI를 읽고, 투명 배경·한 줄 말줄임 제목을 사용한다. 대상 HWND의 위치·크기·최대화·복원·모니터·DPI 변경에 따라 재배치한다. 대상 창이 사라지면 오버레이를 제거한다.

### WindowTitleWriter

옵션이 켜진 경우 `<제목> - ChatGPT`를 대상 HWND의 Window Text에 적용한다. `2000ms`마다 확인하되 값이 바뀐 경우에만 재적용한다. 창 식별에는 제목을 사용하지 않는다. 종료 시 저장한 원래 제목을 복원한다.

### TrayApplication

WinForms `NotifyIcon` 기반 단일 인스턴스 앱으로 구현한다. 메뉴는 `Status`, `Show Conversation Title`, `Change Alt+Tab Title`, `Exit`로 구성한다. 두 표시 옵션은 기본 ON이며 `%LocalAppData%\\ChatGPTWindowTitleHelper\\settings.json`에 저장한다. 설정 손상 시 기본값으로 복구한다.

## 데이터 흐름

`EnumWindows → HWND 추적 → UIA 제목 읽기 → 제목 캐시 → Overlay/Window Text 갱신`

창 종료, UIA 요소 소멸, ChatGPT 재실행, 구조 변경은 예외를 앱 종료로 전파하지 않고 해당 창을 재탐색한다.

## 국제화

.NET 문자열은 Unicode로 처리하고 JSON은 UTF-8로 저장한다. 오버레이는 시스템 글꼴을 우선 사용하고 Windows 글꼴 fallback에 맡긴다. 애플리케이션에 대형 범용 폰트를 번들하지 않는다.

## 검증 기준

- 같은 PID의 4개 HWND를 독립적으로 추적한다.
- 각 창에서 서로 다른 현재 대화 제목을 읽는다.
- 대화 변경 후 최대 polling 주기 내 제목이 갱신된다.
- 오버레이가 입력·포커스·Alt+Tab을 방해하지 않는다.
- 최소화·복원·이동·DPI 변경·다중 모니터에서 정상 동작한다.
- ChatGPT 종료·재실행·UIA 일시 실패에도 프로세스가 죽지 않는다.
- x64 self-contained single-file EXE를 생성한다.

## 범위 제외

DOM 수정, injection, OCR, 이미지 인식, 마우스·키보드 자동화, 사이드바 자동 열기, 수동 제목 입력, 복잡한 설정 화면, 자동 업데이트, 설치 프로그램은 구현하지 않는다.
