export default defineNuxtConfig({
  ssr: false,

  devtools: { enabled: true },

  modules: ['@pinia/nuxt'],

  components: {
    dirs: [
      {
        path: '~/components',
        pathPrefix: false
      }
    ]
  },

  css: ['~/assets/css/main.css'],

  app: {
    head: {
      title: 'Notes',
      meta: [
        { name: 'description', content: 'A simple notes application with sync' },
        { name: 'viewport', content: 'width=device-width, initial-scale=1' }
      ],
      link: [
        { rel: 'icon', type: 'image/x-icon', href: '/favicon.ico' },
        { rel: 'icon', type: 'image/png', sizes: '32x32', href: '/favicon-32.png' },
        { rel: 'icon', type: 'image/png', sizes: '16x16', href: '/favicon-16.png' },
        { rel: 'apple-touch-icon', sizes: '180x180', href: '/icon.png' }
      ]
    }
  },

  runtimeConfig: {
    public: {
      apiBase: process.env.NUXT_PUBLIC_API_BASE || 'http://localhost:8088'
    }
  },

  compatibilityDate: '2024-01-01'
})
