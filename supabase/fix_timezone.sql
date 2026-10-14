-- ===========================================================================
-- big_boss_bro · 一次性修复：把**已经存错的打卡时间 / 结账时间**改回来
-- ---------------------------------------------------------------------------
-- 什么时候要跑这一份：
--   在这份修复之前，App 把打卡时间当成「本机时间字符串」直接发给了 Supabase
--   （`DateTime.toIso8601String()` 对本机时间**不带时区标记**，
--   例如 `2026-06-15T11:43:00.000`）。PostgREST/Postgres 只能按数据库会话时区
--   （Supabase = UTC）去解释它 → 库里存的瞬间**早了整整一个 UTC 偏移**
--   （蒂华纳夏令时 7 小时 / 冬令时 8 小时）。
--
--   于是同一批数据：
--     · App 里显示 11:43（看着是对的）—— 因为它显示的是「UTC 的时分」，
--       碰巧跟当初写进去的本机时分一样，两个错误互相抵消了；
--     · 后台 admin.html 显示 04:43 —— 它老实用浏览器时区换算，所以露馅。
--
--   代码已经改好（`AttendanceSync.punchToRow` / `OrderSync.toRow` 都加了 `.toUtc()`），
--   **但只修代码不会修好已经存进去的那些行** —— 那些行得用这份脚本改一遍。
--
-- ---------------------------------------------------------------------------
-- ⚠️ 怎么用（重要）：**一段一段来**
--
--   Supabase 的 SQL Editor 里，**用鼠标选中一段**再点 Run，就只跑选中的那一段；
--   什么都不选直接 Run 会把整份文件全跑一遍（第 1 步的预览就白看了）。
--
--   顺序：第 0 步 → 第 1 步（**先看**）→ 第 2 步 → 第 3 步（可选）→ 第 4 步
--
--   **不需要改任何东西**：这份脚本里没有要你填的占位符了。
--   它是靠「`at` 比 `created_at` 早 6~9 小时」这个特征找出错的行
--   —— 正常打卡打完 2~25 秒就推进去了，不会早这么久；修好之后这个差回到几秒，
--   所以再跑一遍**不会再改任何行**（这一点跟第 1 步的预览完全一致：
--   预览列出来的行 = 真正会被改的行，一行不多一行不少）。
--
--   前提：**打卡那台设备的时区就是蒂华纳**（下面第 0 步能验证）。
--   把 `America/Tijuana` 换成你店里的时区（共 4 处，都在同一段里）。
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 第 0 步：确认服务器时区 / 目标时区（只是看一眼，不改数据）
-- ---------------------------------------------------------------------------
-- `utc_offset` 应该是 7:00（夏令时 PDT）或 8:00（冬令时 PST）。
-- 如果它跟店里实际的偏移对不上，先把下面所有 `America/Tijuana` 换掉再往下走。
select now()                                  as now_utc,
       now() at time zone 'America/Tijuana'   as now_tijuana,
       now() - (now() at time zone 'America/Tijuana') as utc_offset;


-- ---------------------------------------------------------------------------
-- 第 1 步：**预览** —— 哪些行要改、改成什么（不改数据，先看这一份）
-- ---------------------------------------------------------------------------
-- 在**测试环境或生产**都先跑这一份，逐行看 `old_at` → `new_at`：
--   · 错的那些行：`old_at` 会比员工实际打卡时间早 7~8 小时，`new_at` 正好是员工说的那个点；
--   · 如果某一行 `new_at` 看着**明显不对**（比如算出个凌晨 3 点，没人会上班），
--     说明那一行不是这个 bug（可能是设备系统时区被改过）—— 先别跑第 2 步，把那行贴出来。
select p.id,
       p.employee_id,
       p.kind,
       p.at                    as old_at,          -- 现在库里（错的那个）
       (p.at at time zone 'UTC') at time zone 'America/Tijuana' as new_at,  -- 改完的
       p.created_at,                                -- 服务器收到的时间（正确）
       p.created_at - p.at     as skew              -- 正常是几秒~几分钟；错的那批是 7~8 小时
  from public.attendance_punches p
 where p.created_at - p.at between interval '6 hours' and interval '9 hours'
 order by p.created_at;


