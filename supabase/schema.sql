CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
  email text,
  role text NOT NULL DEFAULT 'member',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);

CREATE TABLE IF NOT EXISTS public.projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  status text NOT NULL DEFAULT 'active',
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members view project" ON public.projects FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.project_members pm
    WHERE pm.project_id = public.projects.id AND pm.user_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role IN ('admin','manager')
  )
);
CREATE POLICY "Managers create project" ON public.projects FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('admin','manager'))
);
CREATE POLICY "Managers update project" ON public.projects FOR UPDATE USING (
  EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('admin','manager'))
);
CREATE POLICY "Admins delete project" ON public.projects FOR DELETE USING (
  EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin')
);

CREATE TABLE IF NOT EXISTS public.project_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid REFERENCES public.projects(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  role text NOT NULL DEFAULT 'member',
  joined_at timestamptz DEFAULT now(),
  UNIQUE(project_id, user_id)
);

ALTER TABLE public.project_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members view membership" ON public.project_members FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('admin','manager'))
  OR user_id = auth.uid()
);
CREATE POLICY "Managers manage members" ON public.project_members FOR ALL USING (
  EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('admin','manager'))
);

CREATE TABLE IF NOT EXISTS public.tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid REFERENCES public.projects(id) ON DELETE CASCADE NOT NULL,
  title text NOT NULL,
  description text,
  status text NOT NULL DEFAULT 'todo',
  priority text NOT NULL DEFAULT 'medium',
  estimated_hours numeric,
  cost_type text NOT NULL DEFAULT 'hourly',
  cost_value numeric NOT NULL DEFAULT 0,
  assigned_to uuid REFERENCES auth.users(id),
  created_by uuid REFERENCES auth.users(id),
  due_date date,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members view tasks" ON public.tasks FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.project_members pm
    WHERE pm.project_id = public.tasks.project_id AND pm.user_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role IN ('admin','manager')
  )
);
CREATE POLICY "Members create tasks" ON public.tasks FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.project_members pm
    WHERE pm.project_id = public.tasks.project_id AND pm.user_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role IN ('admin','manager')
  )
);
CREATE POLICY "Members update tasks" ON public.tasks FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM public.project_members pm
    WHERE pm.project_id = public.tasks.project_id AND pm.user_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role IN ('admin','manager')
  )
);
CREATE POLICY "Managers delete tasks" ON public.tasks FOR DELETE USING (
  EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('admin','manager'))
);

CREATE TABLE IF NOT EXISTS public.time_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid REFERENCES public.tasks(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  project_id uuid REFERENCES public.projects(id) ON DELETE CASCADE NOT NULL,
  date date NOT NULL,
  hours numeric NOT NULL,
  notes text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.time_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own entries" ON public.time_entries FOR SELECT USING (
  user_id = auth.uid()
  OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('admin','manager'))
);
CREATE POLICY "Users create own entries" ON public.time_entries FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "Users update own entries" ON public.time_entries FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "Users delete own entries" ON public.time_entries FOR DELETE USING (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.user_cost_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE NOT NULL,
  rate numeric NOT NULL DEFAULT 0,
  currency text NOT NULL DEFAULT 'CLP',
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.user_cost_rates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own rate" ON public.user_cost_rates FOR SELECT USING (
  user_id = auth.uid()
  OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('admin','manager'))
);
CREATE POLICY "Managers manage rates" ON public.user_cost_rates FOR ALL USING (
  EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('admin','manager'))
);

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
  new.updated_at = now();
  RETURN new;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_projects_updated_at ON public.projects;
CREATE TRIGGER set_projects_updated_at BEFORE UPDATE ON public.projects FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

DROP TRIGGER IF EXISTS set_tasks_updated_at ON public.tasks;
CREATE TRIGGER set_tasks_updated_at BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

INSERT INTO public.profiles (id, email, role)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'admin@example.com', 'admin'),
  ('00000000-0000-0000-0000-000000000002', 'manager@example.com', 'manager'),
  ('00000000-0000-0000-0000-000000000003', 'member@example.com', 'member')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.projects (id, name, description, status, created_by)
VALUES
  ('00000000-0000-0000-0000-000000000101', 'Bluewayone', 'Proyecto Bluewayone', 'active', '00000000-0000-0000-0000-000000000002'),
  ('00000000-0000-0000-0000-000000000102', 'kalu', 'Proyecto kalu', 'active', '00000000-0000-0000-0000-000000000002'),
  ('00000000-0000-0000-0000-000000000103', 'cronos', 'Proyecto cronos', 'paused', '00000000-0000-0000-0000-000000000002'),
  ('00000000-0000-0000-0000-000000000104', 'lanudo', 'Proyecto lanudo', 'active', '00000000-0000-0000-0000-000000000002')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.project_members (project_id, user_id, role)
VALUES
  ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000002', 'manager'),
  ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000003', 'member'),
  ('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000002', 'manager'),
  ('00000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000002', 'manager'),
  ('00000000-0000-0000-0000-000000000104', '00000000-0000-0000-0000-000000000002', 'manager')
ON CONFLICT (project_id, user_id) DO NOTHING;
