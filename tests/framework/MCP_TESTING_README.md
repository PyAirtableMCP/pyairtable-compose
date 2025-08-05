# MCP Tools Comprehensive Testing Framework

This directory contains a comprehensive testing framework for MCP (Model Context Protocol) tools through the pyairtable frontend UI. The framework provides synthetic agents, API mocking, and complete test orchestration for reliable, fast, and thorough testing.

## 🎯 Overview

The MCP testing framework includes:

- **5 Comprehensive Test Scenarios** for complete MCP tool coverage
- **Synthetic UI Agents** that simulate real user interactions
- **API Mocking Framework** for deterministic and fast testing
- **Parallel Execution** with result aggregation
- **Performance Benchmarking** and detailed reporting
- **Error Handling & Retry** mechanisms
- **Screenshot Capture** for debugging
- **Integration Tests** combining all components

## 📋 Test Scenarios

### 1. **Create Metadata Table** (`create-table`)
**File**: `synthetic_agents.py` - `MCPMetadataTableAgent`

Tests complete metadata table creation workflow:
- Navigate to table creation interface
- Fill in table name: "Table_Metadata" 
- Define comprehensive schema with 13 fields
- Submit and verify creation
- Validate table structure in Airtable
- Performance: ~30 seconds expected

**Fields Created**:
- `table_name` (Primary field)
- `table_id`, `record_count`, `field_count`
- `created_date`, `last_updated`
- `description`, `primary_field`
- `field_types`, `data_quality_score`
- `usage_frequency`, `owner`, `tags`

### 2. **Populate Metadata for 35 Tables** (`populate`)
**File**: `synthetic_agents.py` - `MCPMetadataPopulationAgent`

Tests metadata population workflow:
- Get list of all tables in base
- Create additional test tables if needed
- Generate realistic metadata for each table
- Populate 35 records with comprehensive stats
- Verify data persistence and quality
- Performance: ~60 seconds expected

### 3. **Update Metadata Fields** (`update`)
**File**: `synthetic_agents.py` - `MCPMetadataUpdateAgent`

Tests bulk metadata update operations:
- Select existing metadata records
- Perform 5 different update operations:
  - Enhanced descriptions
  - Recalculated quality scores
  - Updated usage frequencies
  - Added/updated tags
  - Owner information updates
- Test selective record updates
- Verify all changes applied correctly
- Performance: ~45 seconds expected

### 4. **Add Improvements Column** (`add-column`)
**File**: `synthetic_agents.py` - `MCPColumnAdditionAgent`

Tests schema modification workflow:
- Verify existing table structure
- Add new "improvements" field (Long text type)
- Apply field to existing rows with default content
- Test field configuration options
- Validate column addition success
- Performance: ~30 seconds expected

### 5. **LLM Analysis Integration** (`llm-analysis`)
**File**: `synthetic_agents.py` - `MCPLLMAnalysisAgent`

Tests comprehensive AI analysis workflow:
- Select tables for analysis (up to 10)
- Run 5 analysis workflows:
  - Structure analysis & relationships
  - Data quality assessment
  - Performance optimization
  - Usage pattern analysis  
  - Automation recommendations
- Update improvements field with AI recommendations
- Test interactive analysis capabilities
- Validate AI response quality
- Performance: ~90 seconds expected

## 🤖 Synthetic Agents

### Base Agent (`SyntheticUIAgent`)
**File**: `ui_agents.py`

Provides core UI automation capabilities:
- Browser management (Chromium/Firefox/WebKit)
- Page interaction methods (click, fill, type, etc.)
- Screenshot capture and tracing
- Performance analysis
- Accessibility checking
- Network monitoring

### MCP-Specific Agents
Each MCP scenario has a specialized agent that extends the base functionality:

```python
# Example usage
async with MCPMetadataTableAgent(config) as agent:
    result = await agent.test_create_metadata_table()
    print(f"Test result: {result.status}")
```

## 🎭 API Mocking Framework

**File**: `mcp_mocking.py`

