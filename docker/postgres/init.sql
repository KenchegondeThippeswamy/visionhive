create table if not exists videos (
  id uuid primary key,
  filename text not null,
  s3_key text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now()
);
create table if not exists detections (
  id serial primary key,
  video_id uuid references videos(id),
  label text not null,
  confidence real not null,
  frame int not null
);
