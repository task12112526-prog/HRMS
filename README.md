# PeopleOS HRMS

A responsive React + TypeScript HR workspace built with Vite, MUI, React Router, TanStack Query, React Hook Form, Zod, and Supabase.

## Run locally

Requirements: Node.js 22+ and npm.

```sh
npm install
npm run dev
```

Set `.env.local` at the project root:

```dotenv
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-supabase-publishable-key
VITE_CURRENCY=USD
```

Restart Vite after changing environment values. The URL and publishable key are browser-visible credentials; database RLS provides access control. **Never use or expose your Supabase `service_role` or secret key in the frontend, environment file, or browser.**

Passwords are managed by **Supabase Authentication**. They are not stored in any of the five HRMS tables, and should never be added to the database or shared with the application. Create/invite user accounts in Supabase Authentication; users sign in with the password they set there.

## Secure the existing five-table schema

The project is expected to already contain the five exact, quoted tables and columns below. This migration is an **upgrade and security-hardening script**, not a table-creation schema. It checks that every required table/column exists and stops with an error if the schema does not match.

In the Supabase Dashboard, open **SQL Editor → New query** and run the full contents of [`supabase/migrations/20261018000000_hrms_exact_schema.sql`](./supabase/migrations/20261018000000_hrms_exact_schema.sql). It is safe to re-run: it preserves table rows, sets ID defaults/sequences, adds constraints/indexes when missing, and configures RLS and grants. Re-run it after app updates that add database functions/indexes. Do not run the previous lowercase-schema migration or mix schema versions.

If that migration was already applied before the net-salary rounding fix, run [`supabase/migrations/20261103000000_fix_net_salary_rounding.sql`](./supabase/migrations/20261103000000_fix_net_salary_rounding.sql) in SQL Editor before retrying the seed. It replaces only the salary trigger function and does not change or delete table data.

**Policy impact:** to prevent an older permissive RLS policy from widening access, the migration replaces all existing RLS policies on these five tables with its named policies. It also revokes `PUBLIC` and `anon` table/sequence privileges and grants access to `authenticated` only. Review any custom policies on these five tables before running; policies on other tables are not changed. Existing rows are not deleted, and new check/foreign-key constraints are added `NOT VALID` so legacy rows are retained while new/updated rows are checked. Resolve any errors reported by Supabase before relying on the application.

| Supabase table | Purpose |
| --- | --- |
| `"Departments"` | `Dept_ID`, `Dept_Name`, `Budget`, `Location` |
| `"Job_Titles"` | `Title_ID`, `Job_Title`, `Base_Salary_Min`, `Base_Salary_Max` |
| `"Employees"` | Exact employee profile, department/title/manager IDs, employment status, and work location fields |
| `"Salaries_And_Compensation"` | Base salary, bonus percentage, medical allowance, tax deduction, net salary |
| `"Attendance_And_Leave"` | Aggregate working days, presence, absences, paid leave, and attendance percentage |

All five tables must use the exact casing and column names in the supplied specification. The migration sets text-ID defaults in the requested formats (`DEP-01`, `JOB-001`, `EMP-100001`, `SAL-000001`, `ATT-000001`) and synchronizes their sequences past existing IDs. It adds foreign keys and lookup indexes when missing, including trigram indexes for fast employee-name/email search. `Net_Salary` and `Attendance_Percentage` are computed in PostgreSQL: existing generated columns are left intact; ordinary columns are maintained by triggers. The formulas are base salary + base salary × bonus percentage + medical allowance − tax deduction, and days present ÷ total working days × 100 (zero when working days are zero).

The migration turns on RLS for all five tables and keeps employee, compensation, and attendance records restricted to HR/Admin or the employee whose authenticated email matches the employee record. Department and job-title lookups are readable by authenticated team members. Employee self-service updates are limited to their own phone and gender; a database trigger prevents changes to employment details. RLS alone is not a substitute for legal/payroll compliance review.

For faster HR dashboard loading, the migration also adds the `hrms_dashboard_summary()` database function. The app uses it for aggregated employee, attendance, and team counts rather than downloading full tables. The employee directory, attendance/payroll lists, and large reports use server-side pagination; full report datasets are fetched only after explicitly choosing CSV/PDF export.

## Login and role setup

