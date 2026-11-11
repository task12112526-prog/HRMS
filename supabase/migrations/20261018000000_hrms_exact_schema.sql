-- Idempotent hardening/defaults migration for the five existing, quoted HRMS tables.
-- It deliberately creates no application tables and never deletes employee data.

do $$
declare
  required record;
  required_column text;
  target_table regclass;
begin
  for required in
    select * from (values
      ('Departments', array['Dept_ID', 'Dept_Name', 'Budget', 'Location']::text[]),
      ('Job_Titles', array['Title_ID', 'Job_Title', 'Base_Salary_Min', 'Base_Salary_Max']::text[]),
      ('Employees', array['Employee_ID', 'First_Name', 'Last_Name', 'Email', 'Phone_Number', 'Gender', 'Date_of_Birth', 'Date_of_Joining', 'Dept_ID', 'Title_ID', 'Manager_ID', 'Employment_Status', 'Work_Location']::text[]),
      ('Salaries_And_Compensation', array['Record_ID', 'Employee_ID', 'Base_Salary', 'Bonus_Percentage', 'Medical_Allowance', 'Tax_Deduction', 'Net_Salary']::text[]),
      ('Attendance_And_Leave', array['Record_ID', 'Employee_ID', 'Total_Working_Days', 'Days_Present', 'Days_Absent', 'Paid_Leaves', 'Attendance_Percentage']::text[])
    ) as expected(table_name, column_names)
  loop
    target_table := to_regclass(format('public.%I', required.table_name));
    if target_table is null then
      raise exception 'Required table public.% is missing. Create it with the exact quoted schema before applying this migration.', required.table_name;
    end if;
    foreach required_column in array required.column_names loop
      if not exists (
        select 1 from pg_attribute
        where attrelid = target_table and attname = required_column and attnum > 0 and not attisdropped
      ) then
        raise exception 'Required column public.%.% is missing. Check the exact table and column casing.', required.table_name, required_column;
      end if;
    end loop;
  end loop;
end;
$$;

create sequence if not exists public.departments_dept_id_seq;
create sequence if not exists public.job_titles_title_id_seq;
create sequence if not exists public.employees_employee_id_seq start with 100001;
create sequence if not exists public.salaries_record_id_seq;
create sequence if not exists public.attendance_record_id_seq;

alter table public."Departments"
  alter column "Dept_ID" set default ('DEP-' || lpad(nextval('public.departments_dept_id_seq')::text, 2, '0')),
  alter column "Budget" set default 0,
  alter column "Location" set default '';

alter table public."Job_Titles"
  alter column "Title_ID" set default ('JOB-' || lpad(nextval('public.job_titles_title_id_seq')::text, 3, '0')),
  alter column "Base_Salary_Min" set default 0,
  alter column "Base_Salary_Max" set default 0;

alter table public."Employees"
  alter column "Employee_ID" set default ('EMP-' || lpad(nextval('public.employees_employee_id_seq')::text, 6, '0')),
  alter column "Phone_Number" set default '',
  alter column "Gender" set default '',
  alter column "Date_of_Joining" set default current_date,
  alter column "Employment_Status" set default 'Active',
  alter column "Work_Location" set default 'Office';

alter table public."Salaries_And_Compensation"
  alter column "Record_ID" set default ('SAL-' || lpad(nextval('public.salaries_record_id_seq')::text, 6, '0')),
  alter column "Bonus_Percentage" set default 0,
  alter column "Medical_Allowance" set default 0,
  alter column "Tax_Deduction" set default 0;

alter table public."Attendance_And_Leave"
  alter column "Record_ID" set default ('ATT-' || lpad(nextval('public.attendance_record_id_seq')::text, 6, '0')),
  alter column "Paid_Leaves" set default 0;

alter sequence public.departments_dept_id_seq owned by public."Departments"."Dept_ID";
alter sequence public.job_titles_title_id_seq owned by public."Job_Titles"."Title_ID";
alter sequence public.employees_employee_id_seq owned by public."Employees"."Employee_ID";
alter sequence public.salaries_record_id_seq owned by public."Salaries_And_Compensation"."Record_ID";
alter sequence public.attendance_record_id_seq owned by public."Attendance_And_Leave"."Record_ID";

