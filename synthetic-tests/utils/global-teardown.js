const fs = require('fs').promises;
const path = require('path');

async function globalTeardown() {
  console.log('🧹 Starting global teardown...');
  
  try {
    // Execute any registered cleanup functions
    if (global.testDataCleanup && global.testDataCleanup.length > 0) {
      console.log(`🗑️  Running ${global.testDataCleanup.length} cleanup functions...`);
      
      for (const cleanupFn of global.testDataCleanup) {
        try {
          await cleanupFn();
        } catch (error) {
          console.warn('⚠️  Cleanup function failed:', error.message);
        }
      }
    }
    
    // Save final metrics
    if (global.testMetrics) {
      await saveFinalMetrics();
    }
    
    // Generate test summary
    await generateTestSummary();
    
    console.log('✅ Global teardown completed');
    
  } catch (error) {
    console.error('❌ Global teardown failed:', error);
  }
}

async function saveFinalMetrics() {
  try {
    const metricsDir = path.join(__dirname, '../reports');
    await fs.mkdir(metricsDir, { recursive: true });
    
    const finalMetrics = {
      ...global.testMetrics,
      endTime: Date.now(),
      duration: Date.now() - global.testMetrics.startTime
    };
    
    const metricsFile = path.join(metricsDir, `metrics-${process.env.TEST_SESSION_ID}.json`);
    await fs.writeFile(metricsFile, JSON.stringify(finalMetrics, null, 2));
    
    console.log(`📊 Final metrics saved to: ${metricsFile}`);
    
  } catch (error) {
    console.warn('⚠️  Failed to save final metrics:', error.message);
  }
}

async function generateTestSummary() {
  try {
    const reportsDir = path.join(__dirname, '../reports');
    const summaryFile = path.join(reportsDir, `summary-${process.env.TEST_SESSION_ID}.md`);
    
    const summary = `# PyAirtable Synthetic Test Summary

## Test Session Information
- **Session ID**: ${process.env.TEST_SESSION_ID}
- **Environment**: ${process.env.TEST_ENV || 'local'}
- **Start Time**: ${new Date(global.testMetrics?.startTime || Date.now()).toISOString()}
- **End Time**: ${new Date().toISOString()}
- **Duration**: ${Math.round((Date.now() - (global.testMetrics?.startTime || Date.now())) / 1000)}s

## Test Results
Test results can be found in the following locations:
- **HTML Report**: \`reports/html-report/index.html\`
- **JSON Results**: \`reports/test-results.json\`
- **JUnit XML**: \`reports/test-results.xml\`
- **Screenshots**: \`screenshots/\`
- **Metrics**: \`reports/metrics-${process.env.TEST_SESSION_ID}.json\`

## Quick Links
- [Open HTML Report](./html-report/index.html)
- [View Screenshots](../screenshots/)

## Notes
This summary was generated automatically by the PyAirtable Synthetic Testing System.
For detailed analysis, refer to the HTML report and captured screenshots.
`;

    await fs.writeFile(summaryFile, summary);
    console.log(`📝 Test summary generated: ${summaryFile}`);
    
  } catch (error) {
    console.warn('⚠️  Failed to generate test summary:', error.message);
  }
}

module.exports = globalTeardown;