### Features
- **Request Interception**: Playwright-based route interception
- **Dynamic Responses**: Context-aware mock responses
- **Response Recording**: Record real interactions for replay
- **Validation**: Mock response quality validation
- **Metrics**: Track mock effectiveness and usage

### Mocking Components

#### Airtable API Mocks (`AirtableMockResponses`)
```python
# Pre-defined responses for common operations
- get_base_schema() - Base and table structure
- create_table_success() - Table creation responses
- add_field_success() - Field addition responses  
- create_records_success() - Record creation
- update_records_success() - Record updates
- list_records() - Record listing with pagination
```

#### LLM Service Mocks (`LLMMockResponses`)
```python
# AI response simulation
- table_creation_response() - Table creation confirmations
- table_analysis_response() - Comprehensive analysis results
- field_addition_response() - Field addition confirmations
- bulk_update_response() - Bulk operation results
- metadata_population_response() - Population confirmations
```

### Usage Examples

```python
# Enable mocking for all APIs
async with MCPMockContextManager(page, 
                                enable_airtable=True, 
                                enable_llm=True) as mock_framework:
    # Run tests with mocked responses
    result = await agent.test_create_metadata_table()

# Custom mock rules
mock_framework.add_mock_rule(MockRule(
    pattern="https://api.airtable.com/v0/*/Table_Metadata",
    method="POST",
    response=MockResponse(status=200, body={"success": True}, delay=2.0)
))
```

## 🔄 Test Orchestration

### Master Orchestrator (`MCPTestOrchestrator`)
**File**: `synthetic_agents.py`

Coordinates all test execution:
- **Parallel Execution**: Run multiple agents simultaneously
- **Result Aggregation**: Combine results from all agents
- **Performance Metrics**: Track timing and success rates
- **Error Handling**: Graceful failure management
- **Report Generation**: HTML and JSON reports

### Integration Test Suite (`MCPIntegrationTestSuite`)
**File**: `mcp_integration_tests.py`

Comprehensive integration testing:
- **Mock Integration**: Combines agents with mocking framework
- **Cross-Scenario Testing**: Tests spanning multiple scenarios
- **Validation Tests**: Mock response quality validation
- **Concurrent Operations**: Race condition testing
- **Complete Workflow**: End-to-end scenario chains

## 🚀 Quick Start

### 1. Installation
```bash
cd /Users/kg/IdeaProjects/pyairtable-compose/tests/framework
pip install -r requirements.txt
playwright install chromium
```

### 2. Configuration
Set environment variables:
```bash
export AIRTABLE_TOKEN="your_token_here"
export AIRTABLE_BASE="appVLUAubH5cFWhMV"
export GEMINI_API_KEY="your_gemini_key_here"
export TEST_ENVIRONMENT="local"
```

### 3. Run Tests

#### Individual Scenarios
```bash
# Create metadata table with mocking
./run_mcp_tests.py --scenario create-table --mocking --verbose

# Populate metadata without mocking (real API)
./run_mcp_tests.py --scenario populate --no-mocking --headless

# All scenarios in parallel
./run_mcp_tests.py --scenario all --parallel --screenshots
```

#### Integration Tests  
```bash
# Quick integration test with mocking
./run_mcp_tests.py --integration quick --parallel

# Comprehensive test suite
./run_mcp_tests.py --integration comprehensive

# Real API integration test
./run_mcp_tests.py --integration real-api --no-parallel
```

#### Health Checks
```bash
# System health check
./run_mcp_tests.py --health-check --verbose
```

## 📊 Test Execution Options

### Test Runner (`run_mcp_tests.py`)

**Core Options:**
- `--scenario {create-table,populate,update,add-column,llm-analysis,all}` - Specific scenario
- `--integration {quick,comprehensive,real-api}` - Integration test type
- `--health-check` - System health validation

**Configuration:**
- `--mocking` / `--no-mocking` - API mocking control
- `--parallel` / `--no-parallel` - Parallel execution
- `--headless` / `--no-headless` - Browser visibility
- `--browser {chromium,firefox,webkit}` - Browser selection
- `--environment {local,minikube,docker-compose}` - Test environment