select setval('public.departments_dept_id_seq', greatest(coalesce(max(substring("Dept_ID" from '[0-9]+$')::bigint), 1), 1), count(*) > 0) from public."Departments";
select setval('public.job_titles_title_id_seq', greatest(coalesce(max(substring("Title_ID" from '[0-9]+$')::bigint), 1), 1), count(*) > 0) from public."Job_Titles";
select setval('public.employees_employee_id_seq', greatest(coalesce(max(substring("Employee_ID" from '[0-9]+$')::bigint), 100000), 100000), count(*) > 0) from public."Employees";
select setval('public.salaries_record_id_seq', greatest(coalesce(max(substring("Record_ID" from '[0-9]+$')::bigint), 1), 1), count(*) > 0) from public."Salaries_And_Compensation";
select setval('public.attendance_record_id_seq', greatest(coalesce(max(substring("Record_ID" from '[0-9]+$')::bigint), 1), 1), count(*) > 0) from public."Attendance_And_Leave";

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public."Departments"'::regclass and conname = 'peopleos_departments_budget_nonnegative'
  ) then
    alter table public."Departments" add constraint peopleos_departments_budget_nonnegative
      check ("Budget" >= 0) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public."Job_Titles"'::regclass and conname = 'peopleos_job_titles_salary_range'
  ) then
    alter table public."Job_Titles" add constraint peopleos_job_titles_salary_range
      check ("Base_Salary_Min" >= 0 and "Base_Salary_Max" >= "Base_Salary_Min") not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public."Employees"'::regclass and conname = 'peopleos_employees_email_normalized'
  ) then
    alter table public."Employees" add constraint peopleos_employees_email_normalized
      check ("Email" = lower(trim("Email"))) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public."Employees"'::regclass and conname = 'peopleos_employees_status'
  ) then
    alter table public."Employees" add constraint peopleos_employees_status
      check ("Employment_Status" in ('Active', 'Terminated', 'On Leave')) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public."Employees"'::regclass and conname = 'peopleos_employees_work_location'
  ) then
    alter table public."Employees" add constraint peopleos_employees_work_location
      check ("Work_Location" in ('Office', 'Remote', 'Hybrid')) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public."Salaries_And_Compensation"'::regclass and conname = 'peopleos_compensation_nonnegative'
  ) then
    alter table public."Salaries_And_Compensation" add constraint peopleos_compensation_nonnegative
      check ("Base_Salary" >= 0 and "Bonus_Percentage" >= 0 and "Medical_Allowance" >= 0 and "Tax_Deduction" >= 0) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public."Attendance_And_Leave"'::regclass and conname = 'peopleos_attendance_day_counts'
  ) then
    alter table public."Attendance_And_Leave" add constraint peopleos_attendance_day_counts
      check (
        "Total_Working_Days" >= 0
        and "Days_Present" >= 0
        and "Days_Absent" >= 0
        and "Paid_Leaves" >= 0
        and "Days_Present" <= "Total_Working_Days"
        and "Days_Present" + "Days_Absent" <= "Total_Working_Days"
        and "Paid_Leaves" <= "Total_Working_Days"
      ) not valid;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conrelid = 'public."Employees"'::regclass
      and contype = 'f' and conkey = array[(select attnum from pg_attribute where attrelid = 'public."Employees"'::regclass and attname = 'Dept_ID')]::smallint[]
      and confrelid = 'public."Departments"'::regclass
      and confkey = array[(select attnum from pg_attribute where attrelid = 'public."Departments"'::regclass and attname = 'Dept_ID')]::smallint[]
  ) then
    alter table public."Employees" add constraint peopleos_employees_department_fkey
      foreign key ("Dept_ID") references public."Departments"("Dept_ID") on update cascade on delete set null not valid;
  end if;
  if not exists (
    select 1 from pg_constraint where conrelid = 'public."Employees"'::regclass
      and contype = 'f' and conkey = array[(select attnum from pg_attribute where attrelid = 'public."Employees"'::regclass and attname = 'Title_ID')]::smallint[]
      and confrelid = 'public."Job_Titles"'::regclass
      and confkey = array[(select attnum from pg_attribute where attrelid = 'public."Job_Titles"'::regclass and attname = 'Title_ID')]::smallint[]
  ) then
    alter table public."Employees" add constraint peopleos_employees_job_title_fkey
      foreign key ("Title_ID") references public."Job_Titles"("Title_ID") on update cascade on delete set null not valid;
  end if;
  if not exists (
    select 1 from pg_constraint where conrelid = 'public."Employees"'::regclass
      and contype = 'f' and conkey = array[(select attnum from pg_attribute where attrelid = 'public."Employees"'::regclass and attname = 'Manager_ID')]::smallint[]
      and confrelid = 'public."Employees"'::regclass
      and confkey = array[(select attnum from pg_attribute where attrelid = 'public."Employees"'::regclass and attname = 'Employee_ID')]::smallint[]
  ) then
    alter table public."Employees" add constraint peopleos_employees_manager_fkey
      foreign key ("Manager_ID") references public."Employees"("Employee_ID") on update cascade on delete set null not valid;
  end if;
  if not exists (
    select 1 from pg_constraint where conrelid = 'public."Salaries_And_Compensation"'::regclass
      and contype = 'f' and conkey = array[(select attnum from pg_attribute where attrelid = 'public."Salaries_And_Compensation"'::regclass and attname = 'Employee_ID')]::smallint[]
      and confrelid = 'public."Employees"'::regclass
      and confkey = array[(select attnum from pg_attribute where attrelid = 'public."Employees"'::regclass and attname = 'Employee_ID')]::smallint[]
  ) then
    alter table public."Salaries_And_Compensation" add constraint peopleos_compensation_employee_fkey
      foreign key ("Employee_ID") references public."Employees"("Employee_ID") on update cascade on delete cascade not valid;
  end if;
  if not exists (
    select 1 from pg_constraint where conrelid = 'public."Attendance_And_Leave"'::regclass
      and contype = 'f' and conkey = array[(select attnum from pg_attribute where attrelid = 'public."Attendance_And_Leave"'::regclass and attname = 'Employee_ID')]::smallint[]
      and confrelid = 'public."Employees"'::regclass
      and confkey = array[(select attnum from pg_attribute where attrelid = 'public."Employees"'::regclass and attname = 'Employee_ID')]::smallint[]
  ) then
    alter table public."Attendance_And_Leave" add constraint peopleos_attendance_employee_fkey
      foreign key ("Employee_ID") references public."Employees"("Employee_ID") on update cascade on delete cascade not valid;
  end if;
