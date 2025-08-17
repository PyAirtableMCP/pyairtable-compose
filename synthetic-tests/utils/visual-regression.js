const fs = require('fs').promises;
const path = require('path');
const pixelmatch = require('pixelmatch');
const { PNG } = require('pngjs');

class VisualRegression {
  constructor() {
    this.baselineDir = path.join(__dirname, '../screenshots/baseline');
    this.actualDir = path.join(__dirname, '../screenshots/actual');
    this.diffDir = path.join(__dirname, '../screenshots/diff');
    this.threshold = 0.1; // 10% pixel difference threshold
  }

  /**
   * Initialize directories for visual regression testing
   */
  async initialize() {
    await fs.mkdir(this.baselineDir, { recursive: true });
    await fs.mkdir(this.actualDir, { recursive: true });
    await fs.mkdir(this.diffDir, { recursive: true });
  }

  /**
   * Capture a screenshot for visual comparison
   */
  async captureScreenshot(page, testName, selector = null, options = {}) {
    await this.initialize();
    
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const filename = `${testName}-${timestamp}.png`;
    const actualPath = path.join(this.actualDir, filename);
    
    const screenshotOptions = {
      path: actualPath,
      fullPage: options.fullPage || false,
      clip: options.clip,
      ...options
    };
    
    if (selector) {
      const element = await page.locator(selector);
      await element.screenshot(screenshotOptions);
    } else {
      await page.screenshot(screenshotOptions);
    }
    
    return {
      actualPath,
      filename,
      testName
    };
  }

  /**
   * Compare screenshot with baseline
   */
  async compareWithBaseline(actualPath, testName) {
    const baselinePath = path.join(this.baselineDir, `${testName}-baseline.png`);
    const diffPath = path.join(this.diffDir, `${testName}-diff.png`);
    
    // Check if baseline exists
    try {
      await fs.access(baselinePath);
    } catch (error) {
      // No baseline exists, copy actual as new baseline
      await fs.copyFile(actualPath, baselinePath);
      return {
        status: 'new_baseline',
        message: 'No baseline found, created new baseline',
        baselinePath,
        actualPath,
        diffPath: null,
        pixelDifference: 0,
        percentageDifference: 0
      };
    }
    
    // Load images
    const actualBuffer = await fs.readFile(actualPath);
    const baselineBuffer = await fs.readFile(baselinePath);
    
    const actualImg = PNG.sync.read(actualBuffer);
    const baselineImg = PNG.sync.read(baselineBuffer);
    
    // Check dimensions match
    if (actualImg.width !== baselineImg.width || actualImg.height !== baselineImg.height) {
      return {
        status: 'dimension_mismatch',
        message: `Image dimensions don't match. Baseline: ${baselineImg.width}x${baselineImg.height}, Actual: ${actualImg.width}x${actualImg.height}`,
        baselinePath,
        actualPath,
        diffPath: null,
        pixelDifference: null,
        percentageDifference: null
      };
    }
    
    // Create diff image
    const diff = new PNG({ width: actualImg.width, height: actualImg.height });
    
    // Compare images
    const pixelDifference = pixelmatch(
      actualImg.data,
      baselineImg.data,
      diff.data,
      actualImg.width,
      actualImg.height,
      {
        threshold: 0.1,
        alpha: 0.2,
        diffColor: [255, 0, 0],
        diffColorAlt: [255, 255, 0]
      }
    );
    
    const totalPixels = actualImg.width * actualImg.height;
    const percentageDifference = (pixelDifference / totalPixels) * 100;
    
    // Save diff image if there are differences
    if (pixelDifference > 0) {
      await fs.writeFile(diffPath, PNG.sync.write(diff));
    }
    
    const status = percentageDifference > this.threshold ? 'failed' : 'passed';
    
    return {
      status,
      message: `Visual comparison ${status}. ${pixelDifference} pixels differ (${percentageDifference.toFixed(2)}%)`,
      baselinePath,
      actualPath,
      diffPath: pixelDifference > 0 ? diffPath : null,
      pixelDifference,
      percentageDifference,
      threshold: this.threshold
    };
  }

  /**
   * Update baseline with current screenshot
   */
  async updateBaseline(actualPath, testName) {
    const baselinePath = path.join(this.baselineDir, `${testName}-baseline.png`);
    await fs.copyFile(actualPath, baselinePath);
    
    return {
      status: 'baseline_updated',
      message: 'Baseline updated successfully',
      baselinePath,
      actualPath
    };
  }

