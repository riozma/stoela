import { createRouter, createWebHistory } from 'vue-router'
import { supabase } from '../supabaseClient'
import LoginView from '../views/LoginView.vue'
import StartseiteView from '../views/StartseiteView.vue'
import LagerDetail from '../views/LagerDetail.vue'
import AnmeldungTN from '../views/AnmeldungTN.vue'
import AnmeldungLeiter from '../views/AnmeldungLeiter.vue'
import Willkommen from '../views/Willkommen.vue'
import OrganisationView from '../views/OrganisationView.vue'
import LagerBearbeitungView from '../views/LagerBearbeitungView.vue'
import MoerderliView from '../views/MoerderliView.vue'
import { isNavSectionAllowed } from '../lib/lagerNavConfig'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', name: 'start', component: StartseiteView, meta: { requiresAuth: true } },
    { path: '/login', name: 'login', component: LoginView },
    { path: '/lager', redirect: '/organisation' },
    { path: '/organisation', name: 'organisation', component: OrganisationView, meta: { requiresAuth: true } },
    { path: '/lager/import', name: 'lager-import', redirect: '/organisation' },
    { path: '/lager/:id/willkommen', name: 'willkommen', component: Willkommen },
    { path: '/lager/:id/anmelden-tn', name: 'anmeldung-tn', component: AnmeldungTN },
    { path: '/lager/:id/anmelden-leiter', name: 'anmeldung-leiter', component: AnmeldungLeiter, meta: { requiresAuth: true } },
    {
      path: '/lager/:id/moerderli',
      name: 'moerderli',
      component: MoerderliView,
      props: (route) => ({ lagerId: route.params.id as string }),
      meta: { requiresAuth: true },
    },
    {
      path: '/lager/:id/bearbeitung',
      name: 'lager-bearbeitung',
      component: LagerBearbeitungView,
      meta: { requiresAuth: true },
    },
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
  if (to.name === 'login' && loggedIn) return '/'
  const lagerId = typeof to.params.id === 'string' ? to.params.id : null
  if (lagerId && to.name === 'lager-section') {
    const section = to.params.section as string
    if (section === 'team') {
      return { path: `/lager/${lagerId}/leiter` }
    }
    if (!isNavSectionAllowed(section)) {
      return { path: `/lager/${lagerId}/bearbeitung` }
    }
  }
  if (lagerId && to.name === 'lager-aemtli') {
    const slug = to.params.aemtliSlug as string
    if (!isNavSectionAllowed(`aemtli:${slug}`)) {
      return { path: `/lager/${lagerId}/bearbeitung` }
    }
  }
  return true
})

export default router
