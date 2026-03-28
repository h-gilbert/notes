export default defineNuxtConfig({
  ssr: false,

  devtools: { enabled: true },

  devServer: {
    port: 3030
  },

  modules: ['@pinia/nuxt', '@vite-pwa/nuxt'],

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
        { name: 'viewport', content: 'width=device-width, initial-scale=1' },
        { name: 'apple-mobile-web-app-capable', content: 'yes' },
        { name: 'apple-mobile-web-app-status-bar-style', content: 'default' },
        { name: 'theme-color', content: '#FBF9F7' }
      ],
      link: [
        { rel: 'icon', type: 'image/x-icon', href: '/favicon.ico' },
        { rel: 'icon', type: 'image/png', sizes: '32x32', href: '/favicon-32.png' },
        { rel: 'icon', type: 'image/png', sizes: '16x16', href: '/favicon-16.png' },
        { rel: 'apple-touch-icon', sizes: '180x180', href: '/icon.png' }
      ]
    }
  },

  pwa: {
    strategies: 'generateSW',
    registerType: 'autoUpdate',
    manifest: {
      name: 'Notes',
      short_name: 'Notes',
      description: 'A simple notes application with sync',
      display: 'standalone',
      theme_color: '#FBF9F7',
      background_color: '#FBF9F7',
      scope: '/',
      start_url: '/',
      icons: [
        {
          src: '/icon.png',
          sizes: '180x180',
          type: 'image/png'
        },
        {
          src: '/favicon-32.png',
          sizes: '32x32',
          type: 'image/png'
        }
      ]
    },
    workbox: {
      navigateFallback: '/',
      globPatterns: ['**/*.{js,css,html,png,ico,svg,woff2}'],
      runtimeCaching: [
        {
          urlPattern: /\/api\/.*/,
          handler: 'NetworkFirst',
          options: {
            networkTimeoutSeconds: 3,
            cacheName: 'api-cache',
            expiration: {
              maxEntries: 50,
              maxAgeSeconds: 60 * 60 * 24 // 1 day
            }
          }
        }
      ]
    },
    client: {
      installPrompt: false
    },
    devOptions: {
      enabled: false
    }
  },

  runtimeConfig: {
    public: {
      apiBase: process.env.NUXT_PUBLIC_API_BASE || 'http://localhost:8088'
    }
  },

  compatibilityDate: '2024-01-01'
})
