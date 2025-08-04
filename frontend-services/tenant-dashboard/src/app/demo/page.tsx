"use client"

import React from "react"
import { ColumnDef } from "@tanstack/react-table"
import { MoreHorizontal, ArrowUpDown, ExternalLink, Edit, Trash2 } from "lucide-react"

import { MainLayout } from "@/components/layout/MainLayout"
import { 
  DataTable, 
  MetricGrid, 
  MetricCard, 
  Button, 
  Badge, 
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/design-system"

// Mock data for demonstration
interface AirtableRecord {
  id: string
  name: string
  email: string
  status: "active" | "inactive" | "pending"
  plan: "free" | "pro" | "enterprise"
  usage: number
  lastActive: string
  createdAt: string
}

const generateMockData = (count: number): AirtableRecord[] => {
  const statuses: AirtableRecord["status"][] = ["active", "inactive", "pending"]
  const plans: AirtableRecord["plan"][] = ["free", "pro", "enterprise"]
  
  return Array.from({ length: count }, (_, i) => ({
    id: `record-${i + 1}`,
    name: `User ${i + 1}`,
    email: `user${i + 1}@example.com`,
    status: statuses[Math.floor(Math.random() * statuses.length)],
    plan: plans[Math.floor(Math.random() * plans.length)],
    usage: Math.floor(Math.random() * 100),
    lastActive: new Date(Date.now() - Math.random() * 30 * 24 * 60 * 60 * 1000).toISOString(),
    createdAt: new Date(Date.now() - Math.random() * 365 * 24 * 60 * 60 * 1000).toISOString(),
  }))
}

export default function DemoPage() {
  const [data, setData] = React.useState<AirtableRecord[]>([])
  const [loading, setLoading] = React.useState(true)

  // Simulate API call
  React.useEffect(() => {
    const loadData = async () => {
      setLoading(true)
      // Simulate network delay
      await new Promise(resolve => setTimeout(resolve, 1000))
      setData(generateMockData(10000)) // Large dataset for virtual scrolling demo
      setLoading(false)
    }

    loadData()
  }, [])

  const handleRefresh = () => {
    setLoading(true)
    setTimeout(() => {
      setData(generateMockData(10000))
      setLoading(false)
    }, 500)
  }

  const handleExport = () => {
    // Mock export functionality
    const csv = [
      'ID,Name,Email,Status,Plan,Usage,Last Active,Created At',
      ...data.slice(0, 100).map(record => 
        `${record.id},${record.name},${record.email},${record.status},${record.plan},${record.usage}%,${record.lastActive},${record.createdAt}`
      )
    ].join('\n')
    
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'airtable-records.csv'
    a.click()
    URL.revokeObjectURL(url)
  }

  const handleEdit = (record: AirtableRecord) => {
    console.log('Edit record:', record)
    // In real app, this would open an edit modal
  }

  const handleDelete = (record: AirtableRecord) => {
    console.log('Delete record:', record)
    // In real app, this would show a confirmation dialog
    setData(prev => prev.filter(r => r.id !== record.id))
  }

  const handleView = (record: AirtableRecord) => {
    console.log('View record:', record)
    // In real app, this would navigate to detail view
  }

  const columns: ColumnDef<AirtableRecord>[] = [
    {
      accessorKey: "name",
      header: ({ column }) => {
        return (
          <Button
            variant="ghost"
            onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
            className="h-8 px-2"
          >
            Name
            <ArrowUpDown className="ml-2 h-4 w-4" />
          </Button>
        )
      },
      cell: ({ row }) => (
        <div className="font-medium">
          {row.getValue("name")}
        </div>
      ),
    },
    {
      accessorKey: "email",
      header: "Email",
      cell: ({ row }) => (
        <div className="text-muted-foreground">
          {row.getValue("email")}
        </div>
      ),
    },
    {
      accessorKey: "status",
      header: "Status",
      cell: ({ row }) => {
        const status = row.getValue("status") as string
        return (
          <Badge
            variant={
              status === "active" 
                ? "default" 
                : status === "pending" 
                ? "secondary" 
                : "outline"
            }
          >
            {status}
          </Badge>
        )
      },
    },
    {
      accessorKey: "plan",
      header: "Plan",
      cell: ({ row }) => {
        const plan = row.getValue("plan") as string
        return (
          <Badge
            variant={
              plan === "enterprise" 
                ? "default" 
                : plan === "pro" 
                ? "secondary" 
                : "outline"
            }
          >
            {plan}
          </Badge>
        )
      },
    },
    {
      accessorKey: "usage",
      header: ({ column }) => {
        return (
          <Button
            variant="ghost"
            onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
            className="h-8 px-2"
          >
            Usage
            <ArrowUpDown className="ml-2 h-4 w-4" />
          </Button>
        )
      },
      cell: ({ row }) => {
        const usage = row.getValue("usage") as number
        return (
          <div className="text-right font-mono">
            {usage}%
          </div>
        )
      },
    },
    {
      accessorKey: "lastActive",
      header: "Last Active",
      cell: ({ row }) => {
        const date = new Date(row.getValue("lastActive"))
        return (
          <div className="text-sm text-muted-foreground">
            {date.toLocaleDateString()}
          </div>
        )
      },
    },
    {
      id: "actions",
      enableHiding: false,
      cell: ({ row }) => {
        const record = row.original

        return (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" className="h-8 w-8 p-0">
                <span className="sr-only">Open menu</span>
                <MoreHorizontal className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuLabel>Actions</DropdownMenuLabel>
              <DropdownMenuItem onClick={() => handleView(record)}>
                <ExternalLink className="mr-2 h-4 w-4" />
                View details
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => handleEdit(record)}>
                <Edit className="mr-2 h-4 w-4" />
                Edit record
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem 
                onClick={() => handleDelete(record)}
                className="text-destructive"
              >
                <Trash2 className="mr-2 h-4 w-4" />
                Delete
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        )
      },
    },
  ]

  return (
    <MainLayout>
      <div className="space-y-6">
        <div>
          <h1 className="text-3xl font-bold">Design System Demo</h1>
          <p className="text-muted-foreground">
            Demonstration of the unified design system with virtual scrolling data table
          </p>
        </div>

        {/* Metrics */}
        <MetricGrid columns={4}>
          <MetricCard
            title="Total Records"
            value={data.length.toLocaleString()}
            description="Across all tables"
            loading={loading}
          />
          <MetricCard
            title="Active Users"
            value={data.filter(r => r.status === "active").length}
            change={{
              value: 12.5,
              label: "vs last month",
              trend: "up"
            }}
            loading={loading}
            variant="success"
          />
          <MetricCard
            title="Pro Plans"
            value={data.filter(r => r.plan === "pro").length}
            change={{
              value: 5.2,
              label: "vs last month", 
              trend: "up"
            }}
            loading={loading}
          />
          <MetricCard
            title="Enterprise"
            value={data.filter(r => r.plan === "enterprise").length}
            change={{
              value: 2.1,
              label: "vs last month",
              trend: "down"
            }}
            loading={loading}
            variant="outline"
          />
        </MetricGrid>

        {/* Virtual Scrolling Data Table */}
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-2xl font-semibold">Airtable Records</h2>
              <p className="text-muted-foreground">
                Manage your Airtable data with virtual scrolling for performance
              </p>
            </div>
          </div>

          <DataTable
            columns={columns}
            data={data}
            loading={loading}
            onRefresh={handleRefresh}
            onExport={handleExport}
            searchPlaceholder="Search records..."
            enableVirtualization={true}
            enableFiltering={true}
            enableColumnVisibility={true}
            enablePagination={false}
          />
        </div>

        {/* Feature Showcase */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <div className="space-y-4">
            <h3 className="text-lg font-semibold">Virtual Scrolling</h3>
            <p className="text-sm text-muted-foreground">
              Handle thousands of records with smooth scrolling performance
            </p>
            <ul className="text-sm space-y-1">
              <li>• Renders only visible rows</li>
              <li>• Smooth scrolling experience</li>
              <li>• Memory efficient</li>
              <li>• Handles 10,000+ records</li>
            </ul>
          </div>

          <div className="space-y-4">
            <h3 className="text-lg font-semibold">Command Palette</h3>
            <p className="text-sm text-muted-foreground">
              Quick navigation and actions with keyboard shortcuts
            </p>
            <ul className="text-sm space-y-1">
              <li>• Press Cmd/Ctrl + K to open</li>
              <li>• Navigate to any page</li>
              <li>• Theme switching</li>
              <li>• Keyboard shortcuts</li>
            </ul>
          </div>

          <div className="space-y-4">
            <h3 className="text-lg font-semibold">PWA Features</h3>
            <p className="text-sm text-muted-foreground">
              Progressive web app with offline capabilities
            </p>
            <ul className="text-sm space-y-1">
              <li>• Install as desktop app</li>
              <li>• Offline data access</li>
              <li>• Background sync</li>
              <li>• Push notifications</li>
            </ul>
          </div>
        </div>
      </div>
    </MainLayout>
  )
}