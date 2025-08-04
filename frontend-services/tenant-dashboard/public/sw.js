// Service Worker for PyAirtable Tenant Dashboard
// Provides offline functionality, caching, and background sync

const CACHE_NAME = 'pyairtable-dashboard-v1';
const STATIC_CACHE_NAME = 'pyairtable-static-v1';
const DYNAMIC_CACHE_NAME = 'pyairtable-dynamic-v1';
const API_CACHE_NAME = 'pyairtable-api-v1';

// Assets to cache on install
const STATIC_ASSETS = [
  '/',
  '/offline',
  '/manifest.json',
  // Add critical CSS and JS files here
];

// API endpoints to cache
const API_ENDPOINTS = [
  '/api/users',
  '/api/tenants',
  '/api/analytics',
  '/api/dashboard',
];

// Install event - cache static assets
self.addEventListener('install', event => {
  console.log('[SW] Installing service worker...');
  
  event.waitUntil(
    Promise.all([
      caches.open(STATIC_CACHE_NAME).then(cache => {
        console.log('[SW] Caching static assets');
        return cache.addAll(STATIC_ASSETS);
      }),
      // Skip waiting to activate immediately
      self.skipWaiting()
    ])
  );
});

// Activate event - cleanup old caches
self.addEventListener('activate', event => {
  console.log('[SW] Activating service worker...');
  
  event.waitUntil(
    Promise.all([
      // Clean up old caches
      caches.keys().then(cacheNames => {
        return Promise.all(
          cacheNames.map(cacheName => {
            if (cacheName !== CACHE_NAME && 
                cacheName !== STATIC_CACHE_NAME && 
                cacheName !== DYNAMIC_CACHE_NAME &&
                cacheName !== API_CACHE_NAME) {
              console.log('[SW] Deleting old cache:', cacheName);
              return caches.delete(cacheName);
            }
          })
        );
      }),
      // Take control of all clients
      self.clients.claim()
    ])
  );
});

// Fetch event - handle network requests
self.addEventListener('fetch', event => {
  const { request } = event;
  const url = new URL(request.url);

  // Skip non-GET requests
  if (request.method !== 'GET') {
    return;
  }

  // Skip chrome-extension requests
  if (url.protocol === 'chrome-extension:') {
    return;
  }

  // Handle different types of requests
  if (url.pathname.startsWith('/api/')) {
    // API requests - network first with cache fallback
    event.respondWith(handleApiRequest(request));
  } else if (isStaticAsset(url.pathname)) {
    // Static assets - cache first
    event.respondWith(handleStaticAsset(request));
  } else {
    // Pages - network first with cache fallback
    event.respondWith(handlePageRequest(request));
  }
});

// Handle API requests with network-first strategy
async function handleApiRequest(request) {
  const cache = await caches.open(API_CACHE_NAME);
  
  try {
    // Try network first
    const networkResponse = await fetch(request);
    
    if (networkResponse.ok) {
      // Cache successful responses
      cache.put(request, networkResponse.clone());
    }
    
    return networkResponse;
  } catch (error) {
    console.log('[SW] Network failed for API request, checking cache...');
    
    // Fallback to cache
    const cachedResponse = await cache.match(request);
    if (cachedResponse) {
      // Add header to indicate cached response
      const response = cachedResponse.clone();
      response.headers.set('X-Cache-Status', 'HIT');
      return response;
    }
    
    // Return offline response for API
    return new Response(
      JSON.stringify({ 
        error: 'Offline', 
        message: 'This request is not available offline',
        cached: false 
      }),
      { 
        status: 503,
        headers: { 'Content-Type': 'application/json' }
      }
    );
  }
}

// Handle static assets with cache-first strategy
async function handleStaticAsset(request) {
  const cache = await caches.open(STATIC_CACHE_NAME);
  
  // Try cache first
  const cachedResponse = await cache.match(request);
  if (cachedResponse) {
    return cachedResponse;
  }
  
  try {
    // Fallback to network
    const networkResponse = await fetch(request);
    
    if (networkResponse.ok) {
      cache.put(request, networkResponse.clone());
    }
    
    return networkResponse;
  } catch (error) {
    console.log('[SW] Failed to fetch static asset:', request.url);
    throw error;
  }
}

