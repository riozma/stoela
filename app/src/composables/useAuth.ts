import { ref } from 'vue'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../supabaseClient'

const session = ref<Session | null>(null)
const ready = ref(false)

supabase.auth.getSession().then(({ data }) => {
  session.value = data.session
  ready.value = true
})

supabase.auth.onAuthStateChange((_event, newSession) => {
  session.value = newSession
})

export function useAuth() {
  async function sendMagicLink(email: string) {
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: window.location.origin },
    })
    if (error) throw error
  }

  async function signOut() {
    await supabase.auth.signOut()
  }

  return { session, ready, sendMagicLink, signOut }
}
