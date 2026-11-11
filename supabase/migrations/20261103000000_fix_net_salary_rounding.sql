-- Fix salary calculation when source columns are double precision.
-- round(numeric, integer) is the PostgreSQL overload that accepts 2 decimals.
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