// Handle page requests with network-first strategy
async function handlePageRequest(request) {
  const cache = await caches.open(DYNAMIC_CACHE_NAME);
  
  try {
    // Try network first
    const networkResponse = await fetch(request);
    
    if (networkResponse.ok) {
      cache.put(request, networkResponse.clone());
    }
    
    return networkResponse;
  } catch (error) {
    console.log('[SW] Network failed for page request, checking cache...');
    
    // Fallback to cache
    const cachedResponse = await cache.match(request);
    if (cachedResponse) {
      return cachedResponse;
    }
    
    // Fallback to offline page
    const offlineResponse = await cache.match('/offline');
    if (offlineResponse) {
      return offlineResponse;
    }
    
    // Final fallback
    return new Response(
      `<!DOCTYPE html>
      <html>
        <head>
          <title>Offline - PyAirtable Dashboard</title>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            body { 
              font-family: system-ui, sans-serif; 
              display: flex; 
              align-items: center; 
              justify-content: center; 
              min-height: 100vh; 
              margin: 0; 
              background: #f9fafb; 
              color: #374151;
            }
            .container { 
              text-align: center; 
              max-width: 400px; 
              padding: 2rem;
            }
            .icon { 
              font-size: 4rem; 
              margin-bottom: 1rem; 
            }
            h1 { 
              font-size: 1.5rem; 
              margin-bottom: 0.5rem; 
              color: #111827;
            }
            p { 
              margin-bottom: 1.5rem; 
              color: #6b7280;
              line-height: 1.5;
            }
            button { 
              background: #3b82f6; 
              color: white; 
              border: none; 
              padding: 0.75rem 1.5rem; 
              border-radius: 0.5rem; 
              cursor: pointer; 
              font-size: 1rem;
              transition: background-color 0.2s;
            }
            button:hover { 
              background: #2563eb; 
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="icon">📱</div>
            <h1>You're offline</h1>
            <p>This page isn't available offline. Check your connection and try again.</p>
            <button onclick="window.location.reload()">Try Again</button>
          </div>
        </body>
      </html>`,
      { 
        status: 200,
        headers: { 'Content-Type': 'text/html' }
      }
    );
  }
}

// Check if URL is a static asset
function isStaticAsset(pathname) {
  return pathname.startsWith('/_next/') ||
         pathname.startsWith('/static/') ||
         pathname.startsWith('/icons/') ||
         pathname.startsWith('/images/') ||
         pathname.match(/\.(js|css|png|jpg|jpeg|gif|svg|ico|woff|woff2|ttf|eot)$/);
}

// Background sync for offline actions
self.addEventListener('sync', event => {
  console.log('[SW] Background sync triggered:', event.tag);
  
  if (event.tag === 'background-sync-api') {
    event.waitUntil(processOfflineActions());
  }
});

// Process actions queued while offline
async function processOfflineActions() {
  // This would process any queued API calls or form submissions
  // Implementation would depend on your specific offline storage strategy
  console.log('[SW] Processing offline actions...');
}

// Push notification handling
self.addEventListener('push', event => {
  if (!event.data) return;
  
  const data = event.data.json();
  const options = {
    body: data.body,
    icon: '/icons/icon-192x192.png',
    badge: '/icons/badge-72x72.png',
    data: data.data,
    actions: data.actions || [],
    requireInteraction: data.requireInteraction || false,
    silent: data.silent || false,
    tag: data.tag || 'default',
    timestamp: Date.now(),
    vibrate: data.vibrate || [200, 100, 200]
  };
  
  event.waitUntil(
    self.registration.showNotification(data.title, options)
  );
});

// Notification click handling
self.addEventListener('notificationclick', event => {
  event.notification.close();
  
  const data = event.notification.data || {};
  const action = event.action;
  
  if (action) {
    // Handle action button clicks
    handleNotificationAction(action, data);
  } else {
    // Handle notification click
    event.waitUntil(
      clients.openWindow(data.url || '/')
    );
  }
});

function handleNotificationAction(action, data) {
  switch (action) {
    case 'view':
      clients.openWindow(data.url || '/');
      break;
    case 'dismiss':
      // Just close the notification
      break;
    default:
      clients.openWindow('/');
  }
}

// Periodic background sync for updates
self.addEventListener('periodicsync', event => {
  if (event.tag === 'cache-update') {
    event.waitUntil(updateCache());
  }
});

async function updateCache() {
  console.log('[SW] Updating cache in background...');
  
  try {
    const cache = await caches.open(API_CACHE_NAME);
    
    // Update critical API endpoints
    const updatePromises = API_ENDPOINTS.map(async endpoint => {
      try {
        const response = await fetch(endpoint);
        if (response.ok) {
          await cache.put(endpoint, response);
        }
      } catch (error) {
        console.log('[SW] Failed to update cache for:', endpoint);
      }
    });
    
    await Promise.all(updatePromises);
    console.log('[SW] Cache update completed');
  } catch (error) {
    console.error('[SW] Cache update failed:', error);
  }
}

// Message handling from the main thread
self.addEventListener('message', event => {
  const { type, payload } = event.data;
  
  switch (type) {
    case 'SKIP_WAITING':
      self.skipWaiting();
      break;
    case 'CACHE_UPDATE':
      updateCache();
      break;
    case 'CLEAR_CACHE':
      clearCache(payload.cacheName);
      break;
    default:
      console.log('[SW] Unknown message type:', type);
  }
});

async function clearCache(cacheName) {
  if (cacheName) {
    await caches.delete(cacheName);
  } else {
    const cacheNames = await caches.keys();
    await Promise.all(cacheNames.map(name => caches.delete(name)));
  }
}

console.log('[SW] Service worker script loaded');