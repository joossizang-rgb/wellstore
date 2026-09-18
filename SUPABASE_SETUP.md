# Supabase 연동 설정 가이드

이 사이트는 이제 실제 데이터베이스(Supabase)와 연동되어 있어요. 배포 전에 **아래 단계를 Supabase 대시보드에서 직접** 진행해주셔야 해요. 코드는 이미 다 반영되어 있어서, 여기 나온 설정만 해주시면 바로 동작해요.

이미 알려주신 정보로 `js` 코드에 아래 값이 들어가 있어요.
- Project URL: `https://mezymmondxgyffpzhfum.supabase.co`
- Publishable key: `sb_publishable_KoEuCz0bpo06Cgn0juXldg_6Smnyc5w` (브라우저에 노출되어도 안전한 키예요. RLS로 접근을 제한해요)

## 1단계. 데이터베이스 스키마 만들기

1. [Supabase 대시보드](https://supabase.com/dashboard) → 해당 프로젝트 선택
2. 왼쪽 메뉴 **SQL Editor** → **New query**
3. 이 폴더의 `supabase-schema.sql` 파일 내용을 전부 복사해서 붙여넣고 **Run**
4. 에러 없이 완료되면 왼쪽 메뉴 **Table Editor**에서 `profiles`, `purchases`, `requests`, `reports` 4개 테이블이 보이는지 확인해주세요.

이 스크립트가 만드는 것:
- 4개 테이블 (`profiles`, `purchases`, `requests`, `reports`)
- 회원가입 시 `auth.users` → `profiles`를 자동으로 만들어주는 트리거
- 일반 회원이 검사권 개수나 권한을 직접 조작하지 못하게 막는 보호 장치
- 모든 테이블에 대한 보안 정책(RLS): 본인 데이터만 보이고, `admin` 권한인 사람만 전체를 볼 수 있어요
- 검사권 구매/키트 신청/상태 변경/결과 입력을 처리하는 함수 4개 (이 함수들을 통해서만 데이터가 바뀌도록 설계했어요)

## 2단계. 이메일 확인(Confirm email) 설정 정하기

**Authentication → Providers → Email**에서 "Confirm email" 옵션을 확인해주세요.

- **켜두면(기본값, 실제 서비스 추천)**: 가입 후 이메일의 확인 링크를 눌러야 로그인할 수 있어요. 사이트에는 이미 "가입 확인 메일을 보내드렸어요" 안내가 뜨도록 만들어뒀어요.
- **꺼두면(테스트에 편함)**: 가입하자마자 바로 로그인 상태로 시작해요. 지금 빠르게 테스트해보시려면 잠시 꺼두셔도 괜찮아요.

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

## 4단계. (선택, 강력 추천) Cloudflare Access로 관리자 경로 추가 보호

지금 상태로도 `admin` 권한이 없으면 데이터를 볼 수 없지만, **로그인 화면 자체는 누구나 접근 가능**해요. 한 단계 더 막고 싶다면:

1. Cloudflare 대시보드 → **Zero Trust → Access → Applications → Add an application → Self-hosted**
2. 도메인은 배포 주소, 경로(Path)는 `/admin*`
3. 정책에서 "이메일이 OO인 사람만 허용" 설정

이렇게 하면 `/admin*` 요청 자체가 Cloudflare 단에서 걸러져서, 허용된 이메일이 아니면 페이지가 뜨지도 않아요.

## 배포하기

이제 이 폴더(`wellscore-wellness`)를 그대로 Cloudflare Pages에 배포하면 돼요. 방법은 `README.md`의 "Cloudflare Pages로 배포하기" 항목을 참고해주세요. **1단계(SQL 실행)를 먼저 하지 않으면 회원가입 자체가 실패**하니, 배포 전에 꼭 SQL부터 실행해주세요.

## ⚠️ 이 구조에서 여전히 남아있는 한계

Supabase 연동으로 이전보다 훨씬 실제 서비스에 가까워졌지만, 아직 완전하지는 않아요.

- **토스페이먼츠 결제 승인**: 결제창에서 성공 신호가 오면 바로 검사권을 지급해요. 실제로는 서버(예: Supabase Edge Functions)에서 토스 결제 승인 API를 호출해 검증한 뒤에만 지급해야, 결제 없이 검사권을 받는 것을 막을 수 있어요. (`checkout-success.html` 안에 관련 주석을 남겨뒀어요.)
- **바코드/키트 고유 ID**: 실제 물리적 키트와 검사기관 결과를 연결하는 바코드 체계는 아직 없어요. 이전에 안내드린 파이프라인 문서를 참고해주세요.
- **관리자 결과 입력**: 지금은 관리자가 직접 숫자를 입력해요. 검사기관과 데이터를 자동으로 주고받는 연동은 별도로 구축이 필요해요.
