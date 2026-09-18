# Wellscore — NAD+ 자가검사 웰니스 서비스

DBS(건조혈액반점) 방식으로 진행하는 NAD+ 자가검사 웰니스 서비스의 웹사이트입니다.
프론트엔드는 순수 HTML/CSS/JS(빌드 과정 없음)이고, 회원/결제/신청/리포트 데이터는 **Supabase**(Postgres + Auth)와 실제로 연동되어 있어요.

브랜드명 "Wellscore"는 임시 제안명이에요. 정식 출시 전에는 상표/사업자명 중복 여부를 별도로 확인해주세요.

## ⚠️ 배포 전에 꼭 하셔야 하는 일

**`SUPABASE_SETUP.md`를 먼저 읽고 그대로 따라해주세요.** Supabase 프로젝트에 테이블/보안정책을 만드는 SQL을 실행하지 않으면 회원가입 자체가 동작하지 않아요. 관리자 계정 만드는 방법도 거기 있어요.

## 폴더 구조

```
wellscore-wellness/
├── index.html            홈
├── about-nad.html         NAD+ 및 DBS 검사 상세 소개
├── store.html             검사 키트(검사권) 구매
├── checkout.html          결제 — 토스페이먼츠 결제위젯 연동
├── checkout-success.html  결제 성공 시 토스페이먼츠가 돌아오는 페이지
├── checkout-fail.html     결제 실패/취소 시 토스페이먼츠가 돌아오는 페이지
├── signup.html            회원가입 (Supabase Auth)
├── login.html             로그인 (Supabase Auth)
├── mypage.html            마이페이지 — 로그인 필요
├── kit-request.html       검사권으로 키트 배송 신청 — 로그인 필요
├── report.html            검사 리포트 — 관리자가 입력한 실제 결과 또는 예시 데이터
├── admin-login.html       (구버전 관리자 로그인 — login.html로 안내 후 리다이렉트)
├── admin-dashboard.html   관리자 대시보드 — role이 admin인 계정만 접근 가능
├── 404.html
├── supabase-schema.sql    Supabase에 실행할 테이블/보안정책 스크립트
├── SUPABASE_SETUP.md      Supabase 설정 단계별 가이드 (꼭 읽어주세요)
└── README.md
```

각 HTML 파일은 CSS가 전부 파일 안에 내장된 독립 실행 파일이에요. 다만 이제 실제 데이터 조회를 위해 인터넷 연결과 Supabase 프로젝트 설정이 필요해서, **`index.html`을 그냥 더블클릭해서 열어도 로그인·회원가입 등 데이터 관련 기능은 동작하지 않아요** (디자인만 확인 가능). 실제 동작 확인은 배포 후 진행해주세요.

## 아키텍처 요약

- **인증**: Supabase Auth (이메일/비밀번호). 비밀번호는 Supabase가 안전하게 저장해요.
- **회원 정보**: `profiles` 테이블 (이름, 연락처, 생년월일, 성별, 주소, 보유 검사권 수, 권한(`role`))
- **구매/신청/결과**: `purchases`, `requests`, `reports` 테이블
- **보안**: Row Level Security로 "본인 데이터만" 접근 가능하고, `role = 'admin'`인 계정만 전체 데이터에 접근 가능해요. 검사권 개수나 신청 상태처럼 중요한 값은 클라이언트가 직접 바꾸지 못하고, 정해진 함수(RPC)를 통해서만 바뀌도록 설계했어요.
- **결제**: 토스페이먼츠 결제위젯(SDK v2), 테스트 클라이언트 키 사용 중

## 관리자 페이지

- 사이트 안에는 관리자로 가는 링크가 없어요. `/admin-dashboard.html`로 직접 접속해야 해요.
- 로그인은 일반 회원과 동일하게 `/login.html`에서 하고, 그 계정의 `role`이 `admin`이어야 대시보드를 볼 수 있어요. (설정 방법은 `SUPABASE_SETUP.md` 참고)
- 더 강하게 막고 싶다면 Cloudflare Access로 `/admin*` 경로 자체를 보호하는 걸 추천드려요 (역시 `SUPABASE_SETUP.md`에 방법 있어요).

## 리포트: 동년배 퍼센타일 방식

"낮음/보통/최적" 같은 건강 상태를 암시하는 표현 대신, **"동일한 분석 방법으로 측정한 동년배 그룹 대비 상위/하위 %"** 만 보여줘요. 연령대별 참고분포(평균/표준편차)는 `js` 코드 안 `NAD_REFERENCE`에 있는데, 이건 실제 임상 데이터가 아닌 예시값이에요 — 논문 등 공개 자료나 자체 축적 데이터로 교체하는 걸 추천드려요.

## 비의료 서비스 안내 문구

"본 서비스는 비의료 건강관리 서비스로, 질병을 진단·예방·치료하기 위한 의료행위가 아닙니다"라는 문구를 홈/NAD+ 소개/구매/결제/리포트 페이지에 명시해뒀어요.

## ⚠️ 아직 남아있는 한계 (꼭 읽어주세요)

- **토스페이먼츠 결제 승인이 서버에서 검증되지 않아요.** 결제창에서 성공 신호가 오면 바로 검사권을 지급해요. 실제로는 서버(Supabase Edge Functions 등)에서 토스 결제 승인 API(시크릿 키 필요)를 호출해 검증한 뒤에만 지급해야, 결제 없이 검사권을 받는 걸 막을 수 있어요. 관련 주석을 `checkout-success.html`에 남겨뒀어요.
- **키트 바코드/고유 ID 체계가 없어요.** 실제 물리적 키트와 검사기관 결과를 연결하려면 바코드가 필요해요 (이전에 안내드린 파이프라인 참고).
- **관리자가 결과를 직접 입력해요.** 검사기관과 자동으로 데이터를 주고받는 연동은 별도 구축이 필요해요.
- **가격 할인 표시, 비의료 서비스 문구**가 관련 법규에 맞는지, **브랜드명 상표 중복 여부**를 실제 출시 전에 확인해주세요.

## 미리보기 (로컬)

디자인만 보시려면 `index.html`을 더블클릭해서 여시면 돼요. 회원가입/로그인 등 실제 데이터 기능을 테스트하시려면 아래처럼 배포 후 확인해주세요.

## Cloudflare Pages로 배포하기

### 방법 A. 대시보드에서 드래그 앤 드롭 (가장 쉬움)

1. **먼저 `SUPABASE_SETUP.md`의 1단계(SQL 실행)를 완료하세요.**
2. [Cloudflare 대시보드](https://dash.cloudflare.com) → **Workers & Pages**
3. **Create application → Pages → Use direct upload**
4. 프로젝트 이름 입력 후 **Create project**
5. 이 폴더(또는 zip) 전체를 드래그 앤 드롭 → **Deploy site**

### 방법 B. Wrangler CLI

```bash
npm install -g wrangler
npx wrangler pages deploy ./wellscore-wellness --project-name=wellscore-wellness
```

## 다음 단계로 고려해볼 것들

- 토스페이먼츠 결제 승인을 서버(Supabase Edge Functions)에서 검증하도록 개선
- 키트 바코드/고유 ID 체계 도입
- 연령대별 NAD+ 참고분포를 실제 데이터로 교체
- 브랜드명 상표/사업자명 중복 여부 정식 확인
- 토스페이먼츠 실제 상점 가입 및 정식 키 발급
- 통신판매업 신고, 사업자 정보 등 법적 표기사항
- 개인정보 처리방침 · 이용약관 문서화 (민감정보 처리 관련)
- 글루타치온 검사 추가 시: `about-nad.html` 구조 참고해 페이지 추가
