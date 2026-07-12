-- Migration: Add tutor RLS policies for messages and storage.objects
-- Context: The tutor role was added with a get_tutor_student_ids() helper
-- function and read access on `messages` was implicitly relied upon, but
-- no explicit INSERT/SELECT policies existed for tutors on either the
-- messages table or the channel-files storage bucket. This caused:
--   - "new row violates row-level security policy for table messages"
--     (code 42501) when a tutor tried to send a message
--   - Images/files silently failing to load for tutor logins
--     (createSignedUrl rejected by storage.objects RLS)
--
-- These policies mirror the existing admin/student policies, scoped
-- through get_tutor_student_ids(auth.uid()) instead of a flat role check
-- or a path-prefix check.

-- ============================================================
-- messages table
-- ============================================================

-- Allow tutors to send messages to their assigned students
CREATE POLICY "Tutor can send messages"
ON messages
FOR INSERT
WITH CHECK (
  student_id IN (SELECT get_tutor_student_ids(auth.uid()))
  AND sent_by = auth.uid()
  AND sender_role = 'tutor'::message_sender
);

-- Allow tutors to view messages for their assigned students
CREATE POLICY "Tutor can view assigned student messages"
ON messages
FOR SELECT
USING (
  student_id IN (SELECT get_tutor_student_ids(auth.uid()))
);

-- ============================================================
-- storage.objects (channel-files bucket)
-- ============================================================

-- Allow tutors to upload files. Tutor/admin uploads are stored under
-- their own auth.uid() as the path prefix (not the student's), so this
-- mirrors "Admin can upload files" (role check) rather than
-- "Students can upload files" (path-prefix check).
CREATE POLICY "Tutor can upload files"
ON storage.objects
FOR INSERT
WITH CHECK (
  bucket_id = 'channel-files'
  AND EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid() AND profiles.role = 'tutor'::user_role
  )
);

-- Allow tutors to view files belonging to their assigned students'
-- messages (mirrors "Students can view own files", scoped via
-- get_tutor_student_ids instead of student_id = auth.uid()).
CREATE POLICY "Tutor can view assigned student files"
ON storage.objects
FOR SELECT
USING (
  bucket_id = 'channel-files'
  AND EXISTS (
    SELECT 1 FROM messages m
    WHERE m.file_path = objects.name
    AND m.student_id IN (SELECT get_tutor_student_ids(auth.uid()))
  )
);
