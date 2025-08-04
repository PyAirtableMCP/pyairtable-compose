import React from 'react'
import { render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { DashboardOverview } from '../DashboardOverview'
import * as api from '@/lib/api'

// Mock the API module
jest.mock('@/lib/api')
const mockedApi = api as jest.Mocked<typeof api>

// Test data
const mockDashboardData = {
  totalWorkspaces: 5,
  totalTables: 25,
  totalRecords: 1250,
  recentActivity: [
    {
      id: '1',
      type: 'workspace_created',
      description: 'Created workspace "Marketing Analytics"',
      timestamp: '2024-01-15T10:30:00Z',
      user: 'John Doe',
    },
    {
      id: '2',
      type: 'table_updated',
      description: 'Updated table "Campaigns"',
      timestamp: '2024-01-15T09:15:00Z',
      user: 'Jane Smith',
    },
  ],
  usageMetrics: {
    apiCalls: 8750,
    storageUsed: 2.5, // GB
    bandwidthUsed: 150, // MB
  },
}

const createWrapper = () => {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,
      },
    },
  })
  
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={queryClient}>
      {children}
    </QueryClientProvider>
  )
}

describe('DashboardOverview', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('renders loading state initially', () => {
    mockedApi.getDashboardOverview.mockImplementation(() => 
      new Promise(() => {}) // Never resolves to keep loading state
    )

    render(<DashboardOverview />, { wrapper: createWrapper() })
    
    expect(screen.getByTestId('dashboard-loading')).toBeInTheDocument()
  })

  it('renders dashboard data when loaded successfully', async () => {
    mockedApi.getDashboardOverview.mockResolvedValue(mockDashboardData)

    render(<DashboardOverview />, { wrapper: createWrapper() })

    await waitFor(() => {
      expect(screen.queryByTestId('dashboard-loading')).not.toBeInTheDocument()
    })

    // Check metric cards
    expect(screen.getByText('5')).toBeInTheDocument() // Total workspaces
    expect(screen.getByText('25')).toBeInTheDocument() // Total tables
    expect(screen.getByText('1,250')).toBeInTheDocument() // Total records

    // Check recent activity
    expect(screen.getByText('Created workspace "Marketing Analytics"')).toBeInTheDocument()
    expect(screen.getByText('Updated table "Campaigns"')).toBeInTheDocument()
    expect(screen.getByText('John Doe')).toBeInTheDocument()
    expect(screen.getByText('Jane Smith')).toBeInTheDocument()

    // Check usage metrics
    expect(screen.getByText('8,750')).toBeInTheDocument() // API calls
    expect(screen.getByText('2.5 GB')).toBeInTheDocument() // Storage
    expect(screen.getByText('150 MB')).toBeInTheDocument() // Bandwidth
  })

  it('renders error state when API call fails', async () => {
    const errorMessage = 'Failed to fetch dashboard data'
    mockedApi.getDashboardOverview.mockRejectedValue(new Error(errorMessage))

    render(<DashboardOverview />, { wrapper: createWrapper() })

    await waitFor(() => {
      expect(screen.getByTestId('dashboard-error')).toBeInTheDocument()
    })

    expect(screen.getByText(/failed to load dashboard data/i)).toBeInTheDocument()
  })

  it('formats numbers correctly', async () => {
    const largeNumberData = {
      ...mockDashboardData,
      totalRecords: 1250000, // 1.25M
      usageMetrics: {
        ...mockDashboardData.usageMetrics,
        apiCalls: 875000, // 875k
      },
    }

    mockedApi.getDashboardOverview.mockResolvedValue(largeNumberData)

    render(<DashboardOverview />, { wrapper: createWrapper() })

    await waitFor(() => {
      expect(screen.getByText('1.25M')).toBeInTheDocument()
      expect(screen.getByText('875K')).toBeInTheDocument()
    })
  })

  it('handles empty activity list gracefully', async () => {
    const emptyActivityData = {
      ...mockDashboardData,
      recentActivity: [],
    }

    mockedApi.getDashboardOverview.mockResolvedValue(emptyActivityData)

    render(<DashboardOverview />, { wrapper: createWrapper() })

    await waitFor(() => {
      expect(screen.getByText(/no recent activity/i)).toBeInTheDocument()
    })
  })

  it('refreshes data when refresh button is clicked', async () => {
    mockedApi.getDashboardOverview.mockResolvedValue(mockDashboardData)

    render(<DashboardOverview />, { wrapper: createWrapper() })

    await waitFor(() => {
      expect(mockedApi.getDashboardOverview).toHaveBeenCalledTimes(1)
    })

    // Click refresh button
    const refreshButton = screen.getByRole('button', { name: /refresh/i })
    refreshButton.click()

    await waitFor(() => {
      expect(mockedApi.getDashboardOverview).toHaveBeenCalledTimes(2)
    })
  })

  it('displays relative timestamps for activity items', async () => {
    const recentData = {
      ...mockDashboardData,
      recentActivity: [
        {
          id: '1',
          type: 'workspace_created',
          description: 'Created workspace "Test"',
          timestamp: new Date(Date.now() - 5 * 60 * 1000).toISOString(), // 5 minutes ago
          user: 'Test User',
        },
      ],
    }

    mockedApi.getDashboardOverview.mockResolvedValue(recentData)

    render(<DashboardOverview />, { wrapper: createWrapper() })

    await waitFor(() => {
      expect(screen.getByText(/5 minutes ago/i)).toBeInTheDocument()
    })
  })

  it('has accessible labels and roles', async () => {
    mockedApi.getDashboardOverview.mockResolvedValue(mockDashboardData)

    render(<DashboardOverview />, { wrapper: createWrapper() })

    await waitFor(() => {
      // Check that metric cards have proper labels
      expect(screen.getByLabelText(/total workspaces/i)).toBeInTheDocument()
      expect(screen.getByLabelText(/total tables/i)).toBeInTheDocument()
      expect(screen.getByLabelText(/total records/i)).toBeInTheDocument()

      // Check that activity section has proper heading
      expect(screen.getByRole('heading', { name: /recent activity/i })).toBeInTheDocument()
    })
  })
})