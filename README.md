# Control de Actividades y Proyectos

App web multi-usuario para registro de tareas, horas, seguimiento de proyectos y evaluación de costos.

## Stack
- Backend: Supabase (PostgreSQL + Auth + RLS)
- Frontend: HTML/JS vanilla en app/index.html
- Despliegue: Vercel

## Pasos
1. Crear proyecto en Supabase
2. Ejecutar supabase/schema.sql en SQL Editor
3. Configurar Auth en Supabase (Email/Google/etc.)
4. Reemplazar en app/index.html:
   - __SUPABASE_URL__
   - __SUPABASE_ANON_KEY__
5. Push a Vercel

## Rol inicial
- El primer usuario creado se le asigna role = 'manager'
- admin/manager pueden crear proyectos y asignar miembros
- member puede ver proyectos asignados y cargar horas