**Output & Debugging:**
- `--verbose` / `--debug` - Logging levels
- `--screenshots` - Screenshot capture
- `--traces` - Browser trace recording
- `--timeout SECONDS` - Test timeout
- `--output FILE` - Results output file

## 📈 Performance Benchmarks

### Expected Execution Times

| Scenario | With Mocking | Without Mocking | Parallel Speedup |
|----------|-------------|-----------------|------------------|
| Create Table | ~10s | ~30s | N/A |
| Populate 35 Tables | ~25s | ~60s | N/A |
| Update Metadata | ~15s | ~45s | N/A |
| Add Column | ~8s | ~30s | N/A |
| LLM Analysis | ~30s | ~90s | N/A |
| **All Scenarios** | **~45s** | **~180s** | **~3x faster** |

### Key Metrics Tracked
- **Response Times**: Individual operation timing
- **Success Rates**: Pass/fail ratios
- **Mock Effectiveness**: API call interception rates
- **Resource Usage**: Memory and CPU utilization
- **Error Recovery**: Retry success rates

## 🔍 Debugging & Troubleshooting

### Debug Mode
```bash
./run_mcp_tests.py --scenario create-table --debug --no-headless --traces
```

### Common Issues

**1. Browser Launch Failures**
```bash
# Install browsers
playwright install chromium firefox webkit

# Check browser availability
playwright install --help
```

**2. API Authentication**
```bash
# Verify credentials
export AIRTABLE_TOKEN="your_token"
curl -H "Authorization: Bearer $AIRTABLE_TOKEN" \
     "https://api.airtable.com/v0/meta/bases"
```

**3. Network Timeouts**
```bash
# Increase timeout for slow networks
./run_mcp_tests.py --scenario populate --timeout 600
```

**4. Mock Framework Issues**
```bash
# Disable mocking to test real APIs
./run_mcp_tests.py --scenario create-table --no-mocking --debug
```

### Artifacts Generated

**Screenshots**: `test-results/ui-agents/{session_id}/`
- Captured automatically on failures
- Manual capture at key test points
- Full-page screenshots with timestamps

**Traces**: `test-results/ui-agents/{session_id}/trace.zip`
- Complete browser interaction recording
- Network request/response details
- JavaScript execution timeline

**Reports**: `test-results/reports/`
- HTML reports with interactive results
- JSON reports for programmatic analysis
- Performance metrics and charts

**Logs**: `mcp_test_run_{timestamp}.log`
- Detailed execution logs
- Error traces and debugging info
- Performance timing details

## 🏗️ Architecture

### Framework Structure
```
tests/framework/
├── synthetic_agents.py      # Main agent implementations
├── mcp_mocking.py          # API mocking framework  
├── mcp_integration_tests.py # Integration test suite
├── run_mcp_tests.py        # Executable test runner
├── ui_agents.py            # Base UI agent classes
├── test_config.py          # Configuration management
├── test_orchestrator.py    # Test execution orchestration
├── test_reporter.py        # Results reporting
├── requirements.txt        # Python dependencies
└── MCP_TESTING_README.md   # This documentation
```

### Key Design Patterns

**1. Agent Pattern**: Specialized agents for different test scenarios
**2. Context Managers**: Resource management for browsers and mocks
**3. Builder Pattern**: Flexible test configuration construction
**4. Observer Pattern**: Event-driven test execution monitoring
**5. Strategy Pattern**: Pluggable execution strategies (parallel/sequential)

### Extension Guide

**Adding New Scenarios:**
1. Create new agent class extending `SyntheticUIAgent`
2. Implement scenario-specific test methods
3. Add mock responses in `mcp_mocking.py`
4. Update test orchestrator to include new scenario
5. Add CLI command in `run_mcp_tests.py`

**Custom Mock Responses:**
```python
# Add custom mock in mcp_mocking.py
@staticmethod
def custom_operation_response() -> MockResponse:
    return MockResponse(
        status=200,
        body={"result": "custom response"},
        delay=1.0
    )
```

