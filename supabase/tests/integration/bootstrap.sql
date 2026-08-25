-- Bootstrap for the media-cleanup worker integration test.
insert into auth.users (id, email)
values ('00000000-0000-0000-0000-00000000c13a', 'media-cleanup-integration@example.com')
on conflict (id) do nothing;
