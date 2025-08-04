"use client"

import * as React from "react"
import { useRouter } from "next/navigation"
import {
  Calculator,
  Calendar,
  CreditCard,
  Settings,
  Smile,
  User,
  Home,
  BarChart3,
  Users,
  Building2,
  FileText,
  Database,
  Search,
  HelpCircle,
  LogOut,
  Moon,
  Sun,
  Monitor,
} from "lucide-react"

import {
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandSeparator,
  CommandShortcut,
} from "@/components/ui/command"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { useTheme } from "next-themes"
import { signOut } from "next-auth/react"

interface CommandItem {
  id: string
  title: string
  description?: string
  icon: React.ComponentType<{ className?: string }>
  action: () => void
  shortcut?: string[]
  badge?: string
  group: string
}

interface CommandPaletteProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function CommandPalette({ open, onOpenChange }: CommandPaletteProps) {
  const router = useRouter()
  const { setTheme, theme } = useTheme()
  const [search, setSearch] = React.useState("")

  // Define all available commands
  const commands: CommandItem[] = [
    // Navigation commands
    {
      id: "nav-home",
      title: "Go to Dashboard",
      description: "Navigate to the main dashboard",
      icon: Home,
      action: () => router.push("/"),
      shortcut: ["g", "h"],
      group: "Navigation",
    },
    {
      id: "nav-analytics",
      title: "Go to Analytics",
      description: "View analytics and insights",
      icon: BarChart3,
      action: () => router.push("/analytics"),
      shortcut: ["g", "a"],
      group: "Navigation",
    },
    {
      id: "nav-users",
      title: "Go to Users",
      description: "Manage users and permissions",
      icon: Users,
      action: () => router.push("/users"),
      shortcut: ["g", "u"],
      group: "Navigation",
    },
    {
      id: "nav-tenants",
      title: "Go to Tenants",
      description: "Manage tenant organizations",
      icon: Building2,
      action: () => router.push("/tenants"),
      shortcut: ["g", "t"],
      group: "Navigation",
    },
    {
      id: "nav-settings",
      title: "Go to Settings",
      description: "Configure application settings",
      icon: Settings,
      action: () => router.push("/settings"),
      shortcut: ["g", "s"],
      group: "Navigation",
    },

    // Actions
    {
      id: "action-search",
      title: "Global Search",
      description: "Search across all data",
      icon: Search,
      action: () => {
        // TODO: Open global search modal
        onOpenChange(false)
      },
      shortcut: ["⌘", "/"],
      group: "Actions",
    },
    {
      id: "action-calculator",
      title: "Calculator",
      description: "Open calculator",
      icon: Calculator,
      action: () => {
        // TODO: Open calculator modal
        onOpenChange(false)
      },
      group: "Tools",
    },
    {
      id: "action-calendar",
      title: "Calendar",
      description: "View calendar events",
      icon: Calendar,
      action: () => {
        // TODO: Open calendar modal
        onOpenChange(false)
      },
      group: "Tools",
    },

    // Theme commands
    {
      id: "theme-light",
      title: "Light Theme",
      description: "Switch to light theme",
      icon: Sun,
      action: () => setTheme("light"),
      badge: theme === "light" ? "Active" : undefined,
      group: "Appearance",
    },
    {
      id: "theme-dark",
      title: "Dark Theme",
      description: "Switch to dark theme",
      icon: Moon,
      action: () => setTheme("dark"),
      badge: theme === "dark" ? "Active" : undefined,
      group: "Appearance",
    },
    {
      id: "theme-system",
      title: "System Theme",
      description: "Use system theme",
      icon: Monitor,
      action: () => setTheme("system"),
      badge: theme === "system" ? "Active" : undefined,
      group: "Appearance",
    },

    // Account commands
    {
      id: "account-profile",
      title: "View Profile",
      description: "View and edit your profile",
      icon: User,
      action: () => router.push("/profile"),
      group: "Account",
    },
    {
      id: "account-billing",
      title: "Billing",
      description: "Manage billing and subscription",
      icon: CreditCard,
      action: () => router.push("/billing"),
      group: "Account",
    },
    {
      id: "account-logout",
      title: "Sign Out",
      description: "Sign out of your account",
      icon: LogOut,
      action: () => signOut(),
      group: "Account",
    },

    // Help
    {
      id: "help-docs",
      title: "Documentation",
      description: "View help documentation",
      icon: FileText,
      action: () => window.open("/docs", "_blank"),
      group: "Help",
    },
    {
      id: "help-support",
      title: "Contact Support",
      description: "Get help from our support team",
      icon: HelpCircle,
      action: () => window.open("/support", "_blank"),
      group: "Help",
    },
  ]

