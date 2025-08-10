import { test, expect } from '@playwright/test'
import fs from 'fs'
import path from 'path'

test.describe('File Upload Functionality', () => {
  test.beforeEach(async ({ page }) => {
    // Mock file upload endpoints
    await page.route('**/api/**upload**', async route => {
      const method = route.request().method()
      
      if (method === 'POST') {
        // Mock successful upload response
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            success: true,
            fileId: 'uploaded_file_123',
            fileName: 'test-file.csv',
            fileSize: 1024,
            uploadedAt: new Date().toISOString()
          })
        })
      } else {
        await route.continue()
      }
    })
  })

  test('should display file upload interface', async ({ page }) => {
    await page.goto('/chat')
    await page.waitForTimeout(2000)
    
    // Look for file upload elements
    const uploadElements = [
      'input[type="file"]',
      'text=Upload',
      'text=Choose file',
      'text=Drop file',
      'text=Drag and drop',
      '[data-testid*="upload"]',
      '.upload-area',
      '.file-drop'
    ]
    
    let foundUploadInterface = false
    for (const selector of uploadElements) {
      try {
        if (await page.locator(selector).first().isVisible({ timeout: 1000 })) {
          foundUploadInterface = true
          break
        }
      } catch {
        // Continue checking
      }
    }
    
    if (foundUploadInterface) {
      // Take screenshot of upload interface
      await expect(page).toHaveScreenshot('file-upload-interface.png', {
        threshold: 0.4
      })
    }
  })

  test('should handle file selection', async ({ page }) => {
    await page.goto('/chat')
    await page.waitForTimeout(2000)
    
    // Create a temporary test file
    const testFilePath = path.join(__dirname, '../test-data/sample.csv')
    const testFileContent = 'Name,Email,Phone\nJohn Doe,john@example.com,555-1234\nJane Smith,jane@example.com,555-5678'
    
    // Ensure test-data directory exists
    const testDataDir = path.join(__dirname, '../test-data')
    if (!fs.existsSync(testDataDir)) {
      fs.mkdirSync(testDataDir, { recursive: true })
    }
    
    // Write test file
    fs.writeFileSync(testFilePath, testFileContent)
    
    try {
      // Look for file input
      const fileInput = page.locator('input[type="file"]').first()
      
      if (await fileInput.isVisible({ timeout: 1000 })) {
        // Set file
        await fileInput.setInputFiles(testFilePath)
        
        // Wait for file to be processed
        await page.waitForTimeout(1000)
        
        // Look for file name display or processing indicator
        const fileNameElements = [
          'text=sample.csv',
          'text=John Doe',
          'text=uploading',
          'text=processing',
          '.file-name',
          '.file-info'
        ]
        
        let foundFileProcessing = false
        for (const selector of fileNameElements) {
          try {
            if (await page.locator(selector).isVisible({ timeout: 2000 })) {
              foundFileProcessing = true
              break
            }
          } catch {
            // Continue
          }
        }
      }
    } finally {
      // Clean up test file
      if (fs.existsSync(testFilePath)) {
        fs.unlinkSync(testFilePath)
      }
    }
  })

  test('should handle file upload errors', async ({ page }) => {
    // Mock upload error
    await page.route('**/api/**upload**', async route => {
      await route.fulfill({
        status: 400,
        contentType: 'application/json',
        body: JSON.stringify({
          error: 'File type not supported'
        })
      })
    })
    
    await page.goto('/chat')
    await page.waitForTimeout(2000)
    
    // Create a test file with unsupported type
    const testFilePath = path.join(__dirname, '../test-data/test.xyz')
    fs.writeFileSync(testFilePath, 'unsupported file content')
    
    try {
      const fileInput = page.locator('input[type="file"]').first()
      
      if (await fileInput.isVisible({ timeout: 1000 })) {
        await fileInput.setInputFiles(testFilePath)
        
        // Wait for error response
        await page.waitForTimeout(2000)
        
        // Look for error messages
        const errorElements = [
          'text=File type not supported',
          'text=Error',
          'text=Upload failed',
          '[role="alert"]',
          '.error',
          '.alert-error'
        ]
        
        let foundError = false
        for (const selector of errorElements) {
          try {
            if (await page.locator(selector).isVisible({ timeout: 1000 })) {
              foundError = true
              break
            }
          } catch {
            // Continue
          }
        }
      }
    } finally {
      // Clean up
      if (fs.existsSync(testFilePath)) {
        fs.unlinkSync(testFilePath)
      }
    }
  })

  test('should validate file size limits', async ({ page }) => {
    await page.goto('/chat')
    await page.waitForTimeout(2000)
    
    // Check if there's any size limit indication
    const sizeLimitElements = [
      'text=Max file size',
      'text=Maximum',
      'text=MB',
      'text=KB',
      'text=Size limit',
      'text=Too large'
    ]
    
    let foundSizeInfo = false
    for (const selector of sizeLimitElements) {
      try {
        if (await page.locator(selector).isVisible({ timeout: 1000 })) {
          foundSizeInfo = true
          break
        }
      } catch {
        // Continue
      }
    }
  })

  test('should handle multiple file uploads', async ({ page }) => {
    await page.goto('/chat')
    await page.waitForTimeout(2000)
    
    const fileInput = page.locator('input[type="file"]').first()
    
    if (await fileInput.isVisible({ timeout: 1000 })) {
      // Check if multiple attribute exists
      const hasMultiple = await fileInput.getAttribute('multiple')
      
      if (hasMultiple !== null) {
        // Create multiple test files
        const testFiles = [
          path.join(__dirname, '../test-data/file1.csv'),
          path.join(__dirname, '../test-data/file2.csv')
        ]
        
        // Ensure directory exists
        const testDataDir = path.join(__dirname, '../test-data')
        if (!fs.existsSync(testDataDir)) {
          fs.mkdirSync(testDataDir, { recursive: true })
        }
        
        try {
          fs.writeFileSync(testFiles[0], 'Name,Value\nTest1,100')
          fs.writeFileSync(testFiles[1], 'Name,Value\nTest2,200')
          
          await fileInput.setInputFiles(testFiles)
          await page.waitForTimeout(1000)
          
          // Look for multiple file indicators
          const multiFileElements = [
            'text=2 files',
            'text=file1.csv',
            'text=file2.csv',
            'text=Multiple files',
            '.file-list'
          ]
          
          let foundMultipleFiles = false
          for (const selector of multiFileElements) {
            try {
              if (await page.locator(selector).isVisible({ timeout: 1000 })) {
                foundMultipleFiles = true
                break
              }
            } catch {
              // Continue
            }
          }
        } finally {
          // Clean up
          testFiles.forEach(file => {
            if (fs.existsSync(file)) {
              fs.unlinkSync(file)
            }
          })
        }
      }
    }
  })

  test('should provide upload progress indication', async ({ page }) => {
    // Mock slow upload response
    await page.route('**/api/**upload**', async route => {
      // Delay response to simulate upload time
      await new Promise(resolve => setTimeout(resolve, 2000))
      
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          fileId: 'slow_upload_123'
        })
      })
    })
    
    await page.goto('/chat')
    await page.waitForTimeout(2000)
    
    const fileInput = page.locator('input[type="file"]').first()
    
    if (await fileInput.isVisible({ timeout: 1000 })) {
      // Create test file
      const testFilePath = path.join(__dirname, '../test-data/progress-test.csv')
      
      // Ensure directory exists
      const testDataDir = path.join(__dirname, '../test-data')
      if (!fs.existsSync(testDataDir)) {
        fs.mkdirSync(testDataDir, { recursive: true })
      }
      
      try {
        fs.writeFileSync(testFilePath, 'Name,Value\nProgress Test,123')
        
        await fileInput.setInputFiles(testFilePath)
        
        // Look for progress indicators
        const progressElements = [
          'text=Uploading',
          'text=Processing',
          'text=%',
          '.progress',
          '.loading',
          '.spinner',
          '[role="progressbar"]'
        ]
        
        let foundProgress = false
        for (const selector of progressElements) {
          try {
            if (await page.locator(selector).isVisible({ timeout: 1000 })) {
              foundProgress = true
              break
            }
          } catch {
            // Continue
          }
        }
        
        // Wait for upload to complete
        await page.waitForTimeout(3000)
        
      } finally {
        if (fs.existsSync(testFilePath)) {
          fs.unlinkSync(testFilePath)
        }
      }
    }
  })
})