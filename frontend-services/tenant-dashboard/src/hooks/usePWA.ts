"use client"

import { useState, useEffect, useCallback } from 'react'

interface BeforeInstallPromptEvent extends Event {
  prompt(): Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

interface PWAState {
  isInstallable: boolean
  isInstalled: boolean
  isOnline: boolean
  isUpdateAvailable: boolean
  showInstallPrompt: () => Promise<boolean>
  dismissInstallPrompt: () => void
  updateApp: () => void
  clearCache: () => Promise<void>
}

export function usePWA(): PWAState {
  const [isInstallable, setIsInstallable] = useState(false)
  const [isInstalled, setIsInstalled] = useState(false)
  const [isOnline, setIsOnline] = useState(true)
  const [isUpdateAvailable, setIsUpdateAvailable] = useState(false)
  const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null)

  // Check if app is installed
  useEffect(() => {
    const checkInstalled = () => {
      const isStandalone = window.matchMedia('(display-mode: standalone)').matches
      const isInWebApp = (window.navigator as any).standalone === true
      setIsInstalled(isStandalone || isInWebApp)
    }

    checkInstalled()
    
    // Listen for display mode changes
    const mediaQuery = window.matchMedia('(display-mode: standalone)')
    mediaQuery.addEventListener('change', checkInstalled)
    
    return () => mediaQuery.removeEventListener('change', checkInstalled)
  }, [])

  // Handle online/offline status
  useEffect(() => {
    const updateOnlineStatus = () => setIsOnline(navigator.onLine)
    
    updateOnlineStatus()
    
    window.addEventListener('online', updateOnlineStatus)
    window.addEventListener('offline', updateOnlineStatus)
    
    return () => {
      window.removeEventListener('online', updateOnlineStatus)
      window.removeEventListener('offline', updateOnlineStatus)
    }
  }, [])

  // Handle install prompt
  useEffect(() => {
    const handleBeforeInstallPrompt = (e: Event) => {
      const event = e as BeforeInstallPromptEvent
      // Prevent Chrome 67 and earlier from automatically showing the prompt
      event.preventDefault()
      // Stash the event so it can be triggered later
      setDeferredPrompt(event)
      setIsInstallable(true)
    }

    const handleAppInstalled = () => {
      console.log('PWA installed successfully')
      setIsInstalled(true)
      setIsInstallable(false)
      setDeferredPrompt(null)
    }

    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt)
    window.addEventListener('appinstalled', handleAppInstalled)

    return () => {
      window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt)
      window.removeEventListener('appinstalled', handleAppInstalled)
    }
  }, [])

  // Register service worker and handle updates
  useEffect(() => {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker
        .register('/sw.js')
        .then((registration) => {
          console.log('Service Worker registered successfully:', registration.scope)

          // Check for updates
          registration.addEventListener('updatefound', () => {
            const newWorker = registration.installing
            if (newWorker) {
              newWorker.addEventListener('statechange', () => {
                if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
                  // New update available
                  setIsUpdateAvailable(true)
                }
              })
            }
          })

          // Listen for messages from service worker
          navigator.serviceWorker.addEventListener('message', (event) => {
            const { type, payload } = event.data
            
            switch (type) {
              case 'UPDATE_AVAILABLE':
                setIsUpdateAvailable(true)
                break
              case 'CACHE_UPDATED':
                console.log('Cache updated:', payload)
                break
              default:
                console.log('Unknown message from SW:', type)
            }
          })
        })
        .catch((error) => {
          console.error('Service Worker registration failed:', error)
        })
    }
  }, [])

  // Show install prompt
  const showInstallPrompt = useCallback(async (): Promise<boolean> => {
    if (!deferredPrompt) {
      return false
    }

    try {
      // Show the install prompt
      await deferredPrompt.prompt()
      
      // Wait for the user to respond to the prompt
      const { outcome } = await deferredPrompt.userChoice
      
      console.log(`User response to install prompt: ${outcome}`)
      
      // Reset the deferred prompt
      setDeferredPrompt(null)
      setIsInstallable(false)
      
      return outcome === 'accepted'
    } catch (error) {
      console.error('Error showing install prompt:', error)
      return false
    }
  }, [deferredPrompt])

  // Dismiss install prompt
  const dismissInstallPrompt = useCallback(() => {
    setIsInstallable(false)
    setDeferredPrompt(null)
  }, [])

  // Update app
  const updateApp = useCallback(() => {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.getRegistration().then((registration) => {
        if (registration && registration.waiting) {
          // Tell the waiting service worker to skip waiting and become active
          registration.waiting.postMessage({ type: 'SKIP_WAITING' })
          
          // Reload the page to use the new service worker
          window.location.reload()
        }
      })
    }
  }, [])

  // Clear cache
  const clearCache = useCallback(async () => {
    if ('caches' in window) {
      try {
        const cacheNames = await caches.keys()
        await Promise.all(
          cacheNames.map(cacheName => caches.delete(cacheName))
        )
        
        // Also tell service worker to clear its caches
        if ('serviceWorker' in navigator) {
          const registration = await navigator.serviceWorker.getRegistration()
          if (registration && registration.active) {
            registration.active.postMessage({ type: 'CLEAR_CACHE' })
          }
        }
        
        console.log('All caches cleared')
      } catch (error) {
        console.error('Error clearing cache:', error)
      }
    }
  }, [])

  return {
    isInstallable,
    isInstalled,
    isOnline,
    isUpdateAvailable,
    showInstallPrompt,
    dismissInstallPrompt,
    updateApp,
    clearCache,
  }
}

