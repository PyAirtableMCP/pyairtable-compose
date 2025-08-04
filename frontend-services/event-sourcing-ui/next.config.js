/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    appDir: true,
  },
  async rewrites() {
    return [
      {
        source: '/api/events/:path*',
        destination: 'http://localhost:8080/api/events/:path*',
      },
      {
        source: '/api/sagas/:path*',
        destination: 'http://localhost:8080/api/sagas/:path*',
      },
      {
        source: '/api/projections/:path*',
        destination: 'http://localhost:8080/api/projections/:path*',
      },
      {
        source: '/api/health/:path*',
        destination: 'http://localhost:8080/api/health/:path*',
      },
    ];
  },
  webpack: (config) => {
    config.resolve.fallback = {
      ...config.resolve.fallback,
      fs: false,
    };
    return config;
  },
};

module.exports = nextConfig;