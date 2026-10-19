-- ===========================================================================
-- big_boss_bro · Supabase 后台（方案 B：云 + 多设备共用一个单池）
-- ---------------------------------------------------------------------------
-- 怎么用：Supabase 控制台 → 左侧「SQL Editor」→ New query → 把这一整份粘进去 → Run。
-- 可以**重复执行**（都是 if not exists / create or replace / drop policy if exists）。
--
-- 五张表：
--   orders            一张单一行：状态 + 整张单的 JSON（App 里 `Order.toJson()` 原样存进 data）
--   menu              只有一行（id='current'）：整份菜单 JSON + 版本号
--   attendance_staff  只有一行（id='current'）：员工名单 JSON + 版本号
--   attendance_punches 一次打卡一行（只增不改）
--   store_settings    只有一行（id='current'）：**店级配置** JSON + 版本号
--                     （店名 / 店头地址 / 税率 / 货币与汇率 / 桌号 / 各分类备注 / 日结支出）
--                     —— 换新设备时靠它自动把"这家店怎么配置"拿回来
--
-- 三条约定（重要）：
--   1) **服务器是权威**：`updated_at` / `rev` / `version` 由触发器维护，App 只管推 data；
--      App 推成功后，把服务器返回的 rev/updated_at/version 存回本地（本地 rev=0 表示「还没推上去」）。
--   2) **结账只允许成功一次**：用 close_order() 做一次 CAS（in_progress → completed），
--      三台设备同时点结账也不会算两次钱。
--   3) **只有登录用户能读写**（RLS 对 authenticated 放开、对 anon 全关）：
--      所以备份之外，外人拿到 anon key 也看不到数据。
-- =========================================== ================================

-- 生成 uuid 用（结账 RPC 里没用到，但留着方便以后扩展）
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 1) 单子表
-- ---------------------------------------------------------------------------
create table if not exists public.orders (
  id          text primary key,                     -- 单号（App 生成，带设备前缀不会撞）
  status      text        not null default 'in_progress', -- in_progress / completed
  order_type  text        not null default 'dine_in',     -- dine_in / takeaway / phonecall_takeaway / platform_takeaway
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
-- 4) 员工考勤（打卡）
--    attendance_staff    员工名单：**只有一行**（id='current'），整份名单 JSON + 版本号
--                        （跟 menu 一个思路：改一次版本 +1，设备比版本号决定要不要拉）
--    attendance_punches  打卡记录：一次打卡一行（上班 in / 下班 out），**只增不改**，
--                        所以设备之间合并就是「按 id 并集」，不存在冲突。
--                        `at` 存的是 **UTC 瞬间**（timestamptz）—— 显示时按各自时区换算，
--                        列上有注释；老数据存歪了的话跑 supabase/fix_timezone.sql。
-- ---------------------------------------------------------------------------
create table if not exists public.attendance_staff (
  id          text primary key default 'current',
  version     bigint      not null default 1,     -- 每次保存 +1
  updated_at  timestamptz not null default now(),
  device_id   text        not null default '',    -- 哪台设备最后改的
  data        jsonb       not null                -- {"staff":[{"id","name","pin"}, ...]}
);

create or replace function public.touch_staff() returns trigger
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

drop trigger if exists attendance_staff_touch on public.attendance_staff;
create trigger attendance_staff_touch
  before insert or update on public.attendance_staff
  for each row execute function public.touch_staff();

create table if not exists public.attendance_punches (
  id          text primary key,                   -- App 生成的全局唯一 id（两台设备不会撞）
  employee_id text        not null,               -- 对应 data.staff[].id
  kind        text        not null default 'in',  -- in = 上班 / out = 下班
  -- ⚠️ 设备打卡的时间，**存 UTC 瞬间**（App 送 `...Z`）。
  --    `timestamptz` 本身不带时区，谁想看墙上时间谁自己换算（App 按设备时区、
  --    admin.html 按浏览器时区）。
  --    历史坑：老版 App 送的是**不带时区标记的本机时间字符串**，被当成 UTC 存下来
  --    → 早了一个 UTC 偏移（蒂华纳 7~8 小时）。修法见 supabase/fix_timezone.sql。
  at          timestamptz not null,               -- 打卡那一刻（UTC）
  device_id   text        not null default '',    -- 哪台设备打的
  created_at  timestamptz not null default now()  -- 服务器收到的顺序（增量同步就靠它）
);

