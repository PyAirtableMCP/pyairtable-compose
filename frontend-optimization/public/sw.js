// Enhanced Service Worker for PyAirtable PWA
// Version 2.0 - Performance Optimized

const CACHE_NAME = 'pyairtable-v2.0';
const RUNTIME_CACHE = 'pyairtable-runtime-v2.0';
const API_CACHE = 'pyairtable-api-v2.0';
const IMAGE_CACHE = 'pyairtable-images-v2.0';

// Resources to cache on install
const STATIC_CACHE_URLS = [
  '/',
  '/manifest.json',
  '/offline',
  '/favicon.ico',
  // Add critical CSS and JS files
  '/_next/static/css/',
  '/_next/static/chunks/',
];

// API endpoints to cache
const API_CACHE_PATTERNS = [
  /^https:\/\/api\.pyairtable\.com\/v1\/user\/profile/,
  /^https:\/\/api\.pyairtable\.com\/v1\/workspaces/,
  /^https:\/\/api\.pyairtable\.com\/v1\/bases\/[\w]+\/tables/,
];

// Images and assets to cache
const IMAGE_CACHE_PATTERNS = [
  /\.(?:png|gif|jpg|jpeg|svg|webp)$/,
  /^https:\/\/images\.pyairtable\.com/,
  /^https:\/\/cdn\.pyairtable\.com\/images/,
];

// Network-first patterns (always try network first)
const NETWORK_FIRST_PATTERNS = [
  /\/api\/auth\//,
  /\/api\/websocket/,
  /\/api\/real-time/,
];

// Cache-first patterns (serve from cache if available)
const CACHE_FIRST_PATTERNS = [
  /\/_next\/static\//,
  /\.(?:css|js|woff|woff2|ttf|eot)$/,
];

// Background sync tags
const SYNC_TAGS = {
  ANALYTICS: 'analytics-sync',
  OFFLINE_ACTIONS: 'offline-actions-sync',
  PERFORMANCE_METRICS: 'performance-metrics-sync',
};

// Install event - cache static resources
self.addEventListener('install', (event) => {
  console.log('Service Worker: Installing...');
  
  event.waitUntil(
    Promise.all([
      caches.open(CACHE_NAME).then((cache) => {
        console.log('Service Worker: Caching static files');
        return cache.addAll(STATIC_CACHE_URLS.filter(url => url !== ''));
      }),
      // Skip waiting to activate immediately
      self.skipWaiting(),
    ])
  );
});

// Activate event - clean up old caches
self.addEventListener('activate', (event) => {
  console.log('Service Worker: Activating...');
  
  event.waitUntil(
    Promise.all([
      // Clean up old caches
      caches.keys().then((cacheNames) => {
        return Promise.all(
          cacheNames
            .filter((cacheName) => {
              return cacheName !== CACHE_NAME && 
                     cacheName !== RUNTIME_CACHE && 
                     cacheName !== API_CACHE && 
                     cacheName !== IMAGE_CACHE;
            })
            .map((cacheName) => {
              console.log('Service Worker: Removing old cache', cacheName);
              return caches.delete(cacheName);
            })
        );
      }),
      // Claim clients immediately
      self.clients.claim(),
    ])
  );
});

// Fetch event - handle all network requests
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Skip non-GET requests
  if (request.method !== 'GET') {
    return;
  }

  // Skip Chrome extension requests
  if (url.protocol === 'chrome-extension:') {
    return;
  }

  // Handle different types of requests
  if (isApiRequest(url)) {
    event.respondWith(handleApiRequest(request));
  } else if (isImageRequest(url)) {
    event.respondWith(handleImageRequest(request));
  } else if (isStaticAsset(url)) {
    event.respondWith(handleStaticAsset(request));
  } else if (isNavigationRequest(request)) {
    event.respondWith(handleNavigationRequest(request));
  } else {
    event.respondWith(handleGenericRequest(request));
  }
});

