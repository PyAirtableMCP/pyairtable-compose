import React, { 
  memo, 
  useMemo, 
  useCallback, 
  lazy, 
  Suspense, 
  forwardRef,
  useRef,
  useEffect,
} from 'react';
import { FixedSizeList as List } from 'react-window';
import { useIntersectionObserver, useLazyImage, useNetworkAware } from '../hooks/usePerformance';
import Image from 'next/image';

// Lazy loading components with better error boundaries
const LazyComponent = lazy(() => 
  import('./HeavyComponent').catch(() => ({ 
    default: () => <div>Failed to load component</div> 
  }))
);

// Optimized Image Component with lazy loading and responsive sizes
interface OptimizedImageProps {
  src: string;
  alt: string;
  width?: number;
  height?: number;
  className?: string;
  priority?: boolean;
  placeholder?: 'blur' | 'empty';
  blurDataURL?: string;
  sizes?: string;
  quality?: number;
}

export const OptimizedImage = memo<OptimizedImageProps>(({
  src,
  alt,
  width = 800,
  height = 600,
  className = '',
  priority = false,
  placeholder = 'blur',
  blurDataURL,
  sizes = '(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw',
  quality = 85,
}) => {
  const { shouldReduceQuality } = useNetworkAware();
  const adjustedQuality = shouldReduceQuality ? Math.max(quality - 20, 50) : quality;

  return (
    <div className={`relative overflow-hidden ${className}`}>
      <Image
        src={src}
        alt={alt}
        width={width}
        height={height}
        priority={priority}
        placeholder={placeholder}
        blurDataURL={blurDataURL || generateBlurDataURL(width, height)}
        sizes={sizes}
        quality={adjustedQuality}
        className="object-cover transition-opacity duration-300"
        onLoad={(e) => {
          // Performance tracking
          if (typeof window !== 'undefined' && window.gtag) {
            window.gtag('event', 'image_load', {
              event_category: 'Performance',
              event_label: src,
              value: Math.round(performance.now()),
            });
          }
        }}
      />
    </div>
  );
});

OptimizedImage.displayName = 'OptimizedImage';

// Generate a blur data URL for placeholder
const generateBlurDataURL = (w: number, h: number): string => {
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');
  if (ctx) {
    ctx.fillStyle = '#f3f4f6';
    ctx.fillRect(0, 0, w, h);
  }
  return canvas.toDataURL();
};

// Virtualized List Component for large datasets
interface VirtualizedListProps<T> {
  items: T[];
  itemHeight: number;
  height: number;
  width?: number;
  renderItem: (item: T, index: number, style: React.CSSProperties) => React.ReactNode;
  onScroll?: (scrollTop: number) => void;
  className?: string;
}

export const VirtualizedList = memo(<T,>({
  items,
  itemHeight,
  height,
  width = '100%',
  renderItem,
  onScroll,
  className = '',
}: VirtualizedListProps<T>) => {
  const Row = useCallback(({ index, style }: { index: number; style: React.CSSProperties }) => {
    const item = items[index];
    return (
      <div style={style}>
        {renderItem(item, index, style)}
      </div>
    );
  }, [items, renderItem]);

  const handleScroll = useCallback(({ scrollTop }: { scrollTop: number }) => {
    onScroll?.(scrollTop);
  }, [onScroll]);

  return (
    <div className={className}>
      <List
        height={height}
        itemCount={items.length}
        itemSize={itemHeight}
        width={width}
        onScroll={handleScroll}
      >
        {Row}
      </List>
    </div>
  );
});

VirtualizedList.displayName = 'VirtualizedList';

// Intersection Observer based lazy component
interface LazyLoadComponentProps {
  children: React.ReactNode;
  fallback?: React.ReactNode;
  threshold?: number;
  rootMargin?: string;
  className?: string;
}