create index if not exists attendance_punches_created_idx
  on public.attendance_punches (created_at);
create index if not exists attendance_punches_at_idx
  on public.attendance_punches (at);

-- ---------------------------------------------------------------------------
-- 5) 店级配置（store_settings）
--    **只有一行**（id='current'）：整份配置 JSON + 版本号（跟 menu / attendance_staff 一个套路）。
--
--    放的是「整个店共用」的东西：
--      店名、店头（地址/电话/RFC）、税率与含税方式、货币符号与汇率、
--      桌号清单、各分类的常用备注、日结支出、菜品管理密码。
--
--    ⚠️ **打印机相关的故意不放这里**（蓝牙 MAC / IP / Windows 打印机名 / 纸宽 /
--       小票编码 / 厨师单字号）：那是每台设备自己的硬件配置，
--       同步过去只会把另一台设备的打印机搞坏。
--
--    为什么需要它：以前换一台新设备（新平板）要把店名、税率、货币、桌号、
--    备注全部重填一遍。现在新设备登录后台后会自动把这一行拉下来。
-- ---------------------------------------------------------------------------
create table if not exists public.store_settings (
  id          text primary key default 'current',
  version     bigint      not null default 1,     -- 每次保存 +1，设备比它决定要不要拉新版
  updated_at  timestamptz not null default now(),
  device_id   text        not null default '',    -- 哪台设备最后改的
  data        jsonb       not null                -- 店级配置 JSON（见上面那份清单）
);

create or replace function public.touch_store_settings() returns trigger
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

drop trigger if exists store_settings_touch on public.store_settings;
create trigger store_settings_touch
  before insert or update on public.store_settings
  for each row execute function public.touch_store_settings();

-- ---------------------------------------------------------------------------
-- 6) 权限（RLS）：登录用户可读写，匿名一律看不到
-- ---------------------------------------------------------------------------
alter table public.orders enable row level security;
alter table public.menu   enable row level security;
alter table public.attendance_staff   enable row level security;
alter table public.attendance_punches enable row level security;
alter table public.store_settings     enable row level security;

drop policy if exists orders_authenticated_all on public.orders;
create policy orders_authenticated_all on public.orders
  for all to authenticated using (true) with check (true);

drop policy if exists menu_authenticated_all on public.menu;
create policy menu_authenticated_all on public.menu
  for all to authenticated using (true) with check (true);

drop policy if exists attendance_staff_authenticated_all on public.attendance_staff;
create policy attendance_staff_authenticated_all on public.attendance_staff
  for all to authenticated using (true) with check (true);

drop policy if exists attendance_punches_authenticated_all on public.attendance_punches;
create policy attendance_punches_authenticated_all on public.attendance_punches
  for all to authenticated using (true) with check (true);

drop policy if exists store_settings_authenticated_all on public.store_settings;
create policy store_settings_authenticated_all on public.store_settings
  for all to authenticated using (true) with check (true);

-- RPC 也要授权（默认 security definer 不给 anon 执行）
revoke all on function public.close_order(text, jsonb, text) from public, anon;
grant execute on function public.close_order(text, jsonb, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7) 自检：跑完可以执行下面两句看看（应该有 5 张表 + 5 个函数）
--    表：orders / menu / attendance_staff / attendance_punches / store_settings
--    函数：touch_order / touch_menu / touch_staff / touch_store_settings / close_order
-- ---------------------------------------------------------------------------
-- select table_name from information_schema.tables where table_schema = 'public';
-- select routine_name from information_schema.routines where routine_schema = 'public';