// Handle API requests with intelligent caching
async function handleApiRequest(request) {
  const url = new URL(request.url);
  
  // Network-first for critical APIs
  if (NETWORK_FIRST_PATTERNS.some(pattern => pattern.test(url.pathname))) {
    return networkFirst(request, API_CACHE);
  }
  
  // Stale-while-revalidate for cacheable APIs
  if (API_CACHE_PATTERNS.some(pattern => pattern.test(request.url))) {
    return staleWhileRevalidate(request, API_CACHE, { maxAge: 5 * 60 * 1000 }); // 5 minutes
  }
  
  // Default to network-only for other APIs
  return fetch(request);
}

// Handle image requests with aggressive caching
async function handleImageRequest(request) {
  return cacheFirst(request, IMAGE_CACHE, {
    maxAge: 30 * 24 * 60 * 60 * 1000, // 30 days
    maxEntries: 200,
  });
}

// Handle static assets with cache-first strategy
async function handleStaticAsset(request) {
  return cacheFirst(request, CACHE_NAME, {
    maxAge: 365 * 24 * 60 * 60 * 1000, // 1 year
  });
}

// Handle navigation requests with network-first and offline fallback
async function handleNavigationRequest(request) {
  try {
    // Try network first
    const networkResponse = await fetch(request);
    
    // Cache successful responses
    if (networkResponse.ok) {
      const cache = await caches.open(RUNTIME_CACHE);
      cache.put(request, networkResponse.clone());
    }
    
    return networkResponse;
  } catch (error) {
    // Try cache
    const cachedResponse = await caches.match(request);
    if (cachedResponse) {
      return cachedResponse;
    }
    
    // Fallback to offline page
    const offlineResponse = await caches.match('/offline');
    return offlineResponse || new Response('Offline', { status: 503 });
  }
}

// Handle generic requests
async function handleGenericRequest(request) {
  return staleWhileRevalidate(request, RUNTIME_CACHE);
}

// Cache strategies implementation

// Network-first strategy
async function networkFirst(request, cacheName, options = {}) {
  try {
    const networkResponse = await fetch(request);
    
    if (networkResponse.ok) {
      const cache = await caches.open(cacheName);
      cache.put(request, networkResponse.clone());
    }
    
    return networkResponse;
  } catch (error) {
    const cachedResponse = await caches.match(request);
    return cachedResponse || new Response('Network Error', { status: 503 });
  }
}

// Cache-first strategy
async function cacheFirst(request, cacheName, options = {}) {
  const cache = await caches.open(cacheName);
  const cachedResponse = await cache.match(request);
  
  if (cachedResponse) {
    // Check if cached response is still fresh
    if (options.maxAge) {
      const cachedDate = new Date(cachedResponse.headers.get('date') || Date.now());
      const isExpired = Date.now() - cachedDate.getTime() > options.maxAge;
      
      if (!isExpired) {
        return cachedResponse;
      }
    } else {
      return cachedResponse;
    }
  }
  
  try {
    const networkResponse = await fetch(request);
    
    if (networkResponse.ok) {
      // Implement cache size management
      if (options.maxEntries) {
        await manageCacheSize(cacheName, options.maxEntries);
      }
      
      cache.put(request, networkResponse.clone());
    }
    
    return networkResponse;
  } catch (error) {
    return cachedResponse || new Response('Cache Error', { status: 503 });
  }
}

