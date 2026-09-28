-- ============================================================
-- Wellscore Supabase 추가 기능 마이그레이션 스크립트
-- (반송 시스템, 배송 정보 상세화, 회원 탈퇴 RPC)
--
-- 이미 기존 supabase-schema.sql을 실행하신 분은
-- Supabase 대시보드 > SQL Editor > New query 에 이 스크립트를
-- 붙여넣고 Run 버튼을 누르시면 됩니다.
-- ============================================================

-- 1. requests 테이블에 반송 및 배송 송장 컬럼 추가
alter table public.requests
  add column if not exists tracking_carrier text default 'CJ대한통운',
  add column if not exists tracking_number text,
  add column if not exists shipped_at timestamptz,
  add column if not exists return_name text,
  add column if not exists return_phone text,
  add column if not exists return_zonecode text,
  add column if not exists return_address text,
  add column if not exists return_address_detail text,
  add column if not exists return_memo text,
  add column if not exists return_requested_at timestamptz,
  add column if not exists return_carrier text default 'CJ대한통운',
  add column if not exists return_tracking_number text;

-- 2. requests 테이블의 status 체크 제약조건 갱신
-- ('배송준비중', '배송중', '반송신청', '반송중', '검사중', '완료')
do $$
begin
  -- 기존 check 제약조건 이름 찾아서 삭제
  execute (
    select 'alter table public.requests drop constraint ' || conname
    from pg_constraint
    where conrelid = 'public.requests'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%status%'
    limit 1
  );
exception when others then
  null;
end $$;

alter table public.requests
  add constraint requests_status_check
  check (status in ('배송준비중', '배송중', '반송신청', '반송중', '검사중', '완료'));

-- ------------------------------------------------------------
-- 3. 사용자 직접 반송 신청 함수 RPC
-- ------------------------------------------------------------
create or replace function public.request_kit_return(
  p_request_id text,
  p_return_name text,
  p_return_phone text,
  p_return_zonecode text,
  p_return_address text,
  p_return_address_detail text,
  p_return_memo text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_current_status text;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select user_id, status into v_user_id, v_current_status
  from public.requests
  where id = p_request_id;

  if v_user_id is null or v_user_id <> auth.uid() then
    raise exception '신청 내역을 찾을 수 없거나 권한이 없습니다.';
  end if;

  -- 배송중 상태(또는 배송준비중)에서 채혈 후 반송 신청 가능
  if v_current_status not in ('배송중', '배송준비중') then
    raise exception '현재 상태에서는 반송을 신청할 수 없습니다. (현재 상태: %)', v_current_status;
  end if;

  update public.requests
  set status = '반송신청',
      return_name = coalesce(p_return_name, recipient_name),
      return_phone = coalesce(p_return_phone, recipient_phone),
      return_zonecode = coalesce(p_return_zonecode, zonecode),
      return_address = coalesce(p_return_address, address),
      return_address_detail = coalesce(p_return_address_detail, address_detail),
      return_memo = p_return_memo,
      return_requested_at = now()
  where id = p_request_id;
end;
$$;

-- ------------------------------------------------------------
-- 4. 관리자: 배송 출고 정보 업데이트 (송장 등록 및 상태 변경)
-- ------------------------------------------------------------
create or replace function public.admin_update_delivery(
  p_request_id text,
  p_status text,
  p_carrier text,
  p_tracking_number text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (select public.is_admin()) then
    raise exception '권한이 없습니다.';
  end if;

  update public.requests
  set status = coalesce(nullif(p_status, ''), status),
      tracking_carrier = coalesce(nullif(p_carrier, ''), tracking_carrier),
      tracking_number = coalesce(nullif(p_tracking_number, ''), tracking_number),
      shipped_at = case when p_status = '배송중' and shipped_at is null then now() else shipped_at end
  where id = p_request_id;
end;
$$;

-- ------------------------------------------------------------
-- 5. 관리자: 반송 회수 정보 업데이트 (반송 송장 및 상태 변경)
-- ------------------------------------------------------------
create or replace function public.admin_update_return(
  p_request_id text,
  p_status text,
  p_carrier text,
  p_tracking_number text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (select public.is_admin()) then
    raise exception '권한이 없습니다.';
  end if;

  update public.requests
  set status = coalesce(nullif(p_status, ''), status),
      return_carrier = coalesce(nullif(p_carrier, ''), return_carrier),
      return_tracking_number = coalesce(nullif(p_tracking_number, ''), return_tracking_number)
  where id = p_request_id;
end;
$$;

-- ------------------------------------------------------------
-- 6. 회원 탈퇴 함수 RPC (내 계정 영구 삭제)
-- ------------------------------------------------------------
create or replace function public.delete_user_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- auth.users 삭제 (cascade 제약조건으로 profiles, purchases, requests, reports 자동 삭제됨)
  delete from auth.users where id = auth.uid();
end;
$$;

-- 권한 부여
grant execute on function public.request_kit_return(text, text, text, text, text, text, text) to authenticated;
grant execute on function public.admin_update_delivery(text, text, text, text) to authenticated;
grant execute on function public.admin_update_return(text, text, text, text) to authenticated;
grant execute on function public.delete_user_account() to authenticated;
