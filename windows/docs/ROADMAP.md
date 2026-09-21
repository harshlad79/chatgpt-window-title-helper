# Roadmap

## v1 — 현재 기준

- 다중 ChatGPT HWND 탐색
- 창별 UIA 제목 탐색
- SectionHeader 기반 제목 오버레이
- Alt+Tab 제목 변경 옵션
- 트레이 설정과 종료 메뉴
- 창별 UIA 중복 실행 방지
- Windows x64 self-contained .NET 8 배포

## v2 — 다음 구현 단계

- 창 이동·크기 변경 중 UIA 신규 작업 보류
- 이동 중 기존 상대좌표 기반 오버레이 추적
- 이동 종료 후 안정화 뒤 해당 창만 UIA 재탐색
- generation 기반 오래된 결과 무효화
- 이동·크기 변경 및 UIA 상태 진단 개선

## 이후 검토

- UIA 구조 변경 이벤트 활용 가능성 재검토
- polling 빈도와 안정화 지연시간 튜닝
- ChatGPT 앱 업데이트별 UIA 구조 호환성 점검
- 배포·설치 편의 개선

