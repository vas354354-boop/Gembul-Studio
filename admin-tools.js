(function () {
  function createClient() {
    if (!window.supabase || !window.GEMBUL_SUPABASE) {
      throw new Error('Koneksi Supabase belum siap. Muat ulang halaman.');
    }
    return window.supabase.createClient(window.GEMBUL_SUPABASE.url, window.GEMBUL_SUPABASE.publishableKey);
  }

  async function requireStaff(ownerOnly) {
    const client = createClient();
    const auth = await client.auth.getUser();
    if (auth.error && auth.error.name !== 'AuthSessionMissingError') throw auth.error;
    if (!auth.data || !auth.data.user) {
      window.location.replace('/account.html');
      return null;
    }
    const profile = await client.from('profiles').select('role,is_active').eq('id', auth.data.user.id).maybeSingle();
    if (profile.error) throw profile.error;
    if (!profile.data || !profile.data.is_active || !['owner', 'admin_cashier'].includes(profile.data.role)) {
      throw new Error('Akun ini tidak memiliki akses staf aktif.');
    }
    if (ownerOnly && profile.data.role !== 'owner') {
      throw new Error('Fitur ini hanya tersedia untuk Super Admin.');
    }
    return {client, user: auth.data.user, role: profile.data.role};
  }

  async function call(client, name, args) {
    const result = await client.rpc(name, args || {});
    if (result.error) throw result.error;
    return result.data;
  }

  function setStatus(element, message, isError) {
    element.textContent = message || '';
    element.classList.toggle('error', Boolean(isError));
  }

  function rupiah(value) {
    return new Intl.NumberFormat('id-ID', {style: 'currency', currency: 'IDR', maximumFractionDigits: 0}).format(Number(value) || 0);
  }

  function escapeText(value) {
    return String(value == null ? '' : value);
  }

  window.GembulStaff = Object.freeze({createClient, requireStaff, call, setStatus, rupiah, escapeText});
})();
