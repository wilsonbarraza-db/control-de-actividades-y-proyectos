-- Control de Actividades y Proyectos
-- Ejecutar en el SQL Editor de Supabase (proyecto helena)

-- Crear esquema propio
create schema if not exists helena;

set search_path = helena, public;

-- 1) Perfiles de usuario con roles
create table if not exists helena.profiles (
  id uuid references auth.users on delete cascade primary key,
  email text,
  display_name text,
  avatar_url text,
  role text not null default 'member',
  created_at timestamptz default now()
);

alter table helena.profiles enable row level security;

create policy "Users read own profile" on helena.profiles for select using (auth.uid() = id);
create policy "Users update own profile" on helena.profiles for update using (auth.uid() = id);

-- 2) Proyectos con información de negocio
create table if not exists helena.projects (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  slug text not null unique,
  description text,
  status text not null default 'active',
  client text,
  budget numeric,
  currency text not null default 'CLP',
  start_date date,
  end_date date,
  created_by uuid references auth.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table helena.projects enable row level security;

create policy "Members view project" on helena.projects for select using (
  exists (
    select 1 from helena.project_members pm
    where pm.project_id = helena.projects.id and pm.user_id = auth.uid()
  )
  or exists (
    select 1 from helena.profiles p
    where p.id = auth.uid() and p.role in ('admin', 'manager')
  )
);

create policy "Managers create project" on helena.projects for insert with check (
  exists (
    select 1 from helena.profiles p
    where p.id = auth.uid() and p.role in ('admin', 'manager')
  )
);

create policy "Managers update project" on helena.projects for update using (
  exists (
    select 1 from helena.profiles p
    where p.id = auth.uid() and p.role in ('admin', 'manager')
  )
);

create policy "Admins delete project" on helena.projects for delete using (
  exists (
    select 1 from helena.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);

-- 3) Miembros de proyecto con roles específicos
create table if not exists helena.project_members (
  id uuid default gen_random_uuid() primary key,
  project_id uuid references helena.projects(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  role text not null default 'member',
  hourly_rate numeric,
  joined_at timestamptz default now(),
  unique(project_id, user_id)
);

alter table helena.project_members enable row level security;

create policy "Members view membership" on helena.project_members for select using (
  exists (
    select 1 from helena.profiles p
    where p.id = auth.uid() and p.role in ('admin', 'manager')
  )
  or user_id = auth.uid()
);

create policy "Managers manage members" on helena.project_members for all using (
  exists (
    select 1 from helena.profiles p
    where p.id = auth.uid() and p.role in ('admin', 'manager')
  )
);

-- 4) Tareas con costos estimados
create table if not exists helena.tasks (
  id uuid default gen_random_uuid() primary key,
  project_id uuid references helena.projects(id) on delete cascade not null,
  title text not null,
  description text,
  status text not null default 'todo',
  priority text not null default 'medium',
  estimated_hours numeric,
  cost_type text not null default 'hourly',
  cost_value numeric not null default 0,
  assigned_to uuid references auth.users(id),
  created_by uuid references auth.users(id),
  due_date date,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table helena.tasks enable row level security;

create policy "Members view tasks" on helena.tasks for select using (
  exists (
    select 1 from helena.project_members pm
    where pm.project_id = helena.tasks.project_id and pm.user_id = auth.uid()
  )
  or exists (
    select 1 from helena.profiles p
    where p.id = auth.uid() and p.role in ('admin', 'manager')
  )
);

create policy "Members create tasks" on helena.tasks for insert with check (
  exists (
    select 1 from helena.project_members pm
    where pm.project_id = helena.tasks.project_id and pm.user_id = auth.uid()
  )
  or exists (
    select 1 from helena.profiles p
    where p.id = auth.uid() and p.role in ('admin', 'manager')
  )
);

create policy "Members update tasks" on helena.tasks for update using (
  exists (
    select 1 from helena.project_members pm
    where pm.project_id = helena.tasks.project_id and pm.user_id = auth.uid()
  )
  or exists (
    select 1 from helena.profiles p
    where p.id = auth.uid() and p.role in ('admin', 'manager')
  )
);

create policy "Managers delete tasks" on helena.tasks for delete using (
  exists (
    select 1 from helena.profiles p
    where p.id = auth.uid() and p.role in ('admin', 'manager')
  )
);

-- 5) Registro de horas por tarea y usuario
create table if not exists helena.time_entries (
  id uuid default gen_random_uuid() primary key,
  task_id uuid references helena.tasks(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  project_id uuid references helena.projects(id) on delete cascade not null,
  date date not null,
  hours numeric not null,
  notes text,
  created_at timestamptz default now()
);

alter table helena.time_entries enable row level security;

create policy "Users view own entries" on helena.time_entries for select using (
  user_id = auth.uid()
  or exists (
    select 1 from helena.profiles p
    where p.id = auth.uid() and p.role in ('admin', 'manager')
  )
);

create policy "Users create own entries" on helena.time_entries for insert with check (user_id = auth.uid());
create policy "Users update own entries" on helena.time_entries for update using (user_id = auth.uid());
create policy "Users delete own entries" on helena.time_entries for delete using (user_id = auth.uid());

-- 6) Tarifas por usuario para cálculo de costos
create table if not exists helena.user_cost_rates (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade unique not null,
  rate numeric not null default 0,
  currency text not null default 'CLP',
  updated_at timestamptz default now()
);

alter table helena.user_cost_rates enable row level security;

create policy "Users view own rate" on helena.user_cost_rates for select using (
  user_id = auth.uid()
  or exists (
    select 1 from helena.profiles p
    where p.id = auth.uid() and p.role in ('admin', 'manager')
  )
);

create policy "Managers manage rates" on helena.user_cost_rates for all using (
  exists (
    select 1 from helena.profiles p
    where p.id = auth.uid() and p.role in ('admin', 'manager')
  )
);

-- 7) Trigger para updated_at automático
create or replace function helena.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists set_projects_updated_at on helena.projects;
create trigger set_projects_updated_at before update on helena.projects for each row execute procedure helena.set_updated_at();

