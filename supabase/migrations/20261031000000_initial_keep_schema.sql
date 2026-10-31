-- =============================================================================
-- Google Keep Clone — Supabase Postgres Schema, RLS Policies & Storage Buckets
-- =============================================================================

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- 1. NOTES TABLE
create table if not exists public.notes (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    title text not null default '',
    content text not null default '',
    rich_spans jsonb not null default '[]'::jsonb,
    is_checklist boolean not null default false,
    checklist_items jsonb not null default '[]'::jsonb,
    color_id text not null default 'default',
    background_theme text not null default 'none',
    is_pinned boolean not null default false,
    is_archived boolean not null default false,
    is_trashed boolean not null default false,
    trashed_at timestamptz,
    is_locked boolean not null default false,
    sort_order double precision not null default 0,
    reminder_at timestamptz,
    reminder_recurrence text not null default 'none',
    reminder_location jsonb,
    link_previews jsonb not null default '[]'::jsonb,
    labels jsonb not null default '[]'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists idx_notes_user_updated on public.notes(user_id, updated_at desc);
create index if not exists idx_notes_user_trashed on public.notes(user_id, is_trashed);

-- 2. NOTE ATTACHMENTS TABLE
create table if not exists public.note_attachments (
    id uuid primary key,
    note_id uuid not null references public.notes(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    type text not null check (type in ('image', 'drawing', 'audio')),
    remote_storage_path text,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists idx_note_attachments_note_id on public.note_attachments(note_id);
create index if not exists idx_note_attachments_user_id on public.note_attachments(user_id);

-- 3. LABELS TABLE
create table if not exists public.labels (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (user_id, name)
);

create index if not exists idx_labels_user_id on public.labels(user_id);

-- 4. ROW LEVEL SECURITY (RLS)
alter table public.notes enable row level security;
alter table public.note_attachments enable row level security;
alter table public.labels enable row level security;

-- Notes policies
create policy "Users can view their own notes"
    on public.notes for select
    using (auth.uid() = user_id);

create policy "Users can insert their own notes"
    on public.notes for insert
    with check (auth.uid() = user_id);

create policy "Users can update their own notes"
    on public.notes for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create policy "Users can delete their own notes"
    on public.notes for delete
    using (auth.uid() = user_id);

-- Note attachments policies
create policy "Users can view their own attachments"
    on public.note_attachments for select
    using (auth.uid() = user_id);

create policy "Users can insert their own attachments"
    on public.note_attachments for insert
    with check (auth.uid() = user_id);

create policy "Users can update their own attachments"
    on public.note_attachments for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create policy "Users can delete their own attachments"
    on public.note_attachments for delete
    using (auth.uid() = user_id);

-- Labels policies
create policy "Users can view their own labels"
    on public.labels for select
    using (auth.uid() = user_id);

create policy "Users can insert their own labels"
    on public.labels for insert
    with check (auth.uid() = user_id);

create policy "Users can update their own labels"
    on public.labels for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create policy "Users can delete their own labels"
    on public.labels for delete
    using (auth.uid() = user_id);

-- 5. REALTIME SUBSCRIPTIONS
alter publication supabase_realtime add table public.notes;
alter publication supabase_realtime add table public.note_attachments;
alter publication supabase_realtime add table public.labels;

-- 6. STORAGE BUCKET FOR MEDIA ATTACHMENTS (Images, Drawings, Audio)
insert into storage.buckets (id, name, public)
values ('keep-attachments', 'keep-attachments', false)
on conflict (id) do nothing;

create policy "Users can upload their own keep attachments"
    on storage.objects for insert
    with check (
        bucket_id = 'keep-attachments'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

create policy "Users can view their own keep attachments"
    on storage.objects for select
    using (
        bucket_id = 'keep-attachments'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

create policy "Users can update their own keep attachments"
    on storage.objects for update
    using (
        bucket_id = 'keep-attachments'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

create policy "Users can delete their own keep attachments"
    on storage.objects for delete
    using (
        bucket_id = 'keep-attachments'
        and auth.uid()::text = (storage.foldername(name))[1]
    );
