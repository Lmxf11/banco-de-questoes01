-- ============================================
-- SQL SETUP — Mesa de Estudos (Novo Projeto)
-- Projeto: mjntpsriejgadxhmbngq
-- Execute no SQL Editor do Supabase
-- ============================================

-- PASSO 1: Adicionar colunas display_name e avatar_url na tabela users
-- (Se a tabela users ainda nao existe, crie:)
CREATE TABLE IF NOT EXISTS public.users (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email TEXT,
  role TEXT DEFAULT 'user',
  display_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Se a tabela ja existe sem as colunas, adicione:
-- ALTER TABLE public.users ADD COLUMN IF NOT EXISTS display_name TEXT;
-- ALTER TABLE public.users ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- PASSO 2: Funcao trigger — sincroniza auth.users com public.users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, email, role, display_name)
  VALUES (
    NEW.id,
    NEW.email,
    'user',
    COALESCE(NEW.raw_user_meta_data->>'nome', NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1))
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    display_name = COALESCE(EXCLUDED.display_name, public.users.display_name);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- PASSO 3: Conectar trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT OR UPDATE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- PASSO 4: RLS — users
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own profile" ON public.users FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.users FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Admins can read all users" ON public.users FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
);

-- PASSO 5: RLS — respostas
ALTER TABLE public.respostas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users read own respostas" ON public.respostas FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users insert own respostas" ON public.respostas FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users update own respostas" ON public.respostas FOR UPDATE USING (auth.uid() = user_id);

-- PASSO 6: RLS — desempenho
ALTER TABLE public.desempenho ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users read own desempenho" ON public.desempenho FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users insert own desempenho" ON public.desempenho FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users update own desempenho" ON public.desempenho FOR UPDATE USING (auth.uid() = user_id);

-- PASSO 7: RLS — questoes
ALTER TABLE public.questoes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read questoes" ON public.questoes FOR SELECT USING (true);
CREATE POLICY "Admins can insert questoes" ON public.questoes FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY "Admins can update questoes" ON public.questoes FOR UPDATE USING (
  EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY "Admins can delete questoes" ON public.questoes FOR DELETE USING (
  EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
);

-- PASSO 8: Criar bucket de storage para avatares
-- Execute no Supabase Dashboard → Storage → New bucket:
--   Nome: avatars
--   Public: YES
-- Ou execute via API/SQL:
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

-- RLS para storage avatars
CREATE POLICY "Users can upload own avatar" ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1]
);
CREATE POLICY "Users can update own avatar" ON storage.objects FOR UPDATE USING (
  bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1]
);
CREATE POLICY "Anyone can view avatars" ON storage.objects FOR SELECT USING (
  bucket_id = 'avatars'
);
CREATE POLICY "Users can delete own avatar" ON storage.objects FOR DELETE USING (
  bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1]
);

-- ============================================
-- PARA CONFIGURAR ADMIN:
-- 1. Faca cadastro normal no site
-- 2. Execute no SQL Editor:
-- UPDATE public.users SET role = 'admin' WHERE email = 'seu-email@exemplo.com';
-- ============================================
