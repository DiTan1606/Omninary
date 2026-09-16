import { User } from '@supabase/supabase-js';
import { Check, Eye, EyeOff, Loader2 } from 'lucide-react';
import { FormEvent, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Profile } from '../lib/types';

type AuthScreenProps = {
  authError?: string;
  onAuthenticated: (profile: Profile) => void;
};

function profileDestination(profile: Profile) {
  return profile.role === 'admin' ? '/admin' : '/app';
}

function routeAuthenticatedProfile(profile: Profile, onAuthenticated: (profile: Profile) => void) {
  const destination = profileDestination(profile);
  if (!window.location.pathname.startsWith(destination)) {
    window.location.assign(destination);
    return;
  }
  onAuthenticated(profile);
}

async function fetchProfile(userId: string) {
  const { data, error } = await supabase
    .from('profiles')
    .select('id,email,display_name,avatar_url,role,created_at')
    .eq('id', userId)
    .maybeSingle<Profile>();

  if (error) throw error;
  return data;
}

async function waitForProfile(user: User) {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const profile = await fetchProfile(user.id);
    if (profile) return profile;
    await new Promise((resolve) => window.setTimeout(resolve, 350));
  }
  throw new Error('Tài khoản đã tạo nhưng chưa có hồ sơ người dùng. Vui lòng thử đăng nhập lại sau vài giây.');
}

function BrandLogo() {
  return (
    <div className="brand">
      <img className="brand-logo" src="/ditanary-logo.png" alt="Ditandnary thuộc Omninary" />
    </div>
  );
}

export default function AuthScreen({ authError = '', onAuthenticated }: AuthScreenProps) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState(authError);

  useEffect(() => {
    setError(authError);
  }, [authError]);

  async function login() {
    const { data, error: signInError } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password
    });
    if (signInError) throw signInError;
    if (!data.user) throw new Error('Không tìm thấy tài khoản.');
    const profile = await waitForProfile(data.user);
    routeAuthenticatedProfile(profile, onAuthenticated);
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    setIsLoading(true);
    setError('');

    try {
      await login();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Đăng nhập thất bại.');
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <div className="login-page">
      <form className="login-panel" onSubmit={submit}>
        <BrandLogo />

        <label>
          Email
          <input value={email} onChange={(event) => setEmail(event.target.value)} type="email" autoComplete="email" />
        </label>

        <label>
          Mật khẩu
          <div className="password-field">
            <input
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              type={showPassword ? 'text' : 'password'}
              autoComplete="current-password"
            />
            <button type="button" onClick={() => setShowPassword((value) => !value)} title="Hiển thị mật khẩu">
              {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
            </button>
          </div>
        </label>

        {error && <div className="form-error">{error}</div>}

        <button className="primary-button" disabled={isLoading || !email || !password}>
          {isLoading ? <Loader2 className="spin" size={18} /> : <Check size={18} />}
          Đăng nhập
        </button>
      </form>
    </div>
  );
}
