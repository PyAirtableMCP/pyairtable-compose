"use client"

import * as React from "react"
import {
  ColumnDef,
  flexRender,
  getCoreRowModel,
  useReactTable,
  SortingState,
  getSortedRowModel,
  ColumnFiltersState,
  getFilteredRowModel,
  VisibilityState,
  getPaginationRowModel,
} from "@tanstack/react-table"
import { useVirtualizer } from "@tanstack/react-virtual"
import { ChevronDown, ChevronUp, Search, Filter, Download, RefreshCw } from "lucide-react"

import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Skeleton } from "@/components/ui/skeleton"
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"

interface DataTableProps<TData, TValue> {
  columns: ColumnDef<TData, TValue>[]
  data: TData[]
  loading?: boolean
  error?: string | null
  onRefresh?: () => void
  onExport?: () => void
  searchPlaceholder?: string
  enableVirtualization?: boolean
  enableFiltering?: boolean
  enableColumnVisibility?: boolean
  enablePagination?: boolean
  className?: string
}

export function DataTable<TData, TValue>({
  columns,
  data,
  loading = false,
  error = null,
  onRefresh,
  onExport,
  searchPlaceholder = "Search...",
  enableVirtualization = true,
  enableFiltering = true,
  enableColumnVisibility = true,
  enablePagination = false,
  className,
}: DataTableProps<TData, TValue>) {
  const [sorting, setSorting] = React.useState<SortingState>([])
  const [columnFilters, setColumnFilters] = React.useState<ColumnFiltersState>([])
  const [columnVisibility, setColumnVisibility] = React.useState<VisibilityState>({})
  const [globalFilter, setGlobalFilter] = React.useState("")

  const table = useReactTable({
    data,
    columns,
    getCoreRowModel: getCoreRowModel(),
    getPaginationRowModel: enablePagination ? getPaginationRowModel() : undefined,
    getSortedRowModel: getSortedRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    onSortingChange: setSorting,
    onColumnFiltersChange: setColumnFilters,
    onColumnVisibilityChange: setColumnVisibility,
    onGlobalFilterChange: setGlobalFilter,
    globalFilterFn: "includesString",
    state: {
      sorting,
      columnFilters,
      columnVisibility,
      globalFilter,
    },
  })

  const { rows } = table.getRowModel()

  // Virtual scrolling setup
  const parentRef = React.useRef<HTMLDivElement>(null)
  const virtualizer = useVirtualizer({
    count: rows.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 50,
    overscan: 5,
    enabled: enableVirtualization && !enablePagination,
  })

  const virtualItems = virtualizer.getVirtualItems()

  // Error state
  if (error) {
    return (
      <div className={cn("rounded-lg border", className)}>
        <DataTableHeader
          table={table}
          globalFilter={globalFilter}
          setGlobalFilter={setGlobalFilter}
          onRefresh={onRefresh}
          onExport={onExport}
          searchPlaceholder={searchPlaceholder}
          enableFiltering={enableFiltering}
          enableColumnVisibility={enableColumnVisibility}
        />
        <div className="flex items-center justify-center h-48">
          <div className="text-center">
            <p className="text-destructive font-medium">Error loading data</p>
            <p className="text-sm text-muted-foreground mt-1">{error}</p>
            {onRefresh && (
              <Button
                variant="outline"
                size="sm"
                onClick={onRefresh}
                className="mt-4"
              >
                <RefreshCw className="h-4 w-4 mr-2" />
                Retry
              </Button>
            )}
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className={cn("rounded-lg border", className)}>
      <DataTableHeader
        table={table}
        globalFilter={globalFilter}
        setGlobalFilter={setGlobalFilter}
        onRefresh={onRefresh}
        onExport={onExport}
        searchPlaceholder={searchPlaceholder}
        enableFiltering={enableFiltering}
        enableColumnVisibility={enableColumnVisibility}
      />

      {/* Table */}
      <div className="relative">
        <div className="rounded-md border-t">
          <table className="w-full">
            <thead className="bg-muted/50">
              {table.getHeaderGroups().map((headerGroup) => (
                <tr key={headerGroup.id}>
                  {headerGroup.headers.map((header) => (
                    <th
                      key={header.id}
                      className="h-12 px-4 text-left align-middle font-medium text-muted-foreground [&:has([role=checkbox])]:pr-0"
                    >
                      {header.isPlaceholder ? null : (
                        <div
                          className={cn(
                            "flex items-center space-x-2",
                            header.column.getCanSort() && "cursor-pointer select-none"
                          )}
                          onClick={header.column.getToggleSortingHandler()}
                        >
                          {flexRender(header.column.columnDef.header, header.getContext())}
                          {header.column.getCanSort() && (
                            <div className="flex flex-col">
                              <ChevronUp
                                className={cn(
                                  "h-3 w-3",
                                  header.column.getIsSorted() === "asc"
                                    ? "text-foreground"
                                    : "text-muted-foreground/50"
                                )}
                              />
                              <ChevronDown
                                className={cn(
                                  "h-3 w-3 -mt-1",
                                  header.column.getIsSorted() === "desc"
                                    ? "text-foreground"
                                    : "text-muted-foreground/50"
                                )}
                              />
                            </div>
                          )}
                        </div>
                      )}
                    </th>
                  ))}
                </tr>
              ))}
            </thead>

            {loading ? (
              <tbody>
                {Array.from({ length: 10 }).map((_, index) => (
                  <tr key={index}>
                    {columns.map((_, colIndex) => (
                      <td key={colIndex} className="h-12 px-4">
                        <Skeleton className="h-4 w-full" />
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            ) : enableVirtualization && !enablePagination ? (
              <tbody>
                <tr>
                  <td colSpan={columns.length} className="p-0">
                    <div
                      ref={parentRef}
                      className="h-96 overflow-auto"
                      style={{
                        contain: 'strict',
                      }}
                    >
                      <div
                        style={{
                          height: `${virtualizer.getTotalSize()}px`,
                          width: '100%',
                          position: 'relative',
                        }}
                      >
                        {virtualItems.map((virtualItem) => {
                          const row = rows[virtualItem.index]
                          return (
                            <div
                              key={row.id}
                              className="absolute top-0 left-0 w-full flex border-b"
                              style={{
                                height: `${virtualItem.size}px`,
                                transform: `translateY(${virtualItem.start}px)`,
                              }}
                            >
                              {row.getVisibleCells().map((cell) => (
                                <div
                                  key={cell.id}
                                  className="px-4 py-2 text-sm flex items-center"
                                  style={{
                                    width: cell.column.getSize(),
                                  }}
                                >
                                  {flexRender(cell.column.columnDef.cell, cell.getContext())}
                                </div>
                              ))}
                            </div>
                          )
                        })}
                      </div>
                    </div>
                  </td>
                </tr>
              </tbody>
            ) : (
              <tbody>
                {rows.length === 0 ? (
                  <tr>
                    <td colSpan={columns.length} className="h-24 text-center">
                      <div className="flex flex-col items-center justify-center">
                        <p className="text-muted-foreground">No results found</p>
                        {globalFilter && (
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => setGlobalFilter("")}
                            className="mt-2"
                          >
                            Clear search
                          </Button>
                        )}
                      </div>
                    </td>
                  </tr>
                ) : (
                  rows.map((row) => (
                    <tr
                      key={row.id}
                      className="border-b transition-colors hover:bg-muted/50 data-[state=selected]:bg-muted"
                    >
                      {row.getVisibleCells().map((cell) => (
                        <td key={cell.id} className="p-4 align-middle [&:has([role=checkbox])]:pr-0">
                          {flexRender(cell.column.columnDef.cell, cell.getContext())}
                        </td>
                      ))}
                    </tr>
                  ))
                )}
              </tbody>
            )}
          </table>
        </div>

        {/* Pagination */}
        {enablePagination && (
          <div className="flex items-center justify-between space-x-2 py-4 px-4">
            <div className="flex-1 text-sm text-muted-foreground">
              {table.getFilteredSelectedRowModel().rows.length} of{" "}
              {table.getFilteredRowModel().rows.length} row(s) selected.
            </div>
            <div className="space-x-2">
              <Button
                variant="outline"
                size="sm"
                onClick={() => table.previousPage()}
                disabled={!table.getCanPreviousPage()}
              >
                Previous
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={() => table.nextPage()}
                disabled={!table.getCanNextPage()}
              >
                Next
              </Button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

interface DataTableHeaderProps<TData> {
  table: any
  globalFilter: string
  setGlobalFilter: (value: string) => void
  onRefresh?: () => void
  onExport?: () => void
  searchPlaceholder: string
  enableFiltering: boolean
  enableColumnVisibility: boolean
}

function DataTableHeader<TData>({
  table,
  globalFilter,
  setGlobalFilter,
  onRefresh,
  onExport,
  searchPlaceholder,
  enableFiltering,
  enableColumnVisibility,
}: DataTableHeaderProps<TData>) {
  return (
    <div className="flex items-center justify-between p-4">
      <div className="flex items-center space-x-2">
        {enableFiltering && (
          <div className="relative">
            <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder={searchPlaceholder}
              value={globalFilter}
              onChange={(e) => setGlobalFilter(e.target.value)}
              className="pl-8 w-64"
            />
          </div>
        )}
        
        {table.getColumn("status") && (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" size="sm">
                <Filter className="h-4 w-4 mr-2" />
                Status
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent>
              {["active", "inactive", "pending"].map((status) => (
                <DropdownMenuCheckboxItem
                  key={status}
                  checked={table.getColumn("status")?.getFilterValue() === status}
                  onCheckedChange={(checked) =>
                    table.getColumn("status")?.setFilterValue(checked ? status : undefined)
                  }
                >
                  <Badge variant="secondary" className="mr-2">
                    {status}
                  </Badge>
                  {status.charAt(0).toUpperCase() + status.slice(1)}
                </DropdownMenuCheckboxItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </div>

      <div className="flex items-center space-x-2">
        {onRefresh && (
          <Button
            variant="outline"
            size="sm"
            onClick={onRefresh}
          >
            <RefreshCw className="h-4 w-4" />
          </Button>
        )}

        {onExport && (
          <Button
            variant="outline"
            size="sm"
            onClick={onExport}
          >
            <Download className="h-4 w-4 mr-2" />
            Export
          </Button>
        )}

        {enableColumnVisibility && (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" size="sm">
                Columns <ChevronDown className="ml-2 h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              {table
                .getAllColumns()
                .filter((column: any) => column.getCanHide())
                .map((column: any) => {
                  return (
                    <DropdownMenuCheckboxItem
                      key={column.id}
                      className="capitalize"
                      checked={column.getIsVisible()}
                      onCheckedChange={(value) => column.toggleVisibility(!!value)}
                    >
                      {column.id}
                    </DropdownMenuCheckboxItem>
                  )
                })}
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </div>
    </div>
  )
}