1. Enable email/password authentication in Supabase **Authentication → Sign In / Providers**, and configure your local and deployed URLs under **Authentication → URL Configuration**.
2. In **Authentication → Users**, invite or create your first account. Set its password there, or let Supabase send an invitation/recovery email for the user to choose one.
3. An employee login is linked to `"Employees"` by an exact, lowercased email match. Create their employee row with the **same verified email** as their Supabase login.
4. Roles are read from the JWT's trusted `app_metadata.role`, never from user-editable `user_metadata`. A user with no assigned app-metadata role defaults to `employee`.
5. To grant your first account administrator access, replace the email in this SQL and run it in the Supabase SQL Editor:

   ```sql
   update auth.users
   set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
     || jsonb_build_object('role', 'admin')
   where lower(email) = lower('you@your-company.com');
   ```

   Promote People team accounts with `'hr_manager'` instead. This query changes Auth metadata, **not the HRMS tables**. Sign out and sign in again to receive a JWT containing the new role. Never give staff an admin role just to make a feature work.

6. Configure Supabase password recovery email templates and your actual domain before real users depend on the forgot-password flow.

There is deliberately **no `user_roles` table** in this five-table version. Employees can see their own employee, salary, and attendance records using their Auth email; administrators and HR managers receive wider access through server-verified Auth `app_metadata` claims and RLS. Editing `user_metadata` from the application will never grant a privileged role.

## Seed data

For a development preview only, run [`supabase/seed.sql`](./supabase/seed.sql) after the migration. It creates fictional example employees, salaries, departments, job titles, and attendance summaries with reserved `example.com` email addresses. It does not create login accounts or passwords. **Do not seed fictitious rows into a production HR system.**

## What the exact five tables support

- HR/Admin CRUD for employees, departments, and job titles; filters, employee lookup, generated IDs, and foreign-key relationships.
- Employee directory uses server-side search, department/status filters, sortable columns, and 10/25/50-row pagination. Searches wait for at least three characters and are debounced; employee pickers also debounce server searches and load only matching options rather than downloading the full directory.
- Employee and HR/Admin access boundaries enforced in PostgreSQL with RLS. Employee self-service profile updates are limited to phone number and gender.
- Compensation records and printable statements, with net salary computed by PostgreSQL and scoped to the employee.
- Attendance/paid-leave **summary** entry and reporting; attendance percentage is computed by PostgreSQL.
- Employee, department, job-title, compensation, and attendance-summary reporting as CSV and print-to-PDF.
- Responsive MUI workspace, dashboard, role-protected routes, and Supabase email/password, logout, recovery, and password-change flows.

### Explicit limits of the supplied schema

The app does not invent database fields that do not exist. As supplied, these five tables cannot represent:

- Leave applications, individual approval/rejection, review notes, balances by leave type, or leave notifications. `Paid_Leaves` is only an aggregate integer.
- Daily clock-in/clock-out records: the attendance table has no work date or timestamps.
- Monthly/dated payroll runs, payment status/payment dates, or a dated pay history. Salary rows have no pay-period or creation-date column; printable statements are identified by `Record_ID` and are not evidence of when compensation was paid.
- Employee profile photos, addresses, emergency contacts, or uploaded documents.
- Period labels for attendance summaries: the table has no month, year, or date column.

Those modules are hidden or limited rather than backed by demo or fabricated records. To enable them, add date/period and workflow fields to your agreed schema or approve additional supporting tables first.

## Build and Vercel

```sh
npm run build
```

In Vercel, import the project using the **Vite** preset, build command `npm run build`, and output directory `dist`. Add `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, and (optionally) the three-letter `VITE_CURRENCY` for Production/Preview/Development. Add the production domain to Supabase Authentication’s site URL and redirect allowlist. [`vercel.json`](./vercel.json) provides the React Router SPA fallback.

## Project layout

```text
src/
  app/                 Routes and responsive application shell
  components/          Shared user-interface components
  features/
    auth/              Supabase Auth provider, forms, and protected routes
    attendance/        Aggregate attendance and leave summaries
    dashboard/         Role-aware HR/employee dashboard
    departments/       Department and budget management
    employees/         Employee directory, CRUD, and self-service profile
    jobs/              Job title and base salary range lookup
    payroll/           Salary components and printable statements
    reports/           Five-table reports, CSV and print-to-PDF
  lib/                 Supabase client and format helpers
  services/            Typed Supabase repository layer
supabase/
  migrations/          Existing-schema upgrade, defaults, constraints, and RLS
  seed.sql             Optional fictional development data
```
