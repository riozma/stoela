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
  async function signUpWithPassword(
    email: string,
    password: string,
    vorname: string,
    nachname: string,
    geburtsdatum?: string,
  ) {
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          given_name: vorname.trim(),
          family_name: nachname.trim(),
          geburtsdatum: geburtsdatum?.trim() || undefined,
        },
      },
    })
    if (error) throw error
  }

  async function signInWithPassword(email: string, password: string) {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw error
  }

  async function signInWithGoogle() {
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.origin },
    })
    if (error) throw error
  }

  async function setPassword(password: string) {
    const { error } = await supabase.auth.updateUser({ password })
    if (error) throw error
  }

  async function signOut() {
    await supabase.auth.signOut()
  }

  return {
    session,
    ready,
    signInWithPassword,
    signUpWithPassword,
    signInWithGoogle,
    setPassword,
    signOut,
  }
}