end;
$$;

create unique index if not exists peopleos_employees_email_uidx
  on public."Employees" (lower("Email"));
create index if not exists peopleos_employees_department_idx
  on public."Employees" ("Dept_ID");
create index if not exists peopleos_employees_job_title_idx
  on public."Employees" ("Title_ID");
create index if not exists peopleos_employees_manager_idx
  on public."Employees" ("Manager_ID");
create index if not exists peopleos_employees_status_idx
  on public."Employees" ("Employment_Status");
create index if not exists peopleos_employees_joining_date_idx
  on public."Employees" ("Date_of_Joining");
create index if not exists peopleos_employees_first_name_idx
  on public."Employees" ("First_Name");
create index if not exists peopleos_employees_last_name_idx
  on public."Employees" ("Last_Name");
create index if not exists peopleos_employees_work_location_idx
  on public."Employees" ("Work_Location");
create index if not exists peopleos_compensation_employee_idx
  on public."Salaries_And_Compensation" ("Employee_ID");
create index if not exists peopleos_attendance_employee_idx
  on public."Attendance_And_Leave" ("Employee_ID");

create extension if not exists pg_trgm;

do $$
declare
  trgm_schema text;
begin
  select namespace.nspname
  into trgm_schema
  from pg_opclass as operator_class
  join pg_namespace as namespace on namespace.oid = operator_class.opcnamespace
  join pg_am as access_method on access_method.oid = operator_class.opcmethod
  where operator_class.opcname = 'gin_trgm_ops'
    and access_method.amname = 'gin'
  limit 1;

  if trgm_schema is null then
    raise exception 'The pg_trgm gin_trgm_ops operator class is unavailable.';
  end if;

  execute format('create index if not exists peopleos_employees_first_name_trgm_idx on public."Employees" using gin ("First_Name" %I.gin_trgm_ops)', trgm_schema);
  execute format('create index if not exists peopleos_employees_last_name_trgm_idx on public."Employees" using gin ("Last_Name" %I.gin_trgm_ops)', trgm_schema);
  execute format('create index if not exists peopleos_employees_email_trgm_idx on public."Employees" using gin ("Email" %I.gin_trgm_ops)', trgm_schema);
  execute format('create index if not exists peopleos_employees_id_trgm_idx on public."Employees" using gin ("Employee_ID" %I.gin_trgm_ops)', trgm_schema);
