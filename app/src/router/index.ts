import { createRouter, createWebHistory } from 'vue-router'
import { supabase } from '../supabaseClient'
import LoginView from '../views/LoginView.vue'
import LagerUebersicht from '../views/LagerUebersicht.vue'
import LagerImport from '../views/LagerImport.vue'
import LagerDetail from '../views/LagerDetail.vue'
import AnmeldungTN from '../views/AnmeldungTN.vue'
import AnmeldungLeiter from '../views/AnmeldungLeiter.vue'
import AemtliUebersicht from '../views/AemtliUebersicht.vue'
import AemtliDetail from '../views/AemtliDetail.vue'
import EventsUebersicht from '../views/EventsUebersicht.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', redirect: '/lager' },
    { path: '/login', name: 'login', component: LoginView },
    { path: '/lager', name: 'lager', component: LagerUebersicht, meta: { requiresAuth: true } },
    { path: '/lager/import', name: 'lager-import', component: LagerImport, meta: { requiresAuth: true } },
    { path: '/lager/:id/anmelden-tn', name: 'anmeldung-tn', component: AnmeldungTN },
    { path: '/lager/:id/anmelden-leiter', name: 'anmeldung-leiter', component: AnmeldungLeiter },
    { path: '/lager/:id', name: 'lager-detail', component: LagerDetail, meta: { requiresAuth: true } },
    { path: '/aemtli', name: 'aemtli', component: AemtliUebersicht, meta: { requiresAuth: true } },
    { path: '/aemtli/:id', name: 'aemtli-detail', component: AemtliDetail, meta: { requiresAuth: true } },
    { path: '/events', name: 'events', component: EventsUebersicht, meta: { requiresAuth: true } },
  ],
})

router.beforeEach(async (to) => {
  const { data } = await supabase.auth.getSession()
  const loggedIn = !!data.session

  if (to.meta.requiresAuth && !loggedIn) return '/login'
  if (to.name === 'login' && loggedIn) return '/lager'
  return true
})

export default router
