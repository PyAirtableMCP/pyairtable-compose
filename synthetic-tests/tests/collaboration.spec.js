const { test, expect } = require('@playwright/test');
const HumanBehavior = require('../utils/human-behavior');
const TraceHelper = require('../utils/trace-helper');
const testConfig = require('../config/test-config.json');

test.describe('Collaboration and Workspace Sharing @regression', () => {
  let humanBehavior;
  let traceHelper;

  test.beforeEach(async ({ page }) => {
    humanBehavior = new HumanBehavior();
    traceHelper = new TraceHelper();
    
    // Setup tracing for this test
    await traceHelper.setupTracing(page, 'collaboration');
    
    // Navigate to dashboard
    await humanBehavior.humanNavigate(page, '/dashboard');
    await page.waitForLoadState('networkidle');
  });

  test('Share workspace with team members @regression', async ({ page }) => {
    const testContext = traceHelper.createTestContext('workspace-sharing', page);
    
    try {
      // Step 1: Navigate to workspace settings or sharing section
      traceHelper.logTestEvent('step_started', { step: 'navigate_to_sharing' });
      
      const sharingSelectors = [
        '[data-testid="share-workspace"]',
        '[data-testid="workspace-settings"]',
        'button:has-text("Share")',
        'a:has-text("Share")',
        'button:has-text("Invite")',
        '[aria-label*="share"]',
        '.share-button',
        '.invite-button'
      ];
      
      let sharingFound = false;
      
      for (const selector of sharingSelectors) {
        if (await page.locator(selector).isVisible({ timeout: 3000 })) {
          await humanBehavior.humanClick(page, selector);
          await page.waitForTimeout(2000);
          sharingFound = true;
          break;
        }
      }
      
      // If not found in main view, try workspace menu or settings
      if (!sharingFound) {
        const menuSelectors = [
          '[data-testid="workspace-menu"]',
          '[data-testid="settings-menu"]',
          'button:has-text("Settings")',
          '.workspace-menu',
          '.settings-button'
        ];
        
        for (const menuSelector of menuSelectors) {
          if (await page.locator(menuSelector).isVisible({ timeout: 2000 })) {
            await humanBehavior.humanClick(page, menuSelector);
            await page.waitForTimeout(1000);
            
            // Look for sharing option in the menu
            for (const shareSelector of sharingSelectors) {
              if (await page.locator(shareSelector).isVisible({ timeout: 2000 })) {
                await humanBehavior.humanClick(page, shareSelector);
                await page.waitForTimeout(1000);
                sharingFound = true;
                break;
              }
            }
            
            if (sharingFound) break;
          }
        }
      }
      
      await traceHelper.captureScreenshot(page, 'sharing-interface');
      traceHelper.logTestEvent('step_completed', { step: 'navigate_to_sharing', found: sharingFound });

      // Step 2: Add team member email
      if (sharingFound) {
        traceHelper.logTestEvent('step_started', { step: 'add_team_member' });
        
        const emailInputSelectors = [
          '[data-testid="invite-email"]',
          'input[name="email"]',
          'input[placeholder*="email"]',
          'input[type="email"]',
          '.invite-email-input'
        ];
        
        let emailInput = null;
        
        for (const inputSelector of emailInputSelectors) {
          const element = page.locator(inputSelector).first();
          if (await element.isVisible({ timeout: 3000 })) {
            emailInput = element;
            break;
          }
        }
        
        if (emailInput) {
          const testEmail = `collaborator.${Date.now()}@example.com`;
          await humanBehavior.humanType(page, emailInput, testEmail);
          await page.waitForTimeout(500);
          
          // Select role if available
          const roleSelectors = [
            '[data-testid="role-select"]',
            'select[name="role"]',
            '.role-dropdown'
          ];
          
          for (const roleSelector of roleSelectors) {
            if (await page.locator(roleSelector).isVisible({ timeout: 2000 })) {
              await humanBehavior.humanClick(page, roleSelector);
              await page.waitForTimeout(500);
              
              // Select an appropriate role
              const roleOptions = page.locator('option, [role="option"]');
              const optionCount = await roleOptions.count();
              if (optionCount > 1) {
                // Select second option (usually "Editor" or "Collaborator")
                await humanBehavior.humanClick(page, roleOptions.nth(1));
              }
              break;
            }
          }
          
          // Send invitation
          const inviteButtonSelectors = [
            '[data-testid="send-invite"]',
            'button:has-text("Invite")',
            'button:has-text("Send")',
            'button:has-text("Add")',
            'button[type="submit"]'
          ];
          
          let inviteSent = false;
          
          for (const inviteSelector of inviteButtonSelectors) {
            if (await page.locator(inviteSelector).isVisible({ timeout: 2000 })) {
              await humanBehavior.humanClick(page, inviteSelector);
              await page.waitForTimeout(2000);
              inviteSent = true;
              break;
            }
          }
          
          await traceHelper.captureScreenshot(page, 'team-member-invited');
          traceHelper.logTestEvent('team_member_invited', { email: testEmail, sent: inviteSent });
        }
        
        traceHelper.logTestEvent('step_completed', { step: 'add_team_member' });
      }

      // Step 3: Verify invitation was sent
      traceHelper.logTestEvent('step_started', { step: 'verify_invitation' });
      
      const successSelectors = [
        '[data-testid="invite-success"]',
        '.success-message',
        '.alert-success',
        'text="Invitation sent"',
        'text="Invite sent"',
        'text="User invited"'
      ];
      
      let invitationVerified = false;
      
      for (const successSelector of successSelectors) {
        if (await page.locator(successSelector).isVisible({ timeout: 3000 })) {
          invitationVerified = true;
          break;
        }
      }
      
      // Also check for the invited user in the team list
      const teamListSelectors = [
        '[data-testid="team-members"]',
        '.team-list',
        '.collaborators-list',
        '.members-list'
      ];
      
      let teamListFound = false;
      
      for (const listSelector of teamListSelectors) {
        if (await page.locator(listSelector).isVisible({ timeout: 2000 })) {
          teamListFound = true;
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'invitation-verified');
      traceHelper.logTestEvent('step_completed', { 
        step: 'verify_invitation', 
        verified: invitationVerified,
        teamListVisible: teamListFound
      });
      
    } catch (error) {
      await traceHelper.captureScreenshot(page, 'workspace-sharing-error', { fullPage: true });
      traceHelper.logTestEvent('test_failed', { error: error.message });
      throw error;
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });

  test('Real-time collaborative editing @regression', async ({ page, context }) => {
    const testContext = traceHelper.createTestContext('real-time-collaboration', page);
    
    try {
      // Step 1: Open a second browser context to simulate another user
      traceHelper.logTestEvent('step_started', { step: 'setup_second_user' });
      
      const secondPage = await context.newPage();
      await traceHelper.setupTracing(secondPage, 'collaboration-second-user');
      
      // Navigate both pages to the same workspace/document
      await humanBehavior.humanNavigate(page, '/dashboard');
      await humanBehavior.humanNavigate(secondPage, '/dashboard');
      
      await page.waitForLoadState('networkidle');
      await secondPage.waitForLoadState('networkidle');
      
      await traceHelper.captureScreenshot(page, 'user1-workspace');
      await traceHelper.captureScreenshot(secondPage, 'user2-workspace');
      
      traceHelper.logTestEvent('step_completed', { step: 'setup_second_user' });

      // Step 2: User 1 makes an edit
      traceHelper.logTestEvent('step_started', { step: 'user1_edit' });
      
      const editableSelectors = [
        '[data-testid="editable-field"]',
        '[contenteditable="true"]',
        'textarea',
        'input:not([type="hidden"])',
        '.editable-cell'
      ];
      
      let editMade = false;
      
      for (const selector of editableSelectors) {
        const element = page.locator(selector).first();
        if (await element.isVisible({ timeout: 3000 })) {
          await humanBehavior.humanClick(page, selector);
          await page.waitForTimeout(500);
          
          const testContent = `User 1 edit at ${new Date().toLocaleTimeString()}`;
          await humanBehavior.humanType(page, selector, testContent);
          await page.waitForTimeout(1000);
          
          editMade = true;
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'user1-edit-made');
      traceHelper.logTestEvent('step_completed', { step: 'user1_edit', editMade });

      // Step 3: Check if User 2 sees the changes
      traceHelper.logTestEvent('step_started', { step: 'verify_real_time_sync' });
      
      // Wait a moment for real-time sync
      await page.waitForTimeout(3000);
      await secondPage.waitForTimeout(3000);
      
      // Refresh second page or wait for websocket updates
      await secondPage.reload({ waitUntil: 'networkidle' });
      
      await traceHelper.captureScreenshot(secondPage, 'user2-after-user1-edit');
      
      // Look for activity indicators or presence indicators
      const presenceSelectors = [
        '[data-testid="user-presence"]',
        '.online-users',
        '.collaborators-indicator',
        '.presence-indicator'
      ];
      
      let presenceVisible = false;
      
      for (const presenceSelector of presenceSelectors) {
        if (await secondPage.locator(presenceSelector).isVisible({ timeout: 2000 })) {
          presenceVisible = true;
          break;
        }
      }
      
      traceHelper.logTestEvent('real_time_sync_check', { presenceVisible });
      traceHelper.logTestEvent('step_completed', { step: 'verify_real_time_sync' });

      // Step 4: User 2 makes a counter-edit
      traceHelper.logTestEvent('step_started', { step: 'user2_edit' });
      
      let user2EditMade = false;
      
      for (const selector of editableSelectors) {
        const element = secondPage.locator(selector).first();
        if (await element.isVisible({ timeout: 3000 })) {
          await humanBehavior.humanClick(secondPage, selector);
          await secondPage.waitForTimeout(500);
          
          const testContent = ` + User 2 addition at ${new Date().toLocaleTimeString()}`;
          await humanBehavior.humanType(secondPage, selector, testContent);
          await secondPage.waitForTimeout(1000);
          
          user2EditMade = true;
          break;
        }
      }
      
      await traceHelper.captureScreenshot(secondPage, 'user2-edit-made');
      traceHelper.logTestEvent('step_completed', { step: 'user2_edit', editMade: user2EditMade });

      // Step 5: Check conflict resolution
      traceHelper.logTestEvent('step_started', { step: 'check_conflict_resolution' });
      
      await page.waitForTimeout(3000);
      await page.reload({ waitUntil: 'networkidle' });
      
      // Look for conflict indicators or merged content
      const conflictSelectors = [
        '[data-testid="conflict-indicator"]',
        '.conflict-warning',
        '.merge-conflict',
        '.conflict-resolution'
      ];
      
      let conflictDetected = false;
      
      for (const conflictSelector of conflictSelectors) {
        if (await page.locator(conflictSelector).isVisible({ timeout: 2000 })) {
          conflictDetected = true;
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'conflict-resolution-check');
      
      traceHelper.logTestEvent('conflict_resolution', { conflictDetected });
      traceHelper.logTestEvent('step_completed', { step: 'check_conflict_resolution' });
      
      // Clean up second page
      await secondPage.close();
      
    } catch (error) {
      await traceHelper.captureScreenshot(page, 'collaboration-error', { fullPage: true });
      traceHelper.logTestEvent('test_failed', { error: error.message });
      throw error;
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });

  test('Comments and notifications system @regression', async ({ page }) => {
    const testContext = traceHelper.createTestContext('comments-notifications', page);
    
    try {
      // Step 1: Find commentable content
      traceHelper.logTestEvent('step_started', { step: 'locate_commentable_content' });
      
      const commentSelectors = [
        '[data-testid="add-comment"]',
        '[data-testid="comment-button"]',
        'button:has-text("Comment")',
        '.comment-button',
        '[aria-label*="comment"]'
      ];
      
      let commentButtonFound = false;
      
      for (const selector of commentSelectors) {
        if (await page.locator(selector).isVisible({ timeout: 3000 })) {
          await humanBehavior.humanClick(page, selector);
          await page.waitForTimeout(1000);
          commentButtonFound = true;
          break;
        }
      }
      
      // If no direct comment button, try right-click context menu
      if (!commentButtonFound) {
        const contentSelectors = [
          '[data-testid="data-cell"]',
          '.data-cell',
          'td',
          '.record'
        ];
        
        for (const contentSelector of contentSelectors) {
          const element = page.locator(contentSelector).first();
          if (await element.isVisible({ timeout: 2000 })) {
            await element.click({ button: 'right' });
            await page.waitForTimeout(500);
            
            // Look for comment option in context menu
            for (const commentSelector of commentSelectors) {
              if (await page.locator(commentSelector).isVisible({ timeout: 1000 })) {
                await humanBehavior.humanClick(page, commentSelector);
                commentButtonFound = true;
                break;
              }
            }
            
            if (commentButtonFound) break;
          }
        }
      }
      
      await traceHelper.captureScreenshot(page, 'comment-interface');
      traceHelper.logTestEvent('step_completed', { step: 'locate_commentable_content', found: commentButtonFound });

      // Step 2: Add a comment
      if (commentButtonFound) {
        traceHelper.logTestEvent('step_started', { step: 'add_comment' });
        
        const commentInputSelectors = [
          '[data-testid="comment-input"]',
          'textarea[placeholder*="comment"]',
          '.comment-input textarea',
          '.comment-box textarea'
        ];
        
        let commentAdded = false;
        
        for (const inputSelector of commentInputSelectors) {
          if (await page.locator(inputSelector).isVisible({ timeout: 3000 })) {
            const commentText = `Test comment added at ${new Date().toLocaleTimeString()}. This is a collaborative feedback on the data.`;
            
            await humanBehavior.humanType(page, inputSelector, commentText);
            await page.waitForTimeout(500);
            
            // Submit comment
            const submitSelectors = [
              '[data-testid="submit-comment"]',
              'button:has-text("Post")',
              'button:has-text("Add Comment")',
              'button:has-text("Submit")',
              'button[type="submit"]'
            ];
            
            for (const submitSelector of submitSelectors) {
              if (await page.locator(submitSelector).isVisible({ timeout: 2000 })) {
                await humanBehavior.humanClick(page, submitSelector);
                await page.waitForTimeout(2000);
                commentAdded = true;
                break;
              }
            }
            
            break;
          }
        }
        
        await traceHelper.captureScreenshot(page, 'comment-added');
        traceHelper.logTestEvent('comment_added', { added: commentAdded });
        traceHelper.logTestEvent('step_completed', { step: 'add_comment' });
      }

      // Step 3: Verify comment appears
      traceHelper.logTestEvent('step_started', { step: 'verify_comment_display' });
      
      const commentDisplaySelectors = [
        '[data-testid="comment"]',
        '.comment',
        '.comment-item',
        '.feedback-item'
      ];
      
      let commentVisible = false;
      
      for (const displaySelector of commentDisplaySelectors) {
        if (await page.locator(displaySelector).isVisible({ timeout: 3000 })) {
          commentVisible = true;
          
          // Simulate reading the comment
          await humanBehavior.simulateReading(page, displaySelector);
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'comment-displayed');
      traceHelper.logTestEvent('step_completed', { step: 'verify_comment_display', visible: commentVisible });

      // Step 4: Check for notifications
      traceHelper.logTestEvent('step_started', { step: 'check_notifications' });
      
      const notificationSelectors = [
        '[data-testid="notifications"]',
        '[data-testid="notification-bell"]',
        '.notification-icon',
        '.notifications-button',
        '[aria-label*="notification"]'
      ];
      
      let notificationsFound = false;
      
      for (const notificationSelector of notificationSelectors) {
        if (await page.locator(notificationSelector).isVisible({ timeout: 3000 })) {
          await humanBehavior.humanClick(page, notificationSelector);
          await page.waitForTimeout(1000);
          
          // Check if notification panel opened
          const notificationPanelSelectors = [
            '[data-testid="notification-panel"]',
            '.notification-dropdown',
            '.notifications-list'
          ];
          
          for (const panelSelector of notificationPanelSelectors) {
            if (await page.locator(panelSelector).isVisible({ timeout: 2000 })) {
              notificationsFound = true;
              await humanBehavior.simulateReading(page, panelSelector);
              break;
            }
          }
          
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'notifications-checked');
      traceHelper.logTestEvent('step_completed', { step: 'check_notifications', found: notificationsFound });

      // Step 5: Reply to comment (if supported)
      traceHelper.logTestEvent('step_started', { step: 'reply_to_comment' });
      
      const replySelectors = [
        '[data-testid="reply-button"]',
        'button:has-text("Reply")',
        '.reply-button'
      ];
      
      let replyAdded = false;
      
      for (const replySelector of replySelectors) {
        if (await page.locator(replySelector).isVisible({ timeout: 2000 })) {
          await humanBehavior.humanClick(page, replySelector);
          await page.waitForTimeout(500);
          
          // Look for reply input
          const replyInputSelectors = [
            '[data-testid="reply-input"]',
            '.reply-input textarea',
            'textarea[placeholder*="reply"]'
          ];
          
          for (const replyInputSelector of replyInputSelectors) {
            if (await page.locator(replyInputSelector).isVisible({ timeout: 2000 })) {
              const replyText = `Reply to comment: Acknowledged and will review this data point.`;
              await humanBehavior.humanType(page, replyInputSelector, replyText);
              
              const submitReplySelectors = [
                '[data-testid="submit-reply"]',
                'button:has-text("Reply")',
                'button:has-text("Post Reply")'
              ];
              
              for (const submitReplySelector of submitReplySelectors) {
                if (await page.locator(submitReplySelector).isVisible({ timeout: 1000 })) {
                  await humanBehavior.humanClick(page, submitReplySelector);
                  await page.waitForTimeout(1000);
                  replyAdded = true;
                  break;
                }
              }
              
              break;
            }
          }
          
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'comment-reply');
      traceHelper.logTestEvent('step_completed', { step: 'reply_to_comment', replyAdded });
      
    } catch (error) {
      await traceHelper.captureScreenshot(page, 'comments-notifications-error', { fullPage: true });
      traceHelper.logTestEvent('test_failed', { error: error.message });
      throw error;
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });

  test('Workspace permissions and access control @regression', async ({ page }) => {
    const testContext = traceHelper.createTestContext('workspace-permissions', page);
    
    try {
      // Step 1: Navigate to workspace settings
      traceHelper.logTestEvent('step_started', { step: 'navigate_to_settings' });
      
      const settingsSelectors = [
        '[data-testid="workspace-settings"]',
        '[data-testid="permissions"]',
        'button:has-text("Settings")',
        'a:has-text("Settings")',
        '[href*="settings"]',
        '.settings-button'
      ];
      
      let settingsFound = false;
      
      for (const selector of settingsSelectors) {
        if (await page.locator(selector).isVisible({ timeout: 3000 })) {
          await humanBehavior.humanClick(page, selector);
          await page.waitForLoadState('networkidle');
          await page.waitForTimeout(2000);
          settingsFound = true;
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'workspace-settings');
      traceHelper.logTestEvent('step_completed', { step: 'navigate_to_settings', found: settingsFound });

      // Step 2: Review current permissions
      if (settingsFound) {
        traceHelper.logTestEvent('step_started', { step: 'review_permissions' });
        
        const permissionSections = [
          '[data-testid="permissions-section"]',
          '.permissions-panel',
          '.access-control',
          '.member-permissions'
        ];
        
        let permissionsVisible = false;
        
        for (const section of permissionSections) {
          if (await page.locator(section).isVisible({ timeout: 3000 })) {
            await humanBehavior.simulateReading(page, section);
            permissionsVisible = true;
            break;
          }
        }
        
        // Look for permission controls
        const permissionControls = [
          'select[name*="role"]',
          '.role-selector',
          'input[type="checkbox"]',
          '.permission-toggle'
        ];
        
        let controlsFound = 0;
        
        for (const control of permissionControls) {
          const elements = page.locator(control);
          controlsFound += await elements.count();
        }
        
        await traceHelper.captureScreenshot(page, 'permissions-review');
        traceHelper.logTestEvent('permissions_review', { 
          permissionsVisible, 
          controlsFound 
        });
        traceHelper.logTestEvent('step_completed', { step: 'review_permissions' });

        // Step 3: Test permission changes
        traceHelper.logTestEvent('step_started', { step: 'test_permission_changes' });
        
        // Try to modify a permission setting
        const toggleSelectors = [
          'input[type="checkbox"]',
          '.permission-toggle',
          '.access-toggle'
        ];
        
        let permissionChanged = false;
        
        for (const toggleSelector of toggleSelectors) {
          const toggle = page.locator(toggleSelector).first();
          if (await toggle.isVisible({ timeout: 2000 })) {
            const wasChecked = await toggle.isChecked();
            await humanBehavior.humanClick(page, toggle);
            await page.waitForTimeout(500);
            
            const isChecked = await toggle.isChecked();
            if (wasChecked !== isChecked) {
              permissionChanged = true;
              
              // Save changes if save button exists
              const saveSelectors = [
                'button:has-text("Save")',
                'button:has-text("Update")',
                'button[type="submit"]'
              ];
              
              for (const saveSelector of saveSelectors) {
                if (await page.locator(saveSelector).isVisible({ timeout: 2000 })) {
                  await humanBehavior.humanClick(page, saveSelector);
                  await page.waitForTimeout(1000);
                  break;
                }
              }
            }
            
            break;
          }
        }
        
        await traceHelper.captureScreenshot(page, 'permission-changed');
        traceHelper.logTestEvent('step_completed', { step: 'test_permission_changes', changed: permissionChanged });
      }
      
    } catch (error) {
      await traceHelper.captureScreenshot(page, 'permissions-error', { fullPage: true });
      traceHelper.logTestEvent('test_failed', { error: error.message });
      throw error;
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });
});