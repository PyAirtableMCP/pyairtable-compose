# PyAirtable Event Sourcing UI - Claude Context

## 🎯 Service Purpose
Advanced event-driven architecture visualization and management interface for PyAirtable's event sourcing system. Provides real-time monitoring of event streams, SAGA orchestration, projection management, and distributed system debugging capabilities.

## 🔧 Technology Stack
- **Framework:** Next.js 15 with App Router and TypeScript
- **Styling:** Tailwind CSS optimized for technical interfaces
- **UI Components:** Radix UI with specialized event visualization components
- **Testing:** **Playwright configured for complex event flow testing**
- **Alternative Testing:** **Puppeteer for automated event system validation**
- **Real-time:** WebSocket connections for live event streaming
- **Visualization:** Custom event timeline and flow diagrams
- **State Management:** Zustand optimized for event-driven data

## 🎭 Event System Testing with Playwright

### **Event Flow Testing**
```bash
# Event-specific test commands
npm run test:event-flows       # Event sourcing workflow tests
npm run test:saga-orchestration # SAGA transaction testing
npm run test:projections       # Projection rebuild testing
npm run test:event-replay      # Event replay scenario testing
npm run test:visual:events     # Event UI visual regression
```

### **Complex Event Scenarios**
- **Event Streaming:** Real-time event visualization and monitoring
- **SAGA Orchestration:** Distributed transaction flow testing
- **Event Replay:** Historical event reconstruction and playback
- **Projection Rebuilding:** Event projection consistency testing
- **Error Recovery:** Event system failure and recovery scenarios

### **Synthetic Event Agents**

#### **Event System Behavior Simulation**
```typescript
// Realistic event system interaction
await eventAgent.triggerEventFlow('user-registration', userData);
await eventAgent.monitorSAGACompletion(sagaId, timeout);
await eventAgent.validateProjectionConsistency(projection);
await eventAgent.simulateEventReplay(fromTimestamp, toTimestamp);
```

#### **Event-Specific Testing Behaviors**
- **Temporal Analysis:** Time-based event sequence validation
- **Causality Checking:** Event cause-and-effect relationship testing
- **Concurrency Testing:** Parallel event stream validation
- **Consistency Verification:** Event sourcing consistency checks

## 📊 Event Sourcing Dashboard Features

### **Real-Time Event Monitoring**
- **Event Stream Visualization:** Live event timeline with filtering
- **Event Type Analytics:** Event frequency and pattern analysis
- **Error Event Tracking:** Failed events and retry mechanisms
- **Performance Metrics:** Event processing latency and throughput

### **SAGA Orchestration Management**
- **Active SAGA Monitoring:** Real-time SAGA transaction status
- **SAGA State Visualization:** Step-by-step SAGA progress tracking
- **Compensation Tracking:** SAGA rollback and compensation monitoring
- **SAGA Performance:** Transaction duration and success rates

### **Event Projections**
- **Projection Status:** Real-time projection health and lag monitoring
- **Rebuild Operations:** Projection rebuild progress and controls
- **Consistency Checks:** Projection consistency validation tools
- **Query Performance:** Read model performance optimization

### **Development Tools**
- **Event Schema Browser:** Explore event structures and schemas
- **Event Simulator:** Generate test events for development
- **Event Debugger:** Step through event processing flows
- **Performance Profiler:** Analyze event processing bottlenecks

### **System Health Monitoring**
- **Service Topology:** Visual map of event-driven services
- **Queue Metrics:** Event queue depth and processing rates
- **Error Analytics:** Event processing error analysis and trends
- **Resource Usage:** Event processing resource consumption

## 🤖 Automated Event Testing with Puppeteer

### **Event System Automation**
```bash
# Automated event system operations
npm run automate:event-replay     # Automated event replay testing
npm run automate:projection-rebuild # Automated projection rebuilds
npm run automate:saga-validation    # Automated SAGA flow validation
npm run automate:performance-test   # Event system performance testing
```