drop trigger if exists set_tasks_updated_at on helena.tasks;
create trigger set_tasks_updated_at before update on helena.tasks for each row execute procedure helena.set_updated_at();

-- 8) Datos iniciales de prueba
insert into helena.profiles (id, email, role)
values
  ('00000000-0000-0000-0000-000000000001', 'admin@example.com', 'admin'),
  ('00000000-0000-0000-0000-000000000002', 'manager@example.com', 'manager'),
  ('00000000-0000-0000-0000-000000000003', 'member@example.com', 'member')
on conflict (id) do nothing;

insert into helena.projects (id, name, slug, description, status, created_by)
values
  ('00000000-0000-0000-0000-000000000101', 'Bluewayone', 'bluewayone', 'Proyecto Bluewayone', 'active', '00000000-0000-0000-0000-000000000002'),
  ('00000000-0000-0000-0000-000000000102', 'kalu', 'kalu', 'Proyecto kalu', 'active', '00000000-0000-0000-0000-000000000002'),
  ('00000000-0000-0000-0000-000000000103', 'cronos', 'cronos', 'Proyecto cronos', 'paused', '00000000-0000-0000-0000-000000000002'),
  ('00000000-0000-0000-0000-000000000104', 'lanudo', 'lanudo', 'Proyecto lanudo', 'active', '00000000-0000-0000-0000-000000000002')
on conflict (id) do nothing;

insert into helena.project_members (project_id, user_id, role)
values
  ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000002', 'manager'),
  ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000003', 'member'),
  ('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000002', 'manager'),
  ('00000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000002', 'manager'),
  ('00000000-0000-0000-0000-000000000104', '00000000-0000-0000-0000-000000000002', 'manager')
on conflict (project_id, user_id) do nothing;
