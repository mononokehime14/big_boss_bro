-- ===========================================================================
-- big_boss_bro · Supabase 后台（方案 B：云 + 多设备共用一个单池）
-- ---------------------------------------------------------------------------
-- 怎么用：Supabase 控制台 → 左侧「SQL Editor」→ New query → 把这一整份粘进去 → Run。
-- 可以**重复执行**（都是 if not exists / create or replace / drop policy if exists）。
--
-- 两张表：
--   orders  一张单一行：状态 + 整张单的 JSON（App 里 `Order.toJson()` 原样存进 data）
--   menu    只有一行（id='current'）：整份菜单 JSON + 版本号
--
-- 三条约定（重要）：
--   1) **服务器是权威**：`updated_at` / `rev` 由触发器维护，App 只管推 data；
--      App 推成功后，把服务器返回的 rev/updated_at 存回本地（本地 rev=0 表示「还没推上去」）。
--   2) **结账只允许成功一次**：用 close_order() 做一次 CAS（in_progress → completed），
--      三台设备同时点结账也不会算两次钱。
--   3) **只有登录用户能读写**（RLS 对 authenticated 放开、对 anon 全关）：
--      所以备份之外，外人拿到 anon key 也看不到数据。
-- ===========================================================================

-- 生成 uuid 用（结账 RPC 里没用到，但留着方便以后扩展）
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 1) 单子表
-- ---------------------------------------------------------------------------
create table if not exists public.orders (
  id          text primary key,                     -- 单号（App 生成，带设备前缀不会撞）
  status      text        not null default 'in_progress', -- in_progress / completed
  order_type  text        not null default 'dine_in',     -- dine_in / takeaway / phonecall_takeaway
  table_no    text        not null default '',
  total       numeric(12,2) not null default 0,
  item_count  integer     not null default 0,
  cashier     text        not null default '',
  device_id   text        not null default '',       -- 哪台设备最后改的
  rev         bigint      not null default 1,        -- 服务器版本号（每次更新 +1）
  updated_at  timestamptz not null default now(),    -- 服务器时间（增量同步就靠它）
  closed_at   timestamptz,
  data        jsonb       not null                   -- 整张单的 JSON
);

create index if not exists orders_updated_idx on public.orders (updated_at);
create index if not exists orders_status_idx  on public.orders (status);

-- 服务器维护 rev / updated_at（App 送什么都会被覆盖成正确的值）
create or replace function public.touch_order() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.rev := 1;
  else
    new.rev := old.rev + 1;
  end if;
  return new;
end $$;

drop trigger if exists orders_touch on public.orders;
create trigger orders_touch
  before insert or update on public.orders
  for each row execute function public.touch_order();

-- ---------------------------------------------------------------------------
-- 2) 菜单表（只有一行，data 里放 {categories:[...], items:[...]}）
-- ---------------------------------------------------------------------------
create table if not exists public.menu (
  id          text primary key default 'current',
  version     bigint      not null default 1,       -- 每次保存 +1，设备比这个数决定要不要更新
  updated_at  timestamptz not null default now(),
  data        jsonb       not null
);

create or replace function public.touch_menu() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.version := 1;
  else
    new.version := old.version + 1;
  end if;
  return new;
end $$;

drop trigger if exists menu_touch on public.menu;
create trigger menu_touch
  before insert or update on public.menu
  for each row execute function public.touch_menu();

-- ---------------------------------------------------------------------------
-- 3) 结账：**只成功一次**的 CAS
--    App 调：POST /rest/v1/rpc/close_order  {"p_id":"...","p_patch":{...},"p_device":"..."}
--    返回：结完之后的整行（含服务器 rev/updated_at）
--    如果这张单已经被别的设备结掉了 → 返回**现状**（status=completed），App 采纳它即可
--
--    注意 p_patch 是 App 那份**整张单的 JSON**（不只是结账字段）：
--    「推上去之后又加了菜、然后马上结账」时，只并结账字段会把新加的菜弄丢。
--    jsonb 的 `||` 是浅合并，所以整份发过来就等于把 data 覆盖成本地那份。
-- ---------------------------------------------------------------------------
create or replace function public.close_order(
  p_id     text,
  p_patch  jsonb,
  p_device text default ''
) returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare r public.orders;
begin
  update public.orders
     set data      = data || coalesce(p_patch, '{}'::jsonb),  -- App 那份整单 JSON 并进来
         status    = 'completed',
         closed_at = coalesce(closed_at, now()),
         device_id = coalesce(nullif(p_device, ''), device_id),
         total     = coalesce((p_patch->>'total')::numeric, total)
   where id = p_id
     and status <> 'completed'
  returning * into r;

  if r.id is null then
    -- 要么已经被别人结掉了，要么这张单还没推上来过
    select * into r from public.orders where id = p_id;
  end if;

  return r;   -- 可能返回 null（说明服务器上根本没有这张单 → App 整单推上来）
end $$;

-- ---------------------------------------------------------------------------
-- 4) 权限（RLS）：登录用户可读写，匿名一律看不到
-- ---------------------------------------------------------------------------
alter table public.orders enable row level security;
alter table public.menu   enable row level security;

drop policy if exists orders_authenticated_all on public.orders;
create policy orders_authenticated_all on public.orders
  for all to authenticated using (true) with check (true);

drop policy if exists menu_authenticated_all on public.menu;
create policy menu_authenticated_all on public.menu
  for all to authenticated using (true) with check (true);

-- RPC 也要授权（默认 security definer 不给 anon 执行）
revoke all on function public.close_order(text, jsonb, text) from public, anon;
grant execute on function public.close_order(text, jsonb, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5) 自检：跑完可以执行下面两句看看（应该有 2 张表 + 3 个函数）
-- ---------------------------------------------------------------------------
-- select table_name from information_schema.tables where table_schema = 'public';
-- select routine_name from information_schema.routines where routine_schema = 'public';