// Stale-while-revalidate strategy
async function staleWhileRevalidate(request, cacheName, options = {}) {
  const cache = await caches.open(cacheName);
  const cachedResponse = await cache.match(request);
  
  // Start network request (don't await)
  const networkResponsePromise = fetch(request).then(async (networkResponse) => {
    if (networkResponse.ok) {
      cache.put(request, networkResponse.clone());
    }
    return networkResponse;
  }).catch(() => null);
  
  // Return cached response immediately if available
  if (cachedResponse) {
    // Check freshness
    if (options.maxAge) {
      const cachedDate = new Date(cachedResponse.headers.get('date') || Date.now());
      const isExpired = Date.now() - cachedDate.getTime() > options.maxAge;
      
      if (!isExpired) {
        // Background update
        networkResponsePromise.catch(() => {});
        return cachedResponse;
      }
    } else {
      // Background update
      networkResponsePromise.catch(() => {});
      return cachedResponse;
    }
  }
  
  // Wait for network response if no cache available
  try {
    return await networkResponsePromise;
  } catch (error) {
    return new Response('Network Error', { status: 503 });
  }
}

// Utility functions

function isApiRequest(url) {
  return url.pathname.startsWith('/api/') || 
         url.hostname.includes('api.pyairtable.com');
}

function isImageRequest(url) {
  return IMAGE_CACHE_PATTERNS.some(pattern => pattern.test(url.pathname)) ||
         IMAGE_CACHE_PATTERNS.some(pattern => pattern.test(url.href));
}

function isStaticAsset(url) {
  return CACHE_FIRST_PATTERNS.some(pattern => pattern.test(url.pathname));
}

function isNavigationRequest(request) {
  return request.mode === 'navigate';
}

// Cache size management
async function manageCacheSize(cacheName, maxEntries) {
  const cache = await caches.open(cacheName);
  const keys = await cache.keys();
  
  if (keys.length >= maxEntries) {
    // Remove oldest entries (simple FIFO)
    const entriesToDelete = keys.slice(0, keys.length - maxEntries + 1);
    await Promise.all(entriesToDelete.map(key => cache.delete(key)));
  }
}

// Background sync for offline actions
self.addEventListener('sync', (event) => {
  console.log('Service Worker: Background sync triggered', event.tag);
  
  switch (event.tag) {
    case SYNC_TAGS.ANALYTICS:
      event.waitUntil(syncAnalytics());
      break;
    case SYNC_TAGS.OFFLINE_ACTIONS:
      event.waitUntil(syncOfflineActions());
      break;
    case SYNC_TAGS.PERFORMANCE_METRICS:
      event.waitUntil(syncPerformanceMetrics());
      break;
  }
});

// Sync offline analytics data
async function syncAnalytics() {
  try {
    const offlineAnalytics = await getStoredData('offline-analytics');
    
    if (offlineAnalytics.length > 0) {
      const response = await fetch('/api/analytics/batch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ events: offlineAnalytics }),
      });
      
      if (response.ok) {
        await clearStoredData('offline-analytics');
        console.log('Service Worker: Analytics synced successfully');
      }
    }
  } catch (error) {
    console.error('Service Worker: Analytics sync failed', error);
  }
}

// Sync offline user actions
async function syncOfflineActions() {
  try {
    const offlineActions = await getStoredData('offline-actions');
    
    for (const action of offlineActions) {
      try {
        const response = await fetch(action.url, {
          method: action.method,
          headers: action.headers,
          body: action.body,
        });
        
        if (response.ok) {
          await removeStoredData('offline-actions', action.id);
        }
      } catch (error) {
        console.error('Service Worker: Failed to sync action', action.id, error);
      }
    }
  } catch (error) {
    console.error('Service Worker: Offline actions sync failed', error);
  }
}

// Sync performance metrics
async function syncPerformanceMetrics() {
  try {
    const metrics = await getStoredData('performance-metrics');
    
    if (metrics.length > 0) {
      const response = await fetch('/api/analytics/performance', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ metrics }),
      });
      
      if (response.ok) {
        await clearStoredData('performance-metrics');
      }
    }
  } catch (error) {
    console.error('Service Worker: Performance metrics sync failed', error);
  }
}