export const LazyLoadComponent = memo<LazyLoadComponentProps>(({
  children,
  fallback = <div className="animate-pulse bg-gray-200 h-32 w-full rounded" />,
  threshold = 0.1,
  rootMargin = '50px',
  className = '',
}) => {
  const ref = useRef<HTMLDivElement>(null);
  const { hasIntersected } = useIntersectionObserver(ref, {
    threshold,
    rootMargin,
  });

  return (
    <div ref={ref} className={className}>
      {hasIntersected ? children : fallback}
    </div>
  );
});

LazyLoadComponent.displayName = 'LazyLoadComponent';

// Performance-optimized data table
interface DataTableProps<T> {
  data: T[];
  columns: Array<{
    key: keyof T;
    header: string;
    render?: (value: T[keyof T], item: T) => React.ReactNode;
    sortable?: boolean;
    width?: string;
  }>;
  onSort?: (key: keyof T, direction: 'asc' | 'desc') => void;
  loading?: boolean;
  className?: string;
}

export const DataTable = memo(<T extends Record<string, any>>({
  data,
  columns,
  onSort,
  loading = false,
  className = '',
}: DataTableProps<T>) => {
  const memoizedRows = useMemo(() => {
    return data.map((item, index) => (
      <tr key={index} className="hover:bg-gray-50 transition-colors">
        {columns.map((column) => (
          <td key={String(column.key)} className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
            {column.render ? column.render(item[column.key], item) : String(item[column.key])}
          </td>
        ))}
      </tr>
    ));
  }, [data, columns]);

  const handleSort = useCallback((key: keyof T) => {
    // Toggle sort direction logic would go here
    onSort?.(key, 'asc');
  }, [onSort]);

  if (loading) {
    return (
      <div className="animate-pulse">
        <div className="h-4 bg-gray-200 rounded w-full mb-2"></div>
        <div className="h-4 bg-gray-200 rounded w-3/4 mb-2"></div>
        <div className="h-4 bg-gray-200 rounded w-1/2"></div>
      </div>
    );
  }

  return (
    <div className={`overflow-x-auto ${className}`}>
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            {columns.map((column) => (
              <th
                key={String(column.key)}
                className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                onClick={() => column.sortable && handleSort(column.key)}
                style={{ width: column.width }}
              >
                {column.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {memoizedRows}
        </tbody>
      </table>
    </div>
  );
});

DataTable.displayName = 'DataTable';

// Optimized Search Component with debouncing
interface OptimizedSearchProps {
  onSearch: (query: string) => void;
  placeholder?: string;
  debounceMs?: number;
  className?: string;
}

export const OptimizedSearch = memo<OptimizedSearchProps>(({
  onSearch,
  placeholder = 'Search...',
  debounceMs = 300,
  className = '',
}) => {
  const [query, setQuery] = React.useState('');
  const timeoutRef = useRef<NodeJS.Timeout>();

  const handleInputChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    setQuery(value);

    // Clear previous timeout
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
    }

    // Set new timeout for debounced search
    timeoutRef.current = setTimeout(() => {
      onSearch(value);
    }, debounceMs);
  }, [onSearch, debounceMs]);

  useEffect(() => {
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  return (
    <input
      type="text"
      value={query}
      onChange={handleInputChange}
      placeholder={placeholder}
      className={`px-4 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent ${className}`}
    />
  );
});

OptimizedSearch.displayName = 'OptimizedSearch';

// Infinite Scroll Component
interface InfiniteScrollProps {
  children: React.ReactNode;
  hasMore: boolean;
  loading: boolean;
  onLoadMore: () => void;
  loader?: React.ReactNode;
  threshold?: number;
}

export const InfiniteScroll = memo<InfiniteScrollProps>(({
  children,
  hasMore,
  loading,
  onLoadMore,
  loader = <div className="text-center py-4">Loading...</div>,
  threshold = 100,
}) => {
  const sentinelRef = useRef<HTMLDivElement>(null);
  const { isIntersecting } = useIntersectionObserver(sentinelRef, {
    rootMargin: `${threshold}px`,
  });

  useEffect(() => {
    if (isIntersecting && hasMore && !loading) {
      onLoadMore();
    }
  }, [isIntersecting, hasMore, loading, onLoadMore]);

  return (
    <>
      {children}
      {hasMore && (
        <div ref={sentinelRef}>
          {loading && loader}
        </div>
      )}
    </>
  );
});

InfiniteScroll.displayName = 'InfiniteScroll';

// Optimized Modal with focus management and portal
interface OptimizedModalProps {
  isOpen: boolean;
  onClose: () => void;
  children: React.ReactNode;
  title?: string;
  className?: string;
}

export const OptimizedModal = memo<OptimizedModalProps>(({
  isOpen,
  onClose,
  children,
  title,
  className = '',
}) => {
  const modalRef = useRef<HTMLDivElement>(null);
  const previousActiveElement = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (isOpen) {
      // Store the currently focused element
      previousActiveElement.current = document.activeElement as HTMLElement;
      
      // Focus the modal
      modalRef.current?.focus();

      // Prevent body scroll
      document.body.style.overflow = 'hidden';
    } else {
      // Restore focus to the previously focused element
      previousActiveElement.current?.focus();
      
      // Restore body scroll
      document.body.style.overflow = 'unset';
    }

    return () => {
      document.body.style.overflow = 'unset';
    };
  }, [isOpen]);

  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Escape') {
      onClose();
    }
  }, [onClose]);

  const handleBackdropClick = useCallback((e: React.MouseEvent) => {
    if (e.target === e.currentTarget) {
      onClose();
    }
  }, [onClose]);

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50"
      onClick={handleBackdropClick}
    >
      <div
        ref={modalRef}
        className={`bg-white rounded-lg shadow-xl max-w-md w-full mx-4 ${className}`}
        onKeyDown={handleKeyDown}
        tabIndex={-1}
        role="dialog"
        aria-modal="true"
        aria-labelledby={title ? 'modal-title' : undefined}
      >
        {title && (
          <div className="px-6 py-4 border-b border-gray-200">
            <h2 id="modal-title" className="text-lg font-semibold text-gray-900">
              {title}
            </h2>
          </div>
        )}
        <div className="px-6 py-4">
          {children}
        </div>
      </div>
    </div>
  );
});