### **Puppeteer Event Use Cases**
- **Automated Testing:** Continuous event system validation
- **Performance Monitoring:** Automated performance regression testing
- **Data Consistency:** Automated consistency checking across projections
- **Load Testing:** High-volume event generation and processing

## 🔄 Event System Visual Testing

### **Event-Specific Visual Tests**
```bash
# Event UI visual validation
npm run test:visual:timeline      # Event timeline visualization
npm run test:visual:saga-flows    # SAGA flow diagrams
npm run test:visual:projections   # Projection status interfaces
npm run test:visual:metrics       # Event metrics dashboards
```

### **Visual Test Categories**
- **Timeline Visualizations:** Event sequence and timing displays
- **Flow Diagrams:** SAGA and event flow visualizations
- **Status Dashboards:** System health and monitoring interfaces
- **Debug Interfaces:** Event debugging and analysis tools
- **Performance Charts:** Event processing metrics and trends

## 🚀 Local Development for Event Sourcing

### **Event System Development Setup**
```bash
# Setup event sourcing development
npm install
npx playwright install

# Event-specific environment variables
cp .env.events.example .env.local
# Configure event system endpoints:
NEXT_PUBLIC_EVENT_API_URL=http://localhost:8000/events
NEXT_PUBLIC_EVENT_WS_URL=ws://localhost:8000/events
NEXT_PUBLIC_SAGA_API_URL=http://localhost:8008
EVENT_STORE_CONNECTION=postgresql://localhost:5432/events
```

### **Event Development Workflow**
```bash
# 1. Start event sourcing backend services
docker-compose -f docker-compose.events.yml up -d

# 2. Start event sourcing UI
npm run dev:events             # Starts on http://localhost:3003

# 3. Run event system tests
npm run test:event-flows       # Event workflow tests
npm run test:saga-integration  # SAGA system integration tests
npm run test:projections       # Projection consistency tests

# 4. Visual regression for event UI
npm run test:visual:events     # Event interface visual tests
```

## 📈 Event Analytics and Monitoring

### **Event Analytics Features**
- **Event Volume Analysis:** Event throughput and patterns over time
- **Processing Latency:** Event processing time distribution analysis
- **Error Pattern Analysis:** Event failure pattern identification
- **Resource Correlation:** Event processing vs. resource utilization

### **Real-Time Monitoring**
- **Live Event Streams:** Real-time event flow visualization
- **SAGA Progress Tracking:** Live SAGA transaction monitoring
- **Projection Lag Monitoring:** Real-time projection consistency tracking
- **System Health Indicators:** Live system status and alerts

## 🔍 Event Debugging and Troubleshooting

### **Debug Tools**
```bash
# Event system debugging
npm run debug:events           # Interactive event debugging
npm run trace:event-flows      # Event flow tracing and analysis
npm run validate:projections   # Projection consistency validation
npm run analyze:performance    # Event processing performance analysis
```

### **Event System Debugging Features**
- **Event Tracing:** Follow individual events through the system
- **SAGA Debugging:** Step through SAGA transaction flows
- **Projection Analysis:** Analyze projection rebuild operations
- **Performance Profiling:** Identify event processing bottlenecks

## 🎨 Advanced Visualization Features

### **Event Timeline Visualization**
- **Interactive Timeline:** Zoom, filter, and search event history
- **Causality Graphs:** Visual cause-and-effect relationships
- **Correlation Analysis:** Related event identification and grouping
- **Pattern Detection:** Automatic event pattern recognition

### **SAGA Flow Visualization**
- **State Machine Diagrams:** Visual SAGA state transitions
- **Progress Indicators:** Real-time SAGA step completion
- **Error Flow Mapping:** Compensation and rollback visualizations
- **Performance Heatmaps:** SAGA step performance analysis

## 📱 Mobile Event Monitoring

