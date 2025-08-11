import { useEffect, useCallback, useRef, useState } from 'react';
import { getCLS, getFID, getFCP, getLCP, getTTFB } from 'web-vitals';

// Performance monitoring hook
export const useWebVitals = () => {
  const [metrics, setMetrics] = useState<Record<string, number>>({});

  useEffect(() => {
    // Core Web Vitals
    getCLS((metric) => {
      setMetrics(prev => ({ ...prev, CLS: metric.value }));
      // Send to analytics
      sendToAnalytics('CLS', metric.value, metric.id);
    });

    getFID((metric) => {
      setMetrics(prev => ({ ...prev, FID: metric.value }));
      sendToAnalytics('FID', metric.value, metric.id);
    });

    getFCP((metric) => {
      setMetrics(prev => ({ ...prev, FCP: metric.value }));
      sendToAnalytics('FCP', metric.value, metric.id);
    });

    getLCP((metric) => {
      setMetrics(prev => ({ ...prev, LCP: metric.value }));
      sendToAnalytics('LCP', metric.value, metric.id);
    });

    getTTFB((metric) => {
      setMetrics(prev => ({ ...prev, TTFB: metric.value }));
      sendToAnalytics('TTFB', metric.value, metric.id);
    });
  }, []);

  return metrics;
};

// Send metrics to analytics service
const sendToAnalytics = (name: string, value: number, id: string) => {
  if (typeof window !== 'undefined' && window.gtag) {
    window.gtag('event', name, {
      event_category: 'Web Vitals',
      value: Math.round(name === 'CLS' ? value * 1000 : value),
      event_label: id,
      non_interaction: true,
    });
  }

  // Send to custom analytics endpoint
  if (process.env.NODE_ENV === 'production') {
    fetch('/api/analytics/vitals', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name,
        value,
        id,
        url: window.location.href,
        userAgent: navigator.userAgent,
        timestamp: Date.now(),
      }),
    }).catch(console.error);
  }
};

// Performance-aware intersection observer
export const useIntersectionObserver = (
  elementRef: React.RefObject<Element>,
  options: IntersectionObserverInit = {}
) => {
  const [isIntersecting, setIsIntersecting] = useState(false);
  const [hasIntersected, setHasIntersected] = useState(false);

  useEffect(() => {
    const element = elementRef.current;
    if (!element) return;

    const observer = new IntersectionObserver(
      ([entry]) => {
        setIsIntersecting(entry.isIntersecting);
        if (entry.isIntersecting && !hasIntersected) {
          setHasIntersected(true);
        }
      },
      {
        threshold: 0.1,
        rootMargin: '50px',
        ...options,
      }
    );

    observer.observe(element);

    return () => observer.disconnect();
  }, [elementRef, hasIntersected, options]);

  return { isIntersecting, hasIntersected };
};

// Optimized debounce hook
export const useDebounce = <T>(value: T, delay: number): T => {
  const [debouncedValue, setDebouncedValue] = useState<T>(value);

  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedValue(value);
    }, delay);

    return () => {
      clearTimeout(handler);
    };
  }, [value, delay]);

  return debouncedValue;
};

// Performance-aware state management
export const useOptimizedState = <T>(initialValue: T) => {
  const [state, setState] = useState(initialValue);
  const timeoutRef = useRef<NodeJS.Timeout>();

  const setOptimizedState = useCallback((newValue: T | ((prev: T) => T)) => {
    // Batch state updates using setTimeout
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
    }

    timeoutRef.current = setTimeout(() => {
      setState(newValue);
    }, 0);
  }, []);

  useEffect(() => {
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  return [state, setOptimizedState] as const;
};

// Image lazy loading with performance optimization
export const useLazyImage = (src: string, placeholder?: string) => {
  const [imageSrc, setImageSrc] = useState(placeholder || '');
  const [imageRef, setImageRef] = useState<HTMLImageElement | null>(null);
  const { isIntersecting } = useIntersectionObserver({ current: imageRef });

  useEffect(() => {
    if (isIntersecting && src && imageSrc !== src) {
      const img = new Image();
      img.onload = () => {
        setImageSrc(src);
      };
      img.src = src;
    }
  }, [isIntersecting, src, imageSrc]);

  return { imageSrc, setImageRef };
};

// Performance monitoring for API calls
export const useApiPerformance = () => {
  const performanceRef = useRef<Map<string, number>>(new Map());

  const startMeasure = useCallback((key: string) => {
    performanceRef.current.set(key, performance.now());
  }, []);

  const endMeasure = useCallback((key: string, metadata?: any) => {
    const startTime = performanceRef.current.get(key);
    if (startTime) {
      const duration = performance.now() - startTime;
      performanceRef.current.delete(key);

      // Send performance data
      if (process.env.NODE_ENV === 'production') {
        fetch('/api/analytics/performance', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            type: 'api_call',
            key,
            duration,
            metadata,
            timestamp: Date.now(),
          }),
        }).catch(console.error);
      }

      return duration;
    }
    return 0;
  }, []);

  return { startMeasure, endMeasure };
};

