-- ============================================================
-- Wellscore Supabase 스키마
-- Supabase 대시보드 > SQL Editor > New query 에 전체를 붙여넣고
-- Run 버튼 한 번으로 전부 실행하면 됩니다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. profiles 테이블 (auth.users를 확장하는 회원 정보)
-- ------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  phone text not null,
  birthdate date,
  gender text check (gender in ('여성','남성')),
  zonecode text,
  address text,
  address_detail text,
  role text not null default 'customer' check (role in ('customer','admin')),
  voucher_count integer not null default 0,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- ------------------------------------------------------------
-- 2. purchases 테이블 (검사권 구매 내역)
-- ------------------------------------------------------------
create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  qty integer not null,
  amount integer not null,
  created_at timestamptz not null default now()
);
alter table public.purchases enable row level security;

-- ------------------------------------------------------------
-- 3. requests 테이블 (키트 신청 / 배송·검사 상태)
-- ------------------------------------------------------------
create table public.requests (
  id text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default '배송준비중' check (status in ('배송준비중','배송중','검사중','완료')),
  recipient_name text not null,
  recipient_phone text not null,
  zonecode text not null,
  address text not null,
  address_detail text not null,
  created_at timestamptz not null default now()
);
alter table public.requests enable row level security;

-- ------------------------------------------------------------
-- 4. reports 테이블 (검사 결과)
-- ------------------------------------------------------------
create table public.reports (
  request_id text primary key references public.requests(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  value numeric not null,
  percentile integer not null,
  age_group text not null,
  created_at timestamptz not null default now()
);
alter table public.reports enable row level security;

-- ============================================================
-- 5. 회원가입 시 auth.users -> profiles 자동 생성
-- ============================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, name, phone, birthdate, gender, zonecode, address, address_detail)
  values (
    new.id,
    new.raw_user_meta_data ->> 'name',
    new.raw_user_meta_data ->> 'phone',
    nullif(new.raw_user_meta_data ->> 'birthdate', '')::date,
    new.raw_user_meta_data ->> 'gender',
    new.raw_user_meta_data ->> 'zonecode',
    new.raw_user_meta_data ->> 'address',
    new.raw_user_meta_data ->> 'address_detail'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ============================================================
-- 6. 관리자 여부 확인 함수 (RLS 정책에서 재사용, 재귀 방지용)
-- ============================================================
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  );
$$;

-- ============================================================
-- 7. voucher_count / role 보호 트리거
--    (일반 회원이 API로 직접 검사권 개수나 권한을 조작하지 못하게 방지)
-- ============================================================
create or replace function public.protect_profile_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (select public.is_admin()) then
    new.voucher_count := old.voucher_count;
    new.role := old.role;
  end if;
  return new;
end;
$$;

create trigger protect_profile_fields_trigger
before update on public.profiles
for each row execute function public.protect_profile_fields();

-- ============================================================
-- 8. RLS 정책
-- ============================================================

-- profiles: 본인 것만, 관리자는 전체
create policy "profiles_select" on public.profiles for select
  using ( id = auth.uid() or (select public.is_admin()) );
create policy "profiles_update" on public.profiles for update
  using ( id = auth.uid() or (select public.is_admin()) );

-- purchases: 본인 것만 조회/등록, 관리자는 전체 조회
create policy "purchases_select" on public.purchases for select
  using ( user_id = auth.uid() or (select public.is_admin()) );

-- requests: 본인 것만 조회, 관리자는 전체 조회 (등록/상태변경은 아래 함수로만 가능)
create policy "requests_select" on public.requests for select
  using ( user_id = auth.uid() or (select public.is_admin()) );

-- reports: 본인 것만 조회, 관리자는 전체 조회
create policy "reports_select" on public.reports for select
  using ( user_id = auth.uid() or (select public.is_admin()) );

-- ============================================================
-- 9. 상태를 바꾸는 작업은 전부 함수(RPC)로만 — 클라이언트가 직접
--    insert/update 하지 못하게 하고, 검증 로직을 서버(DB)에 둡니다.
-- ============================================================

-- 검사권 구매 (결제 성공 후 호출)
create or replace function public.record_purchase(p_qty integer, p_amount integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if p_qty is null or p_qty < 1 or p_qty > 10 then raise exception '수량이 올바르지 않습니다.'; end if;
  if p_amount is null or p_amount <> p_qty * 30000 then raise exception '결제 금액이 올바르지 않습니다.'; end if;

  insert into public.purchases (user_id, qty, amount) values (auth.uid(), p_qty, p_amount);
  update public.profiles set voucher_count = voucher_count + p_qty where id = auth.uid();
end;
$$;

-- 키트 신청 (검사권 1개 차감)
create or replace function public.record_kit_request(
  p_id text, p_recipient_name text, p_recipient_phone text,
  p_zonecode text, p_address text, p_address_detail text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  select voucher_count into v_count from public.profiles where id = auth.uid();
  if v_count is null or v_count < 1 then
    raise exception '보유한 검사권이 없어요.';
  end if;

  insert into public.requests (id, user_id, recipient_name, recipient_phone, zonecode, address, address_detail)
  values (p_id, auth.uid(), p_recipient_name, p_recipient_phone, p_zonecode, p_address, p_address_detail);

  update public.profiles set voucher_count = voucher_count - 1 where id = auth.uid();
end;
$$;

-- 관리자: 배송/검사 상태 변경
create or replace function public.admin_update_status(p_request_id text, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (select public.is_admin()) then raise exception '권한이 없습니다.'; end if;
  update public.requests set status = p_status where id = p_request_id;
end;
$$;

-- 관리자: 결과 입력 -> 리포트 생성 + 신청 상태를 완료로 변경
create or replace function public.admin_record_result(
  p_request_id text, p_value numeric, p_percentile integer, p_age_group text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
begin
  if not (select public.is_admin()) then raise exception '권한이 없습니다.'; end if;

  select user_id into v_user_id from public.requests where id = p_request_id;
  if v_user_id is null then raise exception '신청 내역을 찾을 수 없습니다.'; end if;

  insert into public.reports (request_id, user_id, value, percentile, age_group)
  values (p_request_id, v_user_id, p_value, p_percentile, p_age_group);

  update public.requests set status = '완료' where id = p_request_id;
end;
$$;

grant execute on function public.record_purchase(integer, integer) to authenticated;
grant execute on function public.record_kit_request(text, text, text, text, text, text) to authenticated;
grant execute on function public.admin_update_status(text, text) to authenticated;
grant execute on function public.admin_record_result(text, numeric, integer, text) to authenticated;

-- ============================================================
-- 완료. 아래는 참고용 확인 쿼리입니다 (실행하지 않아도 됩니다).
-- select * from public.profiles;
-- ============================================================
