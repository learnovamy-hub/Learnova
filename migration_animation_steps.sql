-- Run this in Supabase Dashboard > SQL Editor
-- Adds animation columns to learning_standards table

ALTER TABLE public.learning_standards
  ADD COLUMN IF NOT EXISTS animation_steps JSONB,
  ADD COLUMN IF NOT EXISTS animation_alt_steps JSONB;

-- Verify
SELECT COUNT(*) AS total_standards,
       COUNT(animation_steps) AS with_animations
FROM public.learning_standards;