  /**
   * Generate visual regression report
   */
  async generateReport(testResults) {
    const reportPath = path.join(__dirname, '../reports/visual-regression-report.html');
    
    let html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Visual Regression Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f5f5f5; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        .test-result { border: 1px solid #ddd; margin: 10px 0; padding: 15px; border-radius: 5px; }
        .passed { border-left: 5px solid #28a745; }
        .failed { border-left: 5px solid #dc3545; }
        .new_baseline { border-left: 5px solid #007bff; }
        .dimension_mismatch { border-left: 5px solid #ffc107; }
        .image-comparison { display: flex; gap: 10px; margin-top: 10px; }
        .image-container { flex: 1; text-align: center; }
        .image-container img { max-width: 100%; border: 1px solid #ddd; }
        .stats { background: #f8f9fa; padding: 10px; border-radius: 3px; margin: 10px 0; }
        .summary { display: flex; gap: 20px; margin: 20px 0; }
        .summary-item { background: white; padding: 15px; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    </style>
</head>
<body>
    <div class="header">
        <h1>Visual Regression Test Report</h1>
        <p>Generated: ${new Date().toISOString()}</p>
        <p>Session ID: ${process.env.TEST_SESSION_ID || 'unknown'}</p>
    </div>
    
    <div class="summary">
        <div class="summary-item">
            <h3>Total Tests</h3>
            <p style="font-size: 24px; margin: 0;">${testResults.length}</p>
        </div>
        <div class="summary-item">
            <h3>Passed</h3>
            <p style="font-size: 24px; margin: 0; color: #28a745;">${testResults.filter(r => r.status === 'passed').length}</p>
        </div>
        <div class="summary-item">
            <h3>Failed</h3>
            <p style="font-size: 24px; margin: 0; color: #dc3545;">${testResults.filter(r => r.status === 'failed').length}</p>
        </div>
        <div class="summary-item">
            <h3>New Baselines</h3>
            <p style="font-size: 24px; margin: 0; color: #007bff;">${testResults.filter(r => r.status === 'new_baseline').length}</p>
        </div>
    </div>
`;

    for (const result of testResults) {
      html += `
    <div class="test-result ${result.status}">
        <h3>${result.testName}</h3>
        <p><strong>Status:</strong> ${result.status.toUpperCase()}</p>
        <p><strong>Message:</strong> ${result.message}</p>
`;

      if (result.pixelDifference !== null) {
        html += `
        <div class="stats">
            <p><strong>Pixel Difference:</strong> ${result.pixelDifference} pixels</p>
            <p><strong>Percentage Difference:</strong> ${result.percentageDifference.toFixed(2)}%</p>
            <p><strong>Threshold:</strong> ${result.threshold}%</p>
        </div>
`;
      }

      if (result.baselinePath || result.actualPath || result.diffPath) {
        html += `
        <div class="image-comparison">
`;
        
        if (result.baselinePath) {
          const baselineRelative = path.relative(path.dirname(reportPath), result.baselinePath);
          html += `
            <div class="image-container">
                <h4>Baseline</h4>
                <img src="${baselineRelative}" alt="Baseline" />
            </div>
`;
        }
        
        if (result.actualPath) {
          const actualRelative = path.relative(path.dirname(reportPath), result.actualPath);
          html += `
            <div class="image-container">
                <h4>Actual</h4>
                <img src="${actualRelative}" alt="Actual" />
            </div>
`;
        }
        
        if (result.diffPath) {
          const diffRelative = path.relative(path.dirname(reportPath), result.diffPath);
          html += `
            <div class="image-container">
                <h4>Difference</h4>
                <img src="${diffRelative}" alt="Difference" />
            </div>
`;
        }
        
        html += `
        </div>
`;
      }
      
      html += `
    </div>
`;
    }

    html += `
</body>
</html>
`;

    await fs.writeFile(reportPath, html);
    return reportPath;
  }

  /**
   * Clean up old screenshots
   */
  async cleanup(maxAge = 7) {
    const dirs = [this.actualDir, this.diffDir];
    const cutoffTime = Date.now() - (maxAge * 24 * 60 * 60 * 1000);
    
    for (const dir of dirs) {
      try {
        const files = await fs.readdir(dir);
        
        for (const file of files) {
          const filePath = path.join(dir, file);
          const stats = await fs.stat(filePath);
          
          if (stats.mtime.getTime() < cutoffTime) {
            await fs.unlink(filePath);
          }
        }
      } catch (error) {
        console.warn(`Failed to cleanup directory ${dir}:`, error.message);
      }
    }
  }
}

module.exports = VisualRegression;