-- ---------------------------------------------------------------------------
-- 第 2 步：**真正改打卡时间**（条件跟第 1 步一模一样 —— 选中整段一起跑）
-- ---------------------------------------------------------------------------
-- 为什么这样算是对的：
--   `at`（timestamptz）→ `at time zone 'UTC'` 取出「当初写进去的那个墙上时间」
--   （= 员工当时看到的 11:43）→ 再 `at time zone 'America/Tijuana'` 把它当作
--   蒂华纳当地时间来解释 → 得到真正的瞬间（18:43Z）。夏令时/冬令时由时区名自动处理。
--
-- 跑完看最后那个 `still_suspicious`：
--   · **0**  → 说明该修的都修好了（差的都回到几秒），执行 `commit;`
--   · 不是 0 → 别 commit，把结果贴出来（多半是有别的时区的设备也打过卡）
begin;

update public.attendance_punches p
   set at = (p.at at time zone 'UTC') at time zone 'America/Tijuana'
 where p.created_at - p.at between interval '6 hours' and interval '9 hours';

-- 改完再数一遍：还剩几行「看着是错的」
select count(*) as still_suspicious
  from public.attendance_punches
 where created_at - at between interval '6 hours' and interval '9 hours';

commit;


-- ---------------------------------------------------------------------------
-- 第 3 步（可选）：`orders.closed_at`
-- ---------------------------------------------------------------------------
-- 说明：正常结账走的是 `close_order()` RPC，它用服务器的 now() 写 closed_at ——
-- **那是对的**。只有「RPC 没匹配到、App 改走整单 upsert」那条兜底路径才会写错。
-- 这一条是按单子自带的两份数据互相校正：
--   `data->>'closedAt'` 是 App 记下的**墙上时间**（当地时间），把它按蒂华纳解释
--   就是正确的瞬间；而服务器 now() 写的那些行算出来是**同一个值** ——
--   所以这一条是**幂等**的（重复跑不会越改越偏）。
--
-- 先预览：
select o.id,
       o.closed_at as old_closed_at,
       (o.data->>'closedAt')::timestamp at time zone 'America/Tijuana' as new_closed_at,
       o.updated_at
  from public.orders o
 where o.closed_at is not null
   and o.data ? 'closedAt'
   and o.data->>'closedAt' ~ '^\d{4}-\d{2}-\d{2}T'
   -- 已经带时区标记（Z / +00:00）的说明是新版 App 写的（或者本来就是对的）→ 不动
   and o.data->>'closedAt' !~ '(Z|[-+]\d{2}:?\d{2})$'
 order by o.updated_at desc
 limit 200;

-- 看着对再选中下面这段跑：
begin;

update public.orders o
   set closed_at = (o.data->>'closedAt')::timestamp at time zone 'America/Tijuana'
 where o.closed_at is not null
   and o.data ? 'closedAt'
   and o.data->>'closedAt' ~ '^\d{4}-\d{2}-\d{2}T'
   and o.data->>'closedAt' !~ '(Z|[-+]\d{2}:?\d{2})$';

commit;


-- ---------------------------------------------------------------------------
-- 第 4 步：验收
-- ---------------------------------------------------------------------------
-- 最近 50 条打卡：`at_tijuana` 应该跟员工自己记的时间一致（不会再早 7~8 小时），
-- 而且 `skew`（服务器收到时间 − 打卡时间）只差几秒~几分钟。
select p.id,
       p.employee_id,
       p.kind,
       p.at                                     as at_utc,
       p.at at time zone 'America/Tijuana'      as at_tijuana,
       p.created_at,
       p.created_at - p.at                      as skew
  from public.attendance_punches p
 order by p.created_at desc
 limit 50;

-- 还有没有「明显是错的」行？（应该 0）
select count(*) as still_suspicious
  from public.attendance_punches
 where created_at - at between interval '6 hours' and interval '9 hours';