OptimizedModal.displayName = 'OptimizedModal';

// Error Boundary Component
interface ErrorBoundaryState {
  hasError: boolean;
  error?: Error;
}

export class ErrorBoundary extends React.Component<
  React.PropsWithChildren<{
    fallback?: React.ReactNode;
    onError?: (error: Error, errorInfo: React.ErrorInfo) => void;
  }>,
  ErrorBoundaryState
> {
  constructor(props: any) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    console.error('Error caught by boundary:', error, errorInfo);
    this.props.onError?.(error, errorInfo);

    // Send error to monitoring service
    if (typeof window !== 'undefined' && window.gtag) {
      window.gtag('event', 'exception', {
        description: error.toString(),
        fatal: false,
      });
    }
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback || (
        <div className="text-center py-8">
          <h2 className="text-lg font-semibold text-gray-900 mb-2">
            Something went wrong
          </h2>
          <p className="text-gray-600">
            We apologize for the inconvenience. Please try refreshing the page.
          </p>
          <button
            onClick={() => this.setState({ hasError: false })}
            className="mt-4 px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
          >
            Try Again
          </button>
        </div>
      );
    }

    return this.props.children;
  }
}

// Performance Monitor Component
export const PerformanceMonitor: React.FC<{ children: React.ReactNode }> = memo(({ children }) => {
  useEffect(() => {
    if (process.env.NODE_ENV === 'development') {
      // Monitor component render time
      const startTime = performance.now();
      
      return () => {
        const endTime = performance.now();
        const renderTime = endTime - startTime;
        
        if (renderTime > 16) { // More than one frame at 60fps
          console.warn(`Slow render detected: ${renderTime}ms`);
        }
      };
    }
  });

  return <>{children}</>;
});

PerformanceMonitor.displayName = 'PerformanceMonitor';