**Configuration Extensions:**
```python
# Extend TestFrameworkConfig in test_config.py
@dataclass 
class CustomConfig:
    custom_setting: str = "default_value"
```

## 🎛️ Configuration

### Environment Variables
```bash
# Required
AIRTABLE_TOKEN=your_airtable_token
AIRTABLE_BASE=your_base_id
GEMINI_API_KEY=your_gemini_key

# Optional
TEST_ENVIRONMENT=local
BROWSER_TYPE=chromium  
HEADLESS=true
TEST_PARALLEL=true
MAX_WORKERS=4
TEST_TIMEOUT=300
```

### Configuration File (`e2e_test_config.json`)
```json
{
  "environment": "local",
  "test_level": "integration", 
  "parallel_execution": true,
  "browser": {
    "browser_type": "chromium",
    "headless": true,
    "viewport_width": 1920,
    "viewport_height": 1080,
    "screenshot_on_failure": true
  },
  "airtable": {
    "base_id": "appVLUAubH5cFWhMV",
    "rate_limit_per_second": 5
  },
  "generate_html_report": true,
  "save_screenshots": true
}
```

## 📋 Test Coverage

### Functional Coverage
- ✅ **Table Creation**: Schema definition and validation
- ✅ **Record Operations**: CRUD operations with bulk support
- ✅ **Field Management**: Adding, updating, configuring fields
- ✅ **Data Population**: Large-scale data insertion
- ✅ **LLM Integration**: AI analysis and recommendations
- ✅ **UI Interactions**: Complete user workflow simulation
- ✅ **Error Handling**: Failure scenarios and recovery
- ✅ **Performance**: Timing and resource usage

### Technical Coverage
- ✅ **API Mocking**: Request/response interception
- ✅ **Browser Automation**: Multi-browser support
- ✅ **Parallel Execution**: Concurrent test execution
- ✅ **Result Aggregation**: Multi-test result compilation
- ✅ **Report Generation**: HTML and JSON outputs
- ✅ **Screenshot Capture**: Visual debugging support
- ✅ **Network Monitoring**: Request/response tracking
- ✅ **Configuration Management**: Flexible test setup

## 🤝 Contributing

### Adding New Test Scenarios
1. Create new agent class in `synthetic_agents.py`
2. Implement test methods following existing patterns
3. Add corresponding mock responses
4. Update orchestrator and CLI runner
5. Write documentation and examples

### Improving Mock Framework
1. Add new response generators in `mcp_mocking.py`
2. Implement request pattern matching
3. Add validation logic for response quality
4. Update integration tests

### Extending Reporting
1. Add new metrics in `test_reporter.py`
2. Implement additional output formats
3. Create visualization components
4. Update result aggregation logic

## 📞 Support

### Getting Help
1. **Documentation**: Start with this README
2. **Code Examples**: Check existing test implementations
3. **Debug Mode**: Use `--debug` flag for detailed logging
4. **Issue Tracking**: Document problems with full context

### Common Solutions
- **Slow Tests**: Enable mocking with `--mocking`
- **Timeouts**: Increase timeout with `--timeout 600`
- **Browser Issues**: Try different browser with `--browser firefox`
- **Network Problems**: Check credentials and connectivity
- **Mock Problems**: Disable mocking temporarily for debugging

---

## 🎉 Success Criteria

A successful test run should show:
- ✅ All 5 scenarios complete successfully
- ✅ Performance within expected ranges
- ✅ Comprehensive validation passes
- ✅ Screenshots captured for debugging
- ✅ Detailed reports generated
- ✅ No critical errors or timeouts

The framework is designed to be:
- **Reliable**: Consistent results across runs
- **Fast**: Quick feedback through mocking
- **Comprehensive**: Complete scenario coverage
- **Maintainable**: Clear structure and documentation
- **Extensible**: Easy to add new scenarios
- **Observable**: Rich reporting and debugging

Ready to test your MCP tools comprehensively! 🚀