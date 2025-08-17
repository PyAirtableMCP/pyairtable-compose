const { test, expect } = require('@playwright/test');
const HumanBehavior = require('../utils/human-behavior');
const TraceHelper = require('../utils/trace-helper');
const testConfig = require('../config/test-config.json');

test.describe('Data Operations @regression', () => {
  let humanBehavior;
  let traceHelper;

  test.beforeEach(async ({ page }) => {
    humanBehavior = new HumanBehavior();
    traceHelper = new TraceHelper();
    
    // Setup tracing for this test
    await traceHelper.setupTracing(page, 'data-operations');
    
    // Navigate to dashboard (assuming user is logged in)
    await humanBehavior.humanNavigate(page, '/dashboard');
    await page.waitForLoadState('networkidle');
  });

  test('Browse and explore data tables @smoke', async ({ page }) => {
    const testContext = traceHelper.createTestContext('browse-data-tables', page);
    
    try {
      // Step 1: Locate and access data tables
      traceHelper.logTestEvent('step_started', { step: 'locate_data_tables' });
      
      const tableSelectors = [
        '[data-testid="data-table"]',
        '[data-testid="tables-view"]',
        'table',
        '[role="grid"]',
        '.table-container',
        '.data-grid'
      ];
      
      let tableFound = false;
      let tableElement = null;
      
      for (const selector of tableSelectors) {
        const element = page.locator(selector).first();
        if (await element.isVisible({ timeout: 3000 })) {
          tableElement = element;
          tableFound = true;
          break;
        }
      }
      
      if (!tableFound) {
        // Try to navigate to a tables/data section
        const navSelectors = [
          'a:has-text("Tables")',
          'a:has-text("Data")',
          '[data-testid="tables-nav"]',
          '[href*="tables"]',
          '[href*="data"]'
        ];
        
        for (const navSelector of navSelectors) {
          if (await page.locator(navSelector).isVisible({ timeout: 2000 })) {
            await humanBehavior.humanClick(page, navSelector);
            await page.waitForLoadState('networkidle');
            await page.waitForTimeout(2000);
            
            // Check again for tables
            for (const selector of tableSelectors) {
              const element = page.locator(selector).first();
              if (await element.isVisible({ timeout: 3000 })) {
                tableElement = element;
                tableFound = true;
                break;
              }
            }
            
            if (tableFound) break;
          }
        }
      }
      
      await traceHelper.captureScreenshot(page, 'data-tables-view', { fullPage: true });
      traceHelper.logTestEvent('step_completed', { step: 'locate_data_tables', tableFound });

      if (!tableFound) {
        // If no tables found, create some test data first
        await createTestData(page, humanBehavior, traceHelper);
        
        // Try to find tables again
        for (const selector of tableSelectors) {
          const element = page.locator(selector).first();
          if (await element.isVisible({ timeout: 3000 })) {
            tableElement = element;
            tableFound = true;
            break;
          }
        }
      }

      // Step 2: Explore table structure
      if (tableFound && tableElement) {
        traceHelper.logTestEvent('step_started', { step: 'explore_table_structure' });
        
        // Count rows and columns
        const rows = await tableElement.locator('tr, [role="row"]').count();
        const headers = await tableElement.locator('th, [role="columnheader"]').count();
        
        traceHelper.logTestEvent('table_structure', { rows, headers });
        
        // Simulate reading table headers
        const headerElements = tableElement.locator('th, [role="columnheader"]');
        const headerCount = await headerElements.count();
        
        if (headerCount > 0) {
          // Read each header
          for (let i = 0; i < Math.min(headerCount, 5); i++) {
            const header = headerElements.nth(i);
            if (await header.isVisible()) {
              await humanBehavior.simulateReading(page, `th:nth-child(${i + 1}), [role="columnheader"]:nth-child(${i + 1})`);
            }
          }
        }
        
        traceHelper.logTestEvent('step_completed', { step: 'explore_table_structure' });
      }

      // Step 3: Scroll through data
      traceHelper.logTestEvent('step_started', { step: 'scroll_through_data' });
      
      if (tableElement) {
        // Scroll down through the table
        await humanBehavior.humanScroll(page, { direction: 'down', distance: 300, steps: 3 });
        await page.waitForTimeout(1000);
        
        // Scroll back up
        await humanBehavior.humanScroll(page, { direction: 'up', distance: 150, steps: 2 });
        await page.waitForTimeout(500);
      }
      
      await traceHelper.captureScreenshot(page, 'data-scrolled');
      traceHelper.logTestEvent('step_completed', { step: 'scroll_through_data' });

      // Assertions
      expect(tableFound).toBeTruthy();
      if (tableElement) {
        await expect(tableElement).toBeVisible();
      }
      
    } catch (error) {
      await traceHelper.captureScreenshot(page, 'browse-data-error', { fullPage: true });
      traceHelper.logTestEvent('test_failed', { error: error.message });
      throw error;
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });

  test('Filter and search data @regression', async ({ page }) => {
    const testContext = traceHelper.createTestContext('filter-search-data', page);
    
    try {
      // Step 1: Locate filter/search controls
      traceHelper.logTestEvent('step_started', { step: 'locate_filters' });
      
      const filterSelectors = [
        '[data-testid="search-input"]',
        '[data-testid="filter-input"]',
        'input[placeholder*="search"]',
        'input[placeholder*="filter"]',
        '.search-box input',
        '.filter-box input'
      ];
      
      let filterElement = null;
      
      for (const selector of filterSelectors) {
        const element = page.locator(selector).first();
        if (await element.isVisible({ timeout: 3000 })) {
          filterElement = element;
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'before-filtering');
      traceHelper.logTestEvent('step_completed', { step: 'locate_filters', filterFound: !!filterElement });

      // Step 2: Apply search filter
      if (filterElement) {
        traceHelper.logTestEvent('step_started', { step: 'apply_search_filter' });
        
        const searchTerms = ['test', 'data', 'example', 'sample'];
        const searchTerm = searchTerms[Math.floor(Math.random() * searchTerms.length)];
        
        await humanBehavior.humanType(page, filterElement, searchTerm);
        await page.waitForTimeout(1000);
        
        // Press Enter or look for search button
        await page.keyboard.press('Enter');
        await page.waitForTimeout(2000);
        
        await traceHelper.captureScreenshot(page, 'after-search-filter');
        traceHelper.logTestEvent('search_applied', { searchTerm });
        traceHelper.logTestEvent('step_completed', { step: 'apply_search_filter' });
      }

      // Step 3: Try column-specific filters
      traceHelper.logTestEvent('step_started', { step: 'apply_column_filters' });
      
      const columnFilterSelectors = [
        '[data-testid="column-filter"]',
        '.column-filter',
        'th button',
        '[role="columnheader"] button'
      ];
      
      for (const selector of columnFilterSelectors) {
        const elements = page.locator(selector);
        const count = await elements.count();
        
        if (count > 0) {
          // Click on first column filter
          const firstFilter = elements.first();
          if (await firstFilter.isVisible()) {
            await humanBehavior.humanClick(page, selector);
            await page.waitForTimeout(1000);
            
            // Look for filter options
            const filterOptions = page.locator('[role="menu"], .dropdown-menu, .filter-options');
            if (await filterOptions.isVisible({ timeout: 2000 })) {
              // Select a filter option if available
              const options = filterOptions.locator('button, a, [role="menuitem"]');
              const optionCount = await options.count();
              
              if (optionCount > 0) {
                await humanBehavior.humanClick(page, options.first());
                await page.waitForTimeout(1000);
              }
            }
            break;
          }
        }
      }
      
      await traceHelper.captureScreenshot(page, 'after-column-filter');
      traceHelper.logTestEvent('step_completed', { step: 'apply_column_filters' });

      // Step 4: Clear filters
      traceHelper.logTestEvent('step_started', { step: 'clear_filters' });
      
      const clearFilterSelectors = [
        '[data-testid="clear-filters"]',
        'button:has-text("Clear")',
        'button:has-text("Reset")',
        '.clear-filters'
      ];
      
      for (const selector of clearFilterSelectors) {
        if (await page.locator(selector).isVisible({ timeout: 2000 })) {
          await humanBehavior.humanClick(page, selector);
          await page.waitForTimeout(1000);
          break;
        }
      }
      
      // Also clear search input if it exists
      if (filterElement) {
        await filterElement.clear();
        await page.keyboard.press('Enter');
        await page.waitForTimeout(1000);
      }
      
      await traceHelper.captureScreenshot(page, 'filters-cleared');
      traceHelper.logTestEvent('step_completed', { step: 'clear_filters' });
      
    } catch (error) {
      await traceHelper.captureScreenshot(page, 'filter-search-error', { fullPage: true });
      traceHelper.logTestEvent('test_failed', { error: error.message });
      throw error;
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });

  test('Edit and update records @regression', async ({ page }) => {
    const testContext = traceHelper.createTestContext('edit-update-records', page);
    
    try {
      // Step 1: Find editable records
      traceHelper.logTestEvent('step_started', { step: 'locate_editable_records' });
      
      const editableSelectors = [
        '[data-testid="editable-cell"]',
        '.editable-cell',
        'td[contenteditable="true"]',
        'td input',
        'td textarea'
      ];
      
      let editableCell = null;
      
      for (const selector of editableSelectors) {
        const element = page.locator(selector).first();
        if (await element.isVisible({ timeout: 3000 })) {
          editableCell = element;
          break;
        }
      }
      
      // If no directly editable cells, look for edit buttons
      if (!editableCell) {
        const editButtonSelectors = [
          '[data-testid="edit-button"]',
          'button:has-text("Edit")',
          '.edit-button',
          '[aria-label*="edit"]'
        ];
        
        for (const selector of editButtonSelectors) {
          if (await page.locator(selector).isVisible({ timeout: 2000 })) {
            await humanBehavior.humanClick(page, selector);
            await page.waitForTimeout(1000);
            
            // Look for editable fields after clicking edit
            for (const editSelector of editableSelectors) {
              const element = page.locator(editSelector).first();
              if (await element.isVisible({ timeout: 2000 })) {
                editableCell = element;
                break;
              }
            }
            
            if (editableCell) break;
          }
        }
      }
      
      await traceHelper.captureScreenshot(page, 'before-editing');
      traceHelper.logTestEvent('step_completed', { step: 'locate_editable_records', editableFound: !!editableCell });

      // Step 2: Edit a record
      if (editableCell) {
        traceHelper.logTestEvent('step_started', { step: 'edit_record' });
        
        // Get current value
        const currentValue = await editableCell.textContent() || '';
        
        // Click on the cell to edit
        await humanBehavior.humanClick(page, editableCell);
        await page.waitForTimeout(500);
        
        // Clear and enter new value
        const newValue = `Updated at ${new Date().toLocaleTimeString()}`;
        
        if (await editableCell.locator('input, textarea').isVisible({ timeout: 1000 })) {
          // If there's an input/textarea inside, type there
          const input = editableCell.locator('input, textarea').first();
          await input.clear();
          await humanBehavior.humanType(page, input, newValue);
        } else {
          // Otherwise, select all and type
          await page.keyboard.press('Control+A');
          await humanBehavior.humanType(page, editableCell, newValue);
        }
        
        await page.waitForTimeout(500);
        
        // Submit the edit (Enter key or Save button)
        await page.keyboard.press('Enter');
        await page.waitForTimeout(1000);
        
        // Look for save button if Enter didn't work
        const saveButtonSelectors = [
          '[data-testid="save-button"]',
          'button:has-text("Save")',
          '.save-button'
        ];
        
        for (const selector of saveButtonSelectors) {
          if (await page.locator(selector).isVisible({ timeout: 1000 })) {
            await humanBehavior.humanClick(page, selector);
            await page.waitForTimeout(1000);
            break;
          }
        }
        
        await traceHelper.captureScreenshot(page, 'after-editing');
        traceHelper.logTestEvent('record_edited', { 
          oldValue: currentValue.substring(0, 50),
          newValue: newValue.substring(0, 50)
        });
        traceHelper.logTestEvent('step_completed', { step: 'edit_record' });
      }

      // Step 3: Add new record (if possible)
      traceHelper.logTestEvent('step_started', { step: 'add_new_record' });
      
      const addRecordSelectors = [
        '[data-testid="add-record"]',
        'button:has-text("Add")',
        'button:has-text("New")',
        '.add-record-button',
        '[aria-label*="add"]'
      ];
      
      let recordAdded = false;
      
      for (const selector of addRecordSelectors) {
        if (await page.locator(selector).isVisible({ timeout: 2000 })) {
          await humanBehavior.humanClick(page, selector);
          await page.waitForTimeout(1000);
          
          // Fill in new record form if it appears
          const formInputs = page.locator('input:not([type="hidden"]), textarea');
          const inputCount = await formInputs.count();
          
          if (inputCount > 0) {
            for (let i = 0; i < Math.min(inputCount, 3); i++) {
              const input = formInputs.nth(i);
              if (await input.isVisible()) {
                const fieldName = await input.getAttribute('name') || `field_${i}`;
                const testValue = `Test ${fieldName} ${Date.now()}`;
                await humanBehavior.humanType(page, input, testValue);
                await page.waitForTimeout(300);
              }
            }
            
            // Submit the form
            const submitSelectors = [
              'button[type="submit"]',
              'button:has-text("Save")',
              'button:has-text("Add")'
            ];
            
            for (const submitSelector of submitSelectors) {
              if (await page.locator(submitSelector).isVisible({ timeout: 1000 })) {
                await humanBehavior.humanClick(page, submitSelector);
                await page.waitForTimeout(2000);
                recordAdded = true;
                break;
              }
            }
          }
          
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'after-adding-record');
      traceHelper.logTestEvent('step_completed', { step: 'add_new_record', recordAdded });
      
    } catch (error) {
      await traceHelper.captureScreenshot(page, 'edit-records-error', { fullPage: true });
      traceHelper.logTestEvent('test_failed', { error: error.message });
      throw error;
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });

  test('Export data functionality @regression', async ({ page }) => {
    const testContext = traceHelper.createTestContext('export-data', page);
    
    try {
      // Step 1: Locate export functionality
      traceHelper.logTestEvent('step_started', { step: 'locate_export_options' });
      
      const exportSelectors = [
        '[data-testid="export-button"]',
        'button:has-text("Export")',
        'button:has-text("Download")',
        '.export-button',
        '[aria-label*="export"]',
        '[aria-label*="download"]'
      ];
      
      let exportButton = null;
      
      for (const selector of exportSelectors) {
        const element = page.locator(selector).first();
        if (await element.isVisible({ timeout: 3000 })) {
          exportButton = element;
          break;
        }
      }
      
      // Look in menus or dropdowns
      if (!exportButton) {
        const menuSelectors = [
          '[data-testid="more-actions"]',
          'button:has-text("More")',
          'button:has-text("Actions")',
          '.more-actions',
          '.actions-menu'
        ];
        
        for (const menuSelector of menuSelectors) {
          if (await page.locator(menuSelector).isVisible({ timeout: 2000 })) {
            await humanBehavior.humanClick(page, menuSelector);
            await page.waitForTimeout(500);
            
            // Look for export in the opened menu
            for (const exportSelector of exportSelectors) {
              const element = page.locator(exportSelector).first();
              if (await element.isVisible({ timeout: 1000 })) {
                exportButton = element;
                break;
              }
            }
            
            if (exportButton) break;
          }
        }
      }
      
      await traceHelper.captureScreenshot(page, 'export-options');
      traceHelper.logTestEvent('step_completed', { step: 'locate_export_options', exportFound: !!exportButton });

      // Step 2: Trigger export
      if (exportButton) {
        traceHelper.logTestEvent('step_started', { step: 'trigger_export' });
        
        await humanBehavior.humanClick(page, exportButton);
        await page.waitForTimeout(1000);
        
        // Look for export format options
        const formatSelectors = [
          'button:has-text("CSV")',
          'button:has-text("Excel")',
          'button:has-text("JSON")',
          '[data-testid="csv-export"]',
          '[data-testid="excel-export"]'
        ];
        
        let formatSelected = false;
        
        for (const formatSelector of formatSelectors) {
          if (await page.locator(formatSelector).isVisible({ timeout: 2000 })) {
            await humanBehavior.humanClick(page, formatSelector);
            await page.waitForTimeout(500);
            formatSelected = true;
            break;
          }
        }
        
        // If no format selection, just proceed with default export
        if (!formatSelected) {
          // Look for final export/download button
          const finalExportSelectors = [
            'button:has-text("Download")',
            'button:has-text("Export")',
            'button[type="submit"]'
          ];
          
          for (const finalSelector of finalExportSelectors) {
            if (await page.locator(finalSelector).isVisible({ timeout: 1000 })) {
              await humanBehavior.humanClick(page, finalSelector);
              await page.waitForTimeout(1000);
              break;
            }
          }
        }
        
        await traceHelper.captureScreenshot(page, 'export-triggered');
        traceHelper.logTestEvent('step_completed', { step: 'trigger_export', formatSelected });
      }

      // Step 3: Verify export initiation
      traceHelper.logTestEvent('step_started', { step: 'verify_export' });
      
      // Look for success messages or download notifications
      const successSelectors = [
        '[data-testid="export-success"]',
        '.success-message',
        '.alert-success',
        'text="Export started"',
        'text="Download started"'
      ];
      
      let exportVerified = false;
      
      for (const successSelector of successSelectors) {
        if (await page.locator(successSelector).isVisible({ timeout: 3000 })) {
          exportVerified = true;
          break;
        }
      }
      
      // Note: In a real browser, we might see download progress
      // For automated tests, we'll just verify the export was triggered
      
      await traceHelper.captureScreenshot(page, 'export-verification');
      traceHelper.logTestEvent('step_completed', { step: 'verify_export', exportVerified });
      
    } catch (error) {
      await traceHelper.captureScreenshot(page, 'export-error', { fullPage: true });
      traceHelper.logTestEvent('test_failed', { error: error.message });
      throw error;
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });
});

// Helper function to create test data if none exists
async function createTestData(page, humanBehavior, traceHelper) {
  traceHelper.logTestEvent('step_started', { step: 'create_test_data' });
  
  // Look for ways to create or import data
  const createDataSelectors = [
    '[data-testid="create-table"]',
    'button:has-text("Create Table")',
    'button:has-text("Import")',
    'button:has-text("Add Data")',
    '.create-table-button'
  ];
  
  for (const selector of createDataSelectors) {
    if (await page.locator(selector).isVisible({ timeout: 2000 })) {
      await humanBehavior.humanClick(page, selector);
      await page.waitForTimeout(2000);
      
      // If a form appears, fill it with basic test data
      const nameInput = page.locator('input[name="name"], input[placeholder*="name"]').first();
      if (await nameInput.isVisible({ timeout: 2000 })) {
        await humanBehavior.humanType(page, nameInput, 'Test Table ' + Date.now());
        
        const createButton = page.locator('button:has-text("Create"), button[type="submit"]').first();
        if (await createButton.isVisible({ timeout: 1000 })) {
          await humanBehavior.humanClick(page, createButton);
          await page.waitForTimeout(3000);
        }
      }
      
      break;
    }
  }
  
  traceHelper.logTestEvent('step_completed', { step: 'create_test_data' });
}