end;
$$;

create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when ((select auth.jwt())->'app_metadata'->>'role') in ('admin', 'hr_manager', 'employee')
      then (select auth.jwt())->'app_metadata'->>'role'
    else 'employee'
  end;
$$;

create or replace function public.is_hr_or_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.current_app_role() in ('admin', 'hr_manager');
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.current_app_role() = 'admin';
$$;

create or replace function public.current_employee_id()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select "Employee_ID"
  from public."Employees"
  where lower("Email") = lower((select auth.jwt())->>'email')
  limit 1;
$$;

create or replace function public.guard_employee_self_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.is_hr_or_admin() then
    return new;
  end if;

  if new."Employee_ID" is distinct from old."Employee_ID"
    or new."First_Name" is distinct from old."First_Name"
    or new."Last_Name" is distinct from old."Last_Name"
    or new."Email" is distinct from old."Email"
    or new."Date_of_Birth" is distinct from old."Date_of_Birth"
    or new."Date_of_Joining" is distinct from old."Date_of_Joining"
    or new."Dept_ID" is distinct from old."Dept_ID"
    or new."Title_ID" is distinct from old."Title_ID"
    or new."Manager_ID" is distinct from old."Manager_ID"
    or new."Employment_Status" is distinct from old."Employment_Status"
    or new."Work_Location" is distinct from old."Work_Location" then
    raise exception 'Employees may only update their phone number and gender.';
  end if;
  return new;
end;
$$;

create or replace function public.calculate_net_salary()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new."Net_Salary" := round(
    new."Base_Salary"::numeric
    + new."Base_Salary"::numeric * new."Bonus_Percentage"::numeric / 100
    + new."Medical_Allowance"::numeric
    - new."Tax_Deduction"::numeric,
    2
  );
  return new;
end;
$$;

create or replace function public.calculate_attendance_percentage()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new."Attendance_Percentage" := case
    when new."Total_Working_Days" = 0 then 0
    else round(new."Days_Present"::numeric * 100 / new."Total_Working_Days", 2)
  end;
  return new;
end;
$$;

create or replace function public.hrms_dashboard_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_hr_or_admin() then
    raise exception 'Only HR managers and administrators can view the HR dashboard summary.';
  end if;

  return jsonb_build_object(
    'employeeCount', (select count(*) from public."Employees"),
    'activeCount', (select count(*) from public."Employees" where "Employment_Status" = 'Active'),
    'attendanceRecordCount', (select count(*) from public."Attendance_And_Leave"),
    'attendanceWorkingDays', coalesce((select sum("Total_Working_Days") from public."Attendance_And_Leave"), 0),
    'attendancePresentDays', coalesce((select sum("Days_Present") from public."Attendance_And_Leave"), 0),
    'attendancePaidLeaves', coalesce((select sum("Paid_Leaves") from public."Attendance_And_Leave"), 0),
    'departmentCounts', coalesce((
      select jsonb_object_agg(counts."Dept_ID", counts.employee_count)
      from (
        select "Dept_ID", count(*) as employee_count
        from public."Employees"
        where "Dept_ID" is not null
        group by "Dept_ID"
      ) as counts
    ), '{}'::jsonb),
    'titleCounts', coalesce((
      select jsonb_object_agg(counts."Title_ID", counts.employee_count)
      from (
        select "Title_ID", count(*) as employee_count
        from public."Employees"
        where "Title_ID" is not null
        group by "Title_ID"
      ) as counts
    ), '{}'::jsonb)
  );
end;
$$;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'Salaries_And_Compensation'
      and column_name = 'Net_Salary' and is_generated = 'NEVER'
  ) then
    drop trigger if exists peopleos_calculate_net_salary on public."Salaries_And_Compensation";
    create trigger peopleos_calculate_net_salary before insert or update
      on public."Salaries_And_Compensation"
      for each row execute function public.calculate_net_salary();
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'Attendance_And_Leave'
      and column_name = 'Attendance_Percentage' and is_generated = 'NEVER'
  ) then
    drop trigger if exists peopleos_calculate_attendance_percentage on public."Attendance_And_Leave";
    create trigger peopleos_calculate_attendance_percentage before insert or update
      on public."Attendance_And_Leave"
      for each row execute function public.calculate_attendance_percentage();
  end if;
  drop trigger if exists peopleos_guard_employee_self_update on public."Employees";
  create trigger peopleos_guard_employee_self_update before update
    on public."Employees"
    for each row execute function public.guard_employee_self_update();