  // Filter commands based on search
  const filteredCommands = React.useMemo(() => {
    if (!search) return commands
    
    return commands.filter((command) =>
      command.title.toLowerCase().includes(search.toLowerCase()) ||
      command.description?.toLowerCase().includes(search.toLowerCase()) ||
      command.group.toLowerCase().includes(search.toLowerCase())
    )
  }, [search, commands])

  // Group commands
  const groupedCommands = React.useMemo(() => {
    const groups: Record<string, CommandItem[]> = {}
    
    filteredCommands.forEach((command) => {
      if (!groups[command.group]) {
        groups[command.group] = []
      }
      groups[command.group].push(command)
    })
    
    return groups
  }, [filteredCommands])

  // Handle command execution
  const executeCommand = React.useCallback((command: CommandItem) => {
    onOpenChange(false)
    // Small delay to allow the dialog to close first
    setTimeout(() => {
      command.action()
    }, 100)
  }, [onOpenChange])

  // Keyboard shortcuts
  React.useEffect(() => {
    const down = (e: KeyboardEvent) => {
      // Command + K or Ctrl + K to open
      if ((e.key === "k" && (e.metaKey || e.ctrlKey)) || (e.key === "/" && (e.metaKey || e.ctrlKey))) {
        e.preventDefault()
        onOpenChange(!open)
      }

      // ESC to close
      if (e.key === "Escape") {
        onOpenChange(false)
      }

      // Handle command shortcuts when palette is closed
      if (!open) {
        commands.forEach((command) => {
          if (command.shortcut && command.shortcut.length === 2) {
            const [first, second] = command.shortcut
            if (
              e.key === second &&
              ((first === "⌘" && e.metaKey) || 
               (first === "g" && e.key === second && !e.metaKey && !e.ctrlKey))
            ) {
              e.preventDefault()
              command.action()
            }
          }
        })
      }
    }

    document.addEventListener("keydown", down)
    return () => document.removeEventListener("keydown", down)
  }, [open, onOpenChange, commands])

  return (
    <CommandDialog open={open} onOpenChange={onOpenChange}>
      <CommandInput
        placeholder="Type a command or search..."
        value={search}
        onValueChange={setSearch}
      />
      <CommandList>
        <CommandEmpty>
          <div className="flex flex-col items-center justify-center py-6">
            <Search className="h-8 w-8 text-muted-foreground mb-2" />
            <p className="text-sm text-muted-foreground">No results found.</p>
            <p className="text-xs text-muted-foreground mt-1">
              Try searching for navigation, actions, or settings.
            </p>
          </div>
        </CommandEmpty>

        {Object.entries(groupedCommands).map(([group, commands], groupIndex) => (
          <React.Fragment key={group}>
            {groupIndex > 0 && <CommandSeparator />}
            <CommandGroup heading={group}>
              {commands.map((command) => (
                <CommandItem
                  key={command.id}
                  value={`${command.title} ${command.description} ${command.group}`}
                  onSelect={() => executeCommand(command)}
                  className="flex items-center gap-3 px-3 py-2"
                >
                  <command.icon className="h-4 w-4 text-muted-foreground" />
                  <div className="flex-1 space-y-1">
                    <div className="flex items-center gap-2">
                      <span className="font-medium">{command.title}</span>
                      {command.badge && (
                        <Badge variant="secondary" className="text-xs">
                          {command.badge}
                        </Badge>
                      )}
                    </div>
                    {command.description && (
                      <p className="text-xs text-muted-foreground">
                        {command.description}
                      </p>
                    )}
                  </div>
                  {command.shortcut && (
                    <CommandShortcut>
                      {command.shortcut.join(" ")}
                    </CommandShortcut>
                  )}
                </CommandItem>
              ))}
            </CommandGroup>
          </React.Fragment>
        ))}
      </CommandList>
    </CommandDialog>
  )
}

// Hook to use command palette
export function useCommandPalette() {
  const [open, setOpen] = React.useState(false)

  const toggle = React.useCallback(() => {
    setOpen((open) => !open)
  }, [])

  return {
    open,
    setOpen,
    toggle,
    CommandPalette: React.useCallback(
      () => <CommandPalette open={open} onOpenChange={setOpen} />,
      [open, setOpen]
    ),
  }
}

// Global command palette trigger button
export function CommandPaletteTrigger() {
  const { toggle } = useCommandPalette()

  return (
    <Button
      variant="outline"
      className="relative h-9 w-full justify-start text-sm text-muted-foreground sm:pr-12 md:w-40 lg:w-64"
      onClick={toggle}
    >
      <Search className="mr-2 h-4 w-4" />
      <span className="hidden lg:inline-flex">Search commands...</span>
      <span className="inline-flex lg:hidden">Search...</span>
      <kbd className="pointer-events-none absolute right-1.5 top-2 hidden h-5 select-none items-center gap-1 rounded border bg-muted px-1.5 font-mono text-[10px] font-medium opacity-100 sm:flex">
        <span className="text-xs">⌘</span>K
      </kbd>
    </Button>
  )
}