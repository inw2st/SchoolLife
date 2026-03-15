# SchoolLife

학교 급식, 시간표, 학사일정을 한곳에서 확인하려고 만든 iOS 앱.  
아이폰 앱을 중심으로 홈 화면 위젯과 Apple Watch 화면도 함께 구성됨.

## 구성

- iPhone 앱
- iOS 위젯
- Apple Watch 앱
- Apple Watch 위젯

## 현재 기능

### 급식

- 급식 탭에서 오늘 포함 이후 3일간의 급식 확인
- 조식, 중식, 석식을 날짜별로 묶어서 표시
- iOS 위젯에서는 오늘 중식 표시
- Apple Watch 앱과 워치 위젯에서 오늘 급식 확인

### 시간표

- 날짜를 바꿔서 시간표 조회
- 시간표 소스를 교육청 API 또는 컴시간 중에서 선택
- 학년, 반을 바로 바꿔서 확인 가능
- 시간표 항목 직접 수정
- 수정 범위를 오늘만, 같은 요일 전체, 같은 과목명 전체 치환으로 선택 가능
- 수정사항 내보내기, 불러오기, 범위별 초기화 지원
- iOS 위젯과 Apple Watch에서 오늘 시간표 확인

### 학사일정

- 학사일정 탭에서 월별 일정 확인
- 선택한 날짜의 일정 목록 표시

### 설정

- 학교 검색 및 변경
- 학년/반 변경
- 다크 모드 전환
- App Group 및 서명 관련 디버그 정보 확인

## 사용한 것

- Swift
- SwiftUI
- WidgetKit
- WatchConnectivity
- App Groups
- NEIS Open API
- 컴시간 연동용 중계 서버

## 화면

<details>
<summary>학교 찾기</summary>
<br>
<img width="280" alt="학교 찾기" src="https://github.com/user-attachments/assets/70fd05e0-040d-4308-b69c-8bf9ec30ed42" />
</details>

<details>
<summary>급식 탭</summary>
<br>
<img width="280" alt="급식 탭" src="https://github.com/user-attachments/assets/c11d2774-5098-4c78-b74e-ca4d27630c1c" />
</details>

<details>
<summary>시간표 탭</summary>
<br>
<img width="280" alt="시간표 탭" src="https://github.com/user-attachments/assets/c1790a26-7099-4f3b-8e8a-cb732af891df" />
</details>

<details>
<summary>시간표 편집</summary>
<br>
<img width="280" alt="시간표 편집" src="https://github.com/user-attachments/assets/63b6690f-dcdd-4313-82f2-b2a60fcde92b" />
</details>

<details>
<summary>설정</summary>
<br>
<img width="280" alt="설정" src="https://github.com/user-attachments/assets/1b51bff7-45a7-4cb4-8299-bb9257ef4430" />
</details>

<details>
<summary>디버그 정보</summary>
<br>
<img width="280" alt="디버그 정보" src="https://github.com/user-attachments/assets/3c715270-615c-4324-b202-abeddf6008d1" />
</details>

<details>
<summary>위젯</summary>
<br>
<img height="500" alt="위젯" src="https://github.com/user-attachments/assets/d0b4f301-fc55-4c7e-8cad-52670c5cf709" />
</details>

## 참고

- 급식과 학사일정은 교육청 API를 사용함.
- 시간표는 교육청 API 또는 컴시간 중에서 선택할 수 있음.
- 주말에는 컴시간 기준 시간표가 비어 있도록 처리되어 있음.