end;
$$;

revoke all on function public.current_app_role() from public, anon;
revoke all on function public.is_hr_or_admin() from public, anon;
revoke all on function public.is_admin() from public, anon;
revoke all on function public.current_employee_id() from public, anon;
revoke all on function public.guard_employee_self_update() from public, anon;
revoke all on function public.calculate_net_salary() from public, anon;
revoke all on function public.calculate_attendance_percentage() from public, anon;
revoke all on function public.hrms_dashboard_summary() from public, anon;
grant execute on function public.current_app_role() to authenticated;
grant execute on function public.is_hr_or_admin() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.current_employee_id() to authenticated;
grant execute on function public.hrms_dashboard_summary() to authenticated;

alter table public."Departments" enable row level security;
alter table public."Job_Titles" enable row level security;
alter table public."Employees" enable row level security;
alter table public."Salaries_And_Compensation" enable row level security;
alter table public."Attendance_And_Leave" enable row level security;

-- Existing broad/permissive policies can defeat a new restrictive policy by OR.
-- Replace policies on just these five application tables with the policies below.
do $$
declare
  existing_policy record;
begin
  for existing_policy in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = any(array['Departments', 'Job_Titles', 'Employees', 'Salaries_And_Compensation', 'Attendance_And_Leave'])
  loop
    execute format('drop policy %I on %I.%I', existing_policy.policyname, existing_policy.schemaname, existing_policy.tablename);
  end loop;
end;
$$;

revoke all on table public."Departments", public."Job_Titles", public."Employees", public."Salaries_And_Compensation", public."Attendance_And_Leave" from public, anon;
grant select, insert, update, delete on table public."Departments", public."Job_Titles", public."Employees", public."Salaries_And_Compensation", public."Attendance_And_Leave" to authenticated;
revoke all on sequence public.departments_dept_id_seq, public.job_titles_title_id_seq, public.employees_employee_id_seq, public.salaries_record_id_seq, public.attendance_record_id_seq from public, anon;
grant usage, select on sequence public.departments_dept_id_seq, public.job_titles_title_id_seq, public.employees_employee_id_seq, public.salaries_record_id_seq, public.attendance_record_id_seq to authenticated;

create policy "Authenticated users read departments"
  on public."Departments" for select to authenticated using (true);
create policy "HR and admins manage departments"
  on public."Departments" for all to authenticated
  using (public.is_hr_or_admin()) with check (public.is_hr_or_admin());

create policy "Authenticated users read job titles"
  on public."Job_Titles" for select to authenticated using (true);
create policy "HR and admins manage job titles"
  on public."Job_Titles" for all to authenticated
  using (public.is_hr_or_admin()) with check (public.is_hr_or_admin());

create policy "HR sees employees; employees see their email-matched record"
  on public."Employees" for select to authenticated
  using (public.is_hr_or_admin() or lower("Email") = lower((select auth.jwt())->>'email'));
create policy "HR and admins create employee records"
  on public."Employees" for insert to authenticated
  with check (public.is_hr_or_admin());
create policy "HR manages employees; employees update their own record"
  on public."Employees" for update to authenticated
  using (public.is_hr_or_admin() or lower("Email") = lower((select auth.jwt())->>'email'))
  with check (public.is_hr_or_admin() or lower("Email") = lower((select auth.jwt())->>'email'));
create policy "Admins delete employee records"
  on public."Employees" for delete to authenticated
  using (public.is_admin());

create policy "Employees read their compensation; HR sees all"
  on public."Salaries_And_Compensation" for select to authenticated
  using (public.is_hr_or_admin() or "Employee_ID" = (select public.current_employee_id()));
create policy "HR and admins manage compensation"
  on public."Salaries_And_Compensation" for all to authenticated
  using (public.is_hr_or_admin()) with check (public.is_hr_or_admin());

create policy "Employees read their attendance summary; HR sees all"
  on public."Attendance_And_Leave" for select to authenticated
  using (public.is_hr_or_admin() or "Employee_ID" = (select public.current_employee_id()));
create policy "HR and admins manage attendance summaries"
  on public."Attendance_And_Leave" for all to authenticated
  using (public.is_hr_or_admin()) with check (public.is_hr_or_admin());
notify pgrst, 'reload schema';