// Hook for offline storage
export function useOfflineStorage() {
  const [isSupported, setIsSupported] = useState(false)

  useEffect(() => {
    setIsSupported('indexedDB' in window)
  }, [])

  const storeData = useCallback(async (key: string, data: any) => {
    if (!isSupported) return false

    try {
      const request = indexedDB.open('pyairtable-offline', 1)
      
      request.onupgradeneeded = () => {
        const db = request.result
        if (!db.objectStoreNames.contains('data')) {
          db.createObjectStore('data')
        }
      }

      return new Promise<boolean>((resolve, reject) => {
        request.onsuccess = () => {
          const db = request.result
          const transaction = db.transaction(['data'], 'readwrite')
          const store = transaction.objectStore('data')
          
          const putRequest = store.put({ data, timestamp: Date.now() }, key)
          
          putRequest.onsuccess = () => resolve(true)
          putRequest.onerror = () => reject(putRequest.error)
        }
        
        request.onerror = () => reject(request.error)
      })
    } catch (error) {
      console.error('Error storing offline data:', error)
      return false
    }
  }, [isSupported])

  const getData = useCallback(async (key: string): Promise<any> => {
    if (!isSupported) return null

    try {
      const request = indexedDB.open('pyairtable-offline', 1)
      
      return new Promise((resolve, reject) => {
        request.onsuccess = () => {
          const db = request.result
          const transaction = db.transaction(['data'], 'readonly')
          const store = transaction.objectStore('data')
          
          const getRequest = store.get(key)
          
          getRequest.onsuccess = () => {
            const result = getRequest.result
            resolve(result ? result.data : null)
          }
          
          getRequest.onerror = () => reject(getRequest.error)
        }
        
        request.onerror = () => reject(request.error)
      })
    } catch (error) {
      console.error('Error getting offline data:', error)
      return null
    }
  }, [isSupported])

  const removeData = useCallback(async (key: string): Promise<boolean> => {
    if (!isSupported) return false

    try {
      const request = indexedDB.open('pyairtable-offline', 1)
      
      return new Promise<boolean>((resolve, reject) => {
        request.onsuccess = () => {
          const db = request.result
          const transaction = db.transaction(['data'], 'readwrite')
          const store = transaction.objectStore('data')
          
          const deleteRequest = store.delete(key)
          
          deleteRequest.onsuccess = () => resolve(true)
          deleteRequest.onerror = () => reject(deleteRequest.error)
        }
        
        request.onerror = () => reject(request.error)
      })
    } catch (error) {
      console.error('Error removing offline data:', error)
      return false
    }
  }, [isSupported])

  const clearAllData = useCallback(async (): Promise<boolean> => {
    if (!isSupported) return false

    try {
      const request = indexedDB.open('pyairtable-offline', 1)
      
      return new Promise<boolean>((resolve, reject) => {
        request.onsuccess = () => {
          const db = request.result
          const transaction = db.transaction(['data'], 'readwrite')
          const store = transaction.objectStore('data')
          
          const clearRequest = store.clear()
          
          clearRequest.onsuccess = () => resolve(true)
          clearRequest.onerror = () => reject(clearRequest.error)
        }
        
        request.onerror = () => reject(request.error)
      })
    } catch (error) {
      console.error('Error clearing offline data:', error)
      return false
    }
  }, [isSupported])

  return {
    isSupported,
    storeData,
    getData,
    removeData,
    clearAllData,
  }
}