-- Fictional development-only records. Do not use this seed with real employee data.
-- The application creates IDs automatically; this seed uses stable sample IDs so
-- it can be re-run without generating duplicate sample records.
insert into public."Departments" ("Dept_ID", "Dept_Name", "Budget", "Location") values
  ('DEP-01', 'People & Culture', 750000, 'New York'),
  ('DEP-02', 'Engineering', 2400000, 'Remote'),
  ('DEP-03', 'Design', 800000, 'London'),
  ('DEP-04', 'Marketing', 650000, 'New York'),
  ('DEP-05', 'Finance', 700000, 'London')
on conflict ("Dept_ID") do nothing;

insert into public."Job_Titles" ("Title_ID", "Job_Title", "Base_Salary_Min", "Base_Salary_Max") values
  ('JOB-001', 'People Director', 110000, 160000),
  ('JOB-002', 'Staff Engineer', 130000, 190000),
  ('JOB-003', 'Product Designer', 85000, 135000),
  ('JOB-004', 'Marketing Manager', 90000, 145000),
  ('JOB-005', 'Financial Analyst', 70000, 110000),
  ('JOB-006', 'Software Engineer', 95000, 160000)
on conflict ("Title_ID") do nothing;

insert into public."Employees" (
  "Employee_ID", "First_Name", "Last_Name", "Email", "Phone_Number", "Gender",
  "Date_of_Birth", "Date_of_Joining", "Dept_ID", "Title_ID", "Manager_ID",
  "Employment_Status", "Work_Location"
) values
  ('EMP-100001', 'Avery', 'Morgan', 'avery.morgan@example.com', '+1 202 555 0101', 'Female', '1988-04-10', '2021-03-15', 'DEP-01', 'JOB-001', null, 'Active', 'Hybrid'),
  ('EMP-100002', 'Jordan', 'Lee', 'jordan.lee@example.com', '+1 202 555 0102', 'Male', '1990-09-22', '2022-06-01', 'DEP-02', 'JOB-002', 'EMP-100001', 'Active', 'Remote'),
  ('EMP-100003', 'Riley', 'Parker', 'riley.parker@example.com', '+1 202 555 0103', 'Non-binary', '1995-01-14', '2023-01-09', 'DEP-03', 'JOB-003', 'EMP-100001', 'Active', 'Office'),
  ('EMP-100004', 'Casey', 'Reed', 'casey.reed@example.com', '+1 202 555 0104', 'Female', '1992-07-30', '2022-10-17', 'DEP-04', 'JOB-004', 'EMP-100001', 'Active', 'Hybrid'),
  ('EMP-100005', 'Taylor', 'Wright', 'taylor.wright@example.com', '+1 202 555 0105', 'Male', '1997-02-05', '2024-02-12', 'DEP-05', 'JOB-005', 'EMP-100001', 'Active', 'Office'),
  ('EMP-100006', 'Quinn', 'Brooks', 'quinn.brooks@example.com', '+1 202 555 0106', 'Other', '1996-11-11', '2024-08-05', 'DEP-02', 'JOB-006', 'EMP-100002', 'Active', 'Remote')
on conflict ("Employee_ID") do nothing;

insert into public."Salaries_And_Compensation" (
  "Record_ID", "Employee_ID", "Base_Salary", "Bonus_Percentage", "Medical_Allowance", "Tax_Deduction"
) values
  ('SAL-000001', 'EMP-100001', 138000, 10, 2400, 18000),
  ('SAL-000002', 'EMP-100002', 155000, 12.5, 2400, 22000),
  ('SAL-000003', 'EMP-100003', 112000, 8, 1800, 14500),
  ('SAL-000004', 'EMP-100004', 118000, 10, 2400, 16000),
  ('SAL-000005', 'EMP-100005', 92000, 5, 1800, 11000),
  ('SAL-000006', 'EMP-100006', 125000, 8, 2400, 17000)
on conflict ("Record_ID") do nothing;

insert into public."Attendance_And_Leave" (
  "Record_ID", "Employee_ID", "Total_Working_Days", "Days_Present", "Days_Absent", "Paid_Leaves"
) values
  ('ATT-000001', 'EMP-100001', 220, 210, 4, 6),
  ('ATT-000002', 'EMP-100002', 220, 205, 8, 7),
  ('ATT-000003', 'EMP-100003', 220, 212, 3, 5),
  ('ATT-000004', 'EMP-100004', 220, 206, 7, 7),
  ('ATT-000005', 'EMP-100005', 220, 214, 2, 4),
  ('ATT-000006', 'EMP-100006', 220, 208, 6, 6)
on conflict ("Record_ID") do nothing;

select setval(
  'public.departments_dept_id_seq',
  greatest(coalesce(max(substring("Dept_ID" from '[0-9]+$')::bigint), 1), 1),
  count(*) > 0
) from public."Departments";
select setval(
  'public.job_titles_title_id_seq',
  greatest(coalesce(max(substring("Title_ID" from '[0-9]+$')::bigint), 1), 1),
  count(*) > 0
) from public."Job_Titles";
select setval(
  'public.employees_employee_id_seq',
  greatest(coalesce(max(substring("Employee_ID" from '[0-9]+$')::bigint), 100000), 100000),
  count(*) > 0
) from public."Employees";
select setval(
  'public.salaries_record_id_seq',
  greatest(coalesce(max(substring("Record_ID" from '[0-9]+$')::bigint), 1), 1),
  count(*) > 0
) from public."Salaries_And_Compensation";
select setval(
  'public.attendance_record_id_seq',
  greatest(coalesce(max(substring("Record_ID" from '[0-9]+$')::bigint), 1), 1),
  count(*) > 0
) from public."Attendance_And_Leave";