// Memory usage monitoring
export const useMemoryMonitor = () => {
  const [memoryInfo, setMemoryInfo] = useState<any>(null);

  useEffect(() => {
    const updateMemoryInfo = () => {
      if ('memory' in performance) {
        const info = (performance as any).memory;
        setMemoryInfo({
          usedJSHeapSize: info.usedJSHeapSize,
          totalJSHeapSize: info.totalJSHeapSize,
          jsHeapSizeLimit: info.jsHeapSizeLimit,
          usagePercentage: (info.usedJSHeapSize / info.jsHeapSizeLimit) * 100,
        });
      }
    };

    updateMemoryInfo();
    const interval = setInterval(updateMemoryInfo, 5000); // Update every 5 seconds

    return () => clearInterval(interval);
  }, []);

  return memoryInfo;
};

// Bundle loading performance
export const useBundleLoadTime = () => {
  const [loadTimes, setLoadTimes] = useState<Record<string, number>>({});

  useEffect(() => {
    if (typeof window !== 'undefined' && window.performance) {
      const entries = performance.getEntriesByType('resource') as PerformanceResourceTiming[];
      
      const bundleEntries = entries.filter(entry => 
        entry.name.includes('_next/static/chunks/') || 
        entry.name.includes('.js') || 
        entry.name.includes('.css')
      );

      const times: Record<string, number> = {};
      bundleEntries.forEach(entry => {
        const filename = entry.name.split('/').pop() || 'unknown';
        times[filename] = entry.duration;
      });

      setLoadTimes(times);
    }
  }, []);

  return loadTimes;
};

// Network condition aware loading
export const useNetworkAware = () => {
  const [networkInfo, setNetworkInfo] = useState({
    effectiveType: '4g',
    downlink: 10,
    rtt: 50,
    saveData: false,
  });

  useEffect(() => {
    const updateNetworkInfo = () => {
      if ('connection' in navigator) {
        const connection = (navigator as any).connection;
        setNetworkInfo({
          effectiveType: connection.effectiveType || '4g',
          downlink: connection.downlink || 10,
          rtt: connection.rtt || 50,
          saveData: connection.saveData || false,
        });
      }
    };

    updateNetworkInfo();

    if ('connection' in navigator) {
      const connection = (navigator as any).connection;
      connection.addEventListener('change', updateNetworkInfo);
      
      return () => {
        connection.removeEventListener('change', updateNetworkInfo);
      };
    }
  }, []);

  const shouldReduceQuality = networkInfo.effectiveType === 'slow-2g' || 
                             networkInfo.effectiveType === '2g' || 
                             networkInfo.saveData;

  const shouldPreload = networkInfo.effectiveType === '4g' && 
                       networkInfo.downlink > 5 && 
                       !networkInfo.saveData;

  return {
    networkInfo,
    shouldReduceQuality,
    shouldPreload,
  };
};

// Custom hook for performance-aware component rendering
export const usePerformantRender = <T>(
  data: T[],
  itemHeight: number,
  containerHeight: number
) => {
  const [visibleRange, setVisibleRange] = useState({ start: 0, end: 0 });
  const [scrollTop, setScrollTop] = useState(0);

  const visibleCount = Math.ceil(containerHeight / itemHeight);
  const bufferSize = Math.floor(visibleCount / 2);

  useEffect(() => {
    const start = Math.max(0, Math.floor(scrollTop / itemHeight) - bufferSize);
    const end = Math.min(data.length, start + visibleCount + bufferSize * 2);
    
    setVisibleRange({ start, end });
  }, [scrollTop, itemHeight, data.length, visibleCount, bufferSize]);

  const onScroll = useCallback((event: React.UIEvent<HTMLElement>) => {
    setScrollTop(event.currentTarget.scrollTop);
  }, []);

  return {
    visibleItems: data.slice(visibleRange.start, visibleRange.end),
    visibleRange,
    onScroll,
    totalHeight: data.length * itemHeight,
  };
};

// Resource hints hook
export const useResourceHints = () => {
  const preloadResource = useCallback((href: string, as: string, type?: string) => {
    if (typeof document !== 'undefined') {
      const link = document.createElement('link');
      link.rel = 'preload';
      link.href = href;
      link.as = as;
      if (type) link.type = type;
      document.head.appendChild(link);
    }
  }, []);

  const prefetchResource = useCallback((href: string) => {
    if (typeof document !== 'undefined') {
      const link = document.createElement('link');
      link.rel = 'prefetch';
      link.href = href;
      document.head.appendChild(link);
    }
  }, []);

  const preconnect = useCallback((href: string, crossorigin?: boolean) => {
    if (typeof document !== 'undefined') {
      const link = document.createElement('link');
      link.rel = 'preconnect';
      link.href = href;
      if (crossorigin) link.crossOrigin = 'anonymous';
      document.head.appendChild(link);
    }
  }, []);

  return {
    preloadResource,
    prefetchResource,
    preconnect,
  };
};