### **Mobile Event Interface**
```bash
# Mobile event monitoring testing
npm run test:mobile:events     # Mobile event monitoring
npm run test:responsive:events # Event UI responsive design
npm run test:alerts:mobile     # Mobile alert and notification testing
```

### **Mobile Event Features**
- **Critical Alerts:** High-priority event system alerts on mobile
- **System Status:** Quick event system health checks
- **Emergency Controls:** Critical event system controls from mobile
- **Performance Monitoring:** Key event metrics on mobile interface

## 🔒 Event Security and Audit

### **Event Security Features**
- **Event Audit Trails:** Complete audit logging for all events
- **Access Control:** Role-based access to sensitive events
- **Data Privacy:** Event data anonymization and privacy controls
- **Compliance Monitoring:** Event compliance with data regulations

### **Security Testing**
```bash
# Event security testing
npm run test:event-security     # Event access control testing
npm run test:audit-trails       # Event audit trail validation
npm run test:data-privacy       # Event data privacy testing
npm run test:compliance         # Event compliance validation
```

## 🚨 Current Status - Event Sourcing UI

### **✅ Working Features**
- **Event UI Framework:** Next.js event interface operational
- **Visual Components:** Event visualization components functional
- **Development Environment:** Local development setup working
- **Testing Framework:** Playwright configured for event testing

### **❌ Backend Integration Issues**
- **Event Store Connection:** Event store backend not accessible
- **SAGA Service Integration:** SAGA orchestrator service failing (port 8008)
- **WebSocket Connections:** Real-time event streams not functional
- **Event API Gateway:** Event API endpoints not properly routed

### **🔧 Critical Event System Fixes Needed**
1. **Event Store Backend:** Deploy and configure event store database
2. **SAGA Service Repair:** Fix SAGA orchestrator restart loop (port 8008)
3. **WebSocket Integration:** Enable real-time event streaming
4. **API Gateway Configuration:** Configure event system API routes

## 🎯 Event System Testing Strategy

### **Test Coverage Areas**
- **Event Flow Testing:** End-to-end event processing workflows
- **SAGA Transaction Testing:** Complex distributed transaction scenarios
- **Projection Consistency:** Event sourcing consistency validation
- **Performance Testing:** Event processing performance and scalability
- **Error Recovery:** Event system failure and recovery scenarios

### **Testing Priorities**
1. **P0:** Core event streaming and processing
2. **P1:** SAGA orchestration and distributed transactions
3. **P2:** Event projections and read models
4. **P3:** Advanced debugging and analysis tools

## 📊 Performance and Scalability

### **Event Performance Testing**
```bash
# Event system performance testing
npm run test:performance:events # Event processing performance
npm run test:throughput         # Event throughput testing
npm run test:latency           # Event processing latency testing
npm run test:scalability       # Event system scalability testing
```

### **Performance Considerations**
- **High Event Volume:** Support for thousands of events per second
- **Real-time Processing:** Low-latency event processing and visualization
- **Memory Management:** Efficient memory usage for event streaming
- **Network Optimization:** Optimized WebSocket event transmission

## 📞 Event System Support

### **Debug Event Issues**
```bash
# Event system debugging commands
npm run debug:event-flows      # Interactive event flow debugging
npm run logs:event-store       # Event store log analysis
npm run health:event-system    # Event system health validation
npm run repair:projections     # Automated projection repair
```

### **Common Event System Issues**
- **Event Store Connectivity:** Check event store database connection
- **SAGA Service Failures:** Monitor SAGA orchestrator service health
- **Projection Lag:** Monitor and resolve projection consistency issues
- **WebSocket Disconnections:** Handle real-time connection failures

---

**Status:** Event sourcing UI framework ready, event store and SAGA backend integration required.  
**Priority:** Deploy event store backend and fix SAGA orchestrator service.  
**Testing:** Advanced event flow testing capabilities available with Playwright.