// IndexedDB helpers for offline storage
async function getStoredData(storeName) {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('PyAirtableOffline', 1);
    
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const db = request.result;
      const transaction = db.transaction([storeName], 'readonly');
      const store = transaction.objectStore(storeName);
      const getAllRequest = store.getAll();
      
      getAllRequest.onsuccess = () => resolve(getAllRequest.result);
      getAllRequest.onerror = () => reject(getAllRequest.error);
    };
    
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(storeName)) {
        db.createObjectStore(storeName, { keyPath: 'id', autoIncrement: true });
      }
    };
  });
}

async function clearStoredData(storeName) {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('PyAirtableOffline', 1);
    
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const db = request.result;
      const transaction = db.transaction([storeName], 'readwrite');
      const store = transaction.objectStore(storeName);
      const clearRequest = store.clear();
      
      clearRequest.onsuccess = () => resolve();
      clearRequest.onerror = () => reject(clearRequest.error);
    };
  });
}

async function removeStoredData(storeName, id) {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('PyAirtableOffline', 1);
    
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const db = request.result;
      const transaction = db.transaction([storeName], 'readwrite');
      const store = transaction.objectStore(storeName);
      const deleteRequest = store.delete(id);
      
      deleteRequest.onsuccess = () => resolve();
      deleteRequest.onerror = () => reject(deleteRequest.error);
    };
  });
}

// Push notification handling
self.addEventListener('push', (event) => {
  console.log('Service Worker: Push notification received');
  
  if (!event.data) return;
  
  const data = event.data.json();
  const options = {
    body: data.body,
    icon: '/icons/icon-192x192.png',
    badge: '/icons/badge-72x72.png',
    image: data.image,
    data: data.data,
    actions: data.actions || [],
    requireInteraction: data.requireInteraction || false,
    silent: data.silent || false,
    tag: data.tag,
    renotify: data.renotify || false,
    timestamp: Date.now(),
  };
  
  event.waitUntil(
    self.registration.showNotification(data.title, options)
  );
});

// Notification click handling
self.addEventListener('notificationclick', (event) => {
  console.log('Service Worker: Notification clicked');
  
  event.notification.close();
  
  if (event.action) {
    // Handle action buttons
    handleNotificationAction(event.action, event.notification.data);
  } else {
    // Handle notification click
    event.waitUntil(
      self.clients.matchAll({ type: 'window' }).then((clientList) => {
        // Focus existing window if available
        for (const client of clientList) {
          if (client.url === '/' && 'focus' in client) {
            return client.focus();
          }
        }
        
        // Open new window if no existing window
        if (self.clients.openWindow) {
          return self.clients.openWindow('/');
        }
      })
    );
  }
});

function handleNotificationAction(action, data) {
  switch (action) {
    case 'view':
      self.clients.openWindow(data.url || '/');
      break;
    case 'dismiss':
      // Do nothing
      break;
    default:
      console.log('Unknown notification action:', action);
  }
}

// Periodic background sync (if supported)
self.addEventListener('periodicsync', (event) => {
  console.log('Service Worker: Periodic sync triggered', event.tag);
  
  if (event.tag === 'cache-cleanup') {
    event.waitUntil(performCacheCleanup());
  }
});

async function performCacheCleanup() {
  const cacheNames = await caches.keys();
  
  for (const cacheName of cacheNames) {
    const cache = await caches.open(cacheName);
    const requests = await cache.keys();
    
    for (const request of requests) {
      const response = await cache.match(request);
      const date = new Date(response.headers.get('date') || 0);
      const age = Date.now() - date.getTime();
      
      // Remove entries older than 30 days
      if (age > 30 * 24 * 60 * 60 * 1000) {
        await cache.delete(request);
      }
    }
  }
  
  console.log('Service Worker: Cache cleanup completed');
}

// Error handling
self.addEventListener('error', (event) => {
  console.error('Service Worker error:', event.error);
});

self.addEventListener('unhandledrejection', (event) => {
  console.error('Service Worker unhandled rejection:', event.reason);
});

console.log('Service Worker: Loaded successfully');