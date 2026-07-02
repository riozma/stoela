import { createRouter, createWebHistory } from 'vue-router'
import { supabase } from '../supabaseClient'
import LoginView from '../views/LoginView.vue'
import LagerUebersicht from '../views/LagerUebersicht.vue'
import LagerImport from '../views/LagerImport.vue'
import LagerDetail from '../views/LagerDetail.vue'
import AnmeldungTN from '../views/AnmeldungTN.vue'
import AnmeldungLeiter from '../views/AnmeldungLeiter.vue'
import Willkommen from '../views/Willkommen.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', redirect: '/lager' },
    { path: '/login', name: 'login', component: LoginView },
    { path: '/lager', name: 'lager', component: LagerUebersicht, meta: { requiresAuth: true } },
    { path: '/lager/import', name: 'lager-import', component: LagerImport, meta: { requiresAuth: true } },
    { path: '/lager/:id/willkommen', name: 'willkommen', component: Willkommen },
    { path: '/lager/:id/anmelden-tn', name: 'anmeldung-tn', component: AnmeldungTN },
    { path: '/lager/:id/anmelden-leiter', name: 'anmeldung-leiter', component: AnmeldungLeiter, meta: { requiresAuth: true } },
    {
      path: '/lager/:id',
      redirect: (to) => ({ path: `/lager/${to.params.id}/dashboard` }),
    },
    {
      path: '/lager/:id/aemtli/:aemtliSlug',
      name: 'lager-aemtli',
      component: LagerDetail,
      meta: { requiresAuth: true },
    },
    {
      path: '/lager/:id/programm/neu',
      name: 'programm-neu',
      component: LagerDetail,
      meta: { requiresAuth: true },
    },
    {
      path: '/lager/:id/programm/block/:blockId',
      name: 'programm-block',
      component: LagerDetail,
      meta: { requiresAuth: true },
    },
    {
      path: '/lager/:id/programm/tag/:programmTag',
      name: 'programm-tag',
      component: LagerDetail,
      meta: { requiresAuth: true },
    },
    {
      path: '/lager/:id/programm',
      name: 'programm',
      component: LagerDetail,
      meta: { requiresAuth: true },
    },
    {
      path: '/lager/:id/:section',
      name: 'lager-section',
      component: LagerDetail,
      meta: { requiresAuth: true },
    },
  ],
})

router.beforeEach(async (to) => {
  const { data } = await supabase.auth.getSession()
  const loggedIn = !!data.session

  if (to.meta.requiresAuth && !loggedIn) {
    return { path: '/login', query: { redirect: to.fullPath } }
  }
  if (to.name === 'login' && loggedIn) return '/lager'
  return true
})

export default router
