# Supabase 연동 설정 가이드

이 사이트는 실제 데이터베이스(Supabase)와 연동되어 있어요. 배포 전에 **아래 단계를 Supabase 대시보드에서 직접** 진행해주셔야 해요. 코드는 이미 다 반영되어 있어서, 여기 나온 설정만 해주시면 바로 동작해요.

이미 알려주신 정보로 `js` 코드에 아래 값이 들어가 있어요.
- Project URL: `https://mezymmondxgyffpzhfum.supabase.co`
- Publishable key: `sb_publishable_KoEuCz0bpo06Cgn0juXldg_6Smnyc5w` (브라우저에 노출되어도 안전한 키예요. RLS로 접근을 제한해요)

---

## 1단계. 데이터베이스 스키마 만들기 (또는 업데이트하기)

[Supabase 대시보드](https://supabase.com/dashboard) → 해당 프로젝트 선택 → 왼쪽 메뉴 **SQL Editor** → **New query**

### 처음 새로 세팅하는 경우
- `supabase-schema.sql` 파일 내용을 전체 복사해서 붙여넣고 **Run** 실행.

### 이미 이전 버전 스키마를 실행해 둔 경우 (기존 데이터 유지)
- `update-schema.sql` 파일 내용을 전체 복사해서 붙여넣고 **Run** 실행.
- 반송 상태(`반송신청`, `반송중`), 배송 및 반송 송장 컬럼, 사용자 직접 반송 신청 RPC, 배송/반송 관리자 RPC, 회원 탈퇴 RPC가 자동으로 추가/적용됩니다.

---

## 2단계. 이메일 확인(Confirm email) 설정 정하기

**Authentication → Providers → Email**에서 "Confirm email" 옵션을 확인해주세요.

- **켜두면(기본값, 실제 서비스 추천)**: 가입 후 이메일의 확인 링크를 눌러야 로그인할 수 있어요. 사이트에는 이미 "가입 확인 메일을 보내드렸어요" 안내가 뜨도록 만들어뒀어요.
- **꺼두면(테스트에 편함)**: 가입하자마자 바로 로그인 상태로 시작해요. 지금 빠르게 테스트해보시려면 잠시 꺼두셔도 괜찮아요.

---

## 3단계. 관리자 계정 만들기

관리자 계정도 회원가입과 똑같은 절차를 거쳐요. 최초 1명은 아래처럼 수동으로 승격해줘야 해요.

1. 배포된 사이트에서 관리자로 쓸 이메일로 **일반 회원가입**을 평소처럼 진행해요 (`/signup.html`).
2. Supabase **SQL Editor**에서 아래 쿼리를 실행해요 (이메일만 본인 것으로 바꿔서):

```sql
update public.profiles
set role = 'admin'
where id = (select id from auth.users where email = '본인의관리자이메일@example.com');
```

3. 이제 그 계정으로 `/login.html`에서 로그인한 뒤 `/admin-dashboard.html`로 들어가면 관리자 화면이 보여요.

관리자 페이지 접근 링크는 사이트 어디에도 노출되어 있지 않아요. 주소를 직접 입력해서 들어가야 하고, 로그인은 했지만 `role`이 `admin`이 아닌 사람이 들어오면 "접근 권한이 없어요"라고만 표시돼요.

---

## 4단계. (선택, 강력 추천) Cloudflare Access로 관리자 경로 추가 보호

지금 상태로도 `admin` 권한이 없으면 데이터를 볼 수 없지만, **로그인 화면 자체는 누구나 접근 가능**해요. 한 단계 더 막고 싶다면:

1. Cloudflare 대시보드 → **Zero Trust → Access → Applications → Add an application → Self-hosted**
2. 도메인은 배포 주소, 경로(Path)는 `/admin*`
3. 정책에서 "이메일이 OO인 사람만 허용" 설정

이렇게 하면 `/admin*` 요청 자체가 Cloudflare 단에서 걸러져서, 허용된 이메일이 아니면 페이지가 뜨지도 않아요.

---

## 배포하기

이제 이 폴더(`wellscore-wellness`)를 그대로 Cloudflare Pages에 배포하면 돼요. 방법은 `README.md`의 "Cloudflare Pages로 배포하기" 항목을 참고해주세요. **1단계(SQL 실행)를 먼저 하지 않으면 회원가입 자체가 실패**하니, 배포 전에 꼭 SQL부터 실행해주세요.
