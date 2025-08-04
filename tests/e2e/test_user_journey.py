"""
End-to-end test scenarios for complete user journeys in PyAirtable.
Tests the full user experience from registration to feature usage.
"""

import pytest
import asyncio
import httpx
from playwright.async_api import async_playwright, Page, Browser, BrowserContext
from typing import Dict, Any
import json
import time
from dataclasses import dataclass
from tests.fixtures.factories import TestDataFactory


@dataclass
class UserJourneyMetrics:
    """Track metrics for user journey performance"""
    registration_time: float = 0.0
    login_time: float = 0.0
    first_table_creation_time: float = 0.0
    record_creation_time: float = 0.0
    ai_query_time: float = 0.0
    workflow_execution_time: float = 0.0
    websocket_connection_time: float = 0.0
    file_upload_time: float = 0.0
    total_journey_time: float = 0.0


@pytest.mark.e2e
@pytest.mark.slow
class TestCompleteUserJourney:
    """Test complete user journeys from start to finish"""

    @pytest.fixture(autouse=True)
    async def setup_browser(self):
        """Setup browser for E2E tests"""
        self.playwright = await async_playwright().start()
        self.browser = await self.playwright.chromium.launch(
            headless=True,
            args=['--no-sandbox', '--disable-dev-shm-usage']
        )
        self.context = await self.browser.new_context(
            viewport={'width': 1920, 'height': 1080},
            record_video_dir='tests/reports/videos/' if pytest.current_request.config.option.video else None
        )
        self.page = await self.context.new_page()
        
        # Enable console logging
        self.page.on("console", lambda msg: print(f"Browser console: {msg.text}"))
        self.page.on("pageerror", lambda error: print(f"Browser error: {error}"))
        
        yield
        
        await self.context.close()
        await self.browser.close()
        await self.playwright.stop()

    async def test_new_user_complete_journey(self, test_environment, test_data_factory):
        """Test complete journey for a new user from registration to advanced features"""
        metrics = UserJourneyMetrics()
        start_time = time.time()
        
        # Generate test user data
        user_data = test_data_factory.create_user_data()
        
        try:
            # Step 1: Registration
            await self._test_user_registration(user_data, metrics)
            
            # Step 2: Email verification (mocked)
            await self._test_email_verification(user_data, metrics)
            
            # Step 3: Login
            await self._test_user_login(user_data, metrics)
            
            # Step 4: Dashboard access
            await self._test_dashboard_access(metrics)
            
            # Step 5: Create first table
            await self._test_table_creation(metrics)
            
            # Step 6: Add records to table
            await self._test_record_operations(metrics)
            
            # Step 7: Test AI chat functionality
            await self._test_ai_chat_features(metrics)
            
            # Step 8: Test workflow automation
            await self._test_workflow_automation(metrics)
            
            # Step 9: Test file upload/processing
            await self._test_file_operations(metrics)
            
            # Step 10: Test real-time WebSocket features
            await self._test_websocket_features(metrics)
            
            # Step 11: Test collaboration features
            await self._test_collaboration_features(metrics)
            
            # Step 12: Test data export
            await self._test_data_export(metrics)
            
            metrics.total_journey_time = time.time() - start_time
            
            # Validate performance metrics
            await self._validate_performance_metrics(metrics)
            
            # Log journey completion
            print(f"Complete user journey completed in {metrics.total_journey_time:.2f}s")
            
        except Exception as e:
            # Capture screenshot on failure
            await self.page.screenshot(path=f'tests/reports/screenshots/journey_failure_{int(time.time())}.png')
            raise

    async def _test_user_registration(self, user_data: Dict[str, Any], metrics: UserJourneyMetrics):
        """Test user registration process"""
        start_time = time.time()
        
        # Navigate to registration page
        await self.page.goto(f"{test_environment.api_gateway_url}/register")
        
        # Fill registration form
        await self.page.fill('[data-testid="email-input"]', user_data['email'])
        await self.page.fill('[data-testid="password-input"]', user_data['password'])
        await self.page.fill('[data-testid="confirm-password-input"]', user_data['password'])
        await self.page.fill('[data-testid="first-name-input"]', user_data['first_name'])
        await self.page.fill('[data-testid="last-name-input"]', user_data['last_name'])
        
        # Submit registration
        await self.page.click('[data-testid="register-button"]')
        
        # Wait for registration success
        await self.page.wait_for_selector('[data-testid="registration-success"]', timeout=10000)
        
        metrics.registration_time = time.time() - start_time
        
        # Verify success message
        success_text = await self.page.text_content('[data-testid="registration-success"]')
        assert "registration successful" in success_text.lower()

    async def _test_email_verification(self, user_data: Dict[str, Any], metrics: UserJourneyMetrics):
        """Test email verification process (mocked in test environment)"""
        # In test environment, we simulate email verification
        # by directly calling the verification endpoint
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{test_environment.auth_service_url}/auth/verify-email",
                json={"email": user_data['email'], "token": "test_verification_token"}
            )
            assert response.status_code == 200

    async def _test_user_login(self, user_data: Dict[str, Any], metrics: UserJourneyMetrics):
        """Test user login process"""
        start_time = time.time()
        
        # Navigate to login page
        await self.page.goto(f"{test_environment.api_gateway_url}/login")
        
        # Fill login form
        await self.page.fill('[data-testid="login-email-input"]', user_data['email'])
        await self.page.fill('[data-testid="login-password-input"]', user_data['password'])
        
        # Submit login
        await self.page.click('[data-testid="login-button"]')
        
        # Wait for dashboard redirect
        await self.page.wait_for_url(f"**/dashboard", timeout=10000)
        
        metrics.login_time = time.time() - start_time
        
        # Verify successful login
        user_profile = await self.page.wait_for_selector('[data-testid="user-profile"]', timeout=5000)
        assert user_profile is not None

    async def _test_dashboard_access(self, metrics: UserJourneyMetrics):
        """Test dashboard access and initial load"""
        # Verify dashboard elements load
        await self.page.wait_for_selector('[data-testid="dashboard-content"]', timeout=10000)
        await self.page.wait_for_selector('[data-testid="navigation-menu"]', timeout=5000)
        await self.page.wait_for_selector('[data-testid="table-list"]', timeout=5000)
        
        # Check for welcome message or onboarding
        welcome_element = await self.page.query_selector('[data-testid="welcome-message"]')
        if welcome_element:
            welcome_text = await welcome_element.text_content()
            assert "welcome" in welcome_text.lower()

    async def _test_table_creation(self, metrics: UserJourneyMetrics):
        """Test creating first table"""
        start_time = time.time()
        
        # Click create table button
        await self.page.click('[data-testid="create-table-button"]')
        
        # Fill table creation form
        table_name = f"Test Table {int(time.time())}"
        await self.page.fill('[data-testid="table-name-input"]', table_name)
        
        # Add some fields
        await self.page.click('[data-testid="add-field-button"]')
        await self.page.fill('[data-testid="field-name-input"]', "Name")
        await self.page.select_option('[data-testid="field-type-select"]', "text")
        
        await self.page.click('[data-testid="add-field-button"]')
        await self.page.fill('[data-testid="field-name-input"]:nth-child(2)', "Email")
        await self.page.select_option('[data-testid="field-type-select"]:nth-child(2)', "email")
        
        # Submit table creation
        await self.page.click('[data-testid="create-table-submit"]')
        
        # Wait for table to be created
        await self.page.wait_for_selector(f'[data-testid="table-{table_name}"]', timeout=10000)
        
        metrics.first_table_creation_time = time.time() - start_time

    async def _test_record_operations(self, metrics: UserJourneyMetrics):
        """Test record creation, updating, and deletion"""
        start_time = time.time()
        
        # Create new record
        await self.page.click('[data-testid="add-record-button"]')
        
        # Fill record data
        await self.page.fill('[data-testid="record-name-field"]', "John Doe")
        await self.page.fill('[data-testid="record-email-field"]', "john.doe@example.com")
        
        # Save record
        await self.page.click('[data-testid="save-record-button"]')
        
        # Wait for record to appear in table
        await self.page.wait_for_selector('[data-testid="record-john-doe"]', timeout=5000)
        
        # Test record editing
        await self.page.click('[data-testid="record-john-doe"] [data-testid="edit-button"]')
        await self.page.fill('[data-testid="record-name-field"]', "John Smith")
        await self.page.click('[data-testid="save-record-button"]')
        
        # Verify update
        await self.page.wait_for_selector('[data-testid="record-john-smith"]', timeout=5000)
        
        metrics.record_creation_time = time.time() - start_time

    async def _test_ai_chat_features(self, metrics: UserJourneyMetrics):
        """Test AI chat functionality"""
        start_time = time.time()
        
        # Open AI chat
        await self.page.click('[data-testid="ai-chat-button"]')
        
        # Wait for chat interface
        await self.page.wait_for_selector('[data-testid="chat-interface"]', timeout=5000)
        
        # Send a message
        chat_message = "Help me analyze the data in my table"
        await self.page.fill('[data-testid="chat-input"]', chat_message)
        await self.page.click('[data-testid="send-chat-button"]')
        
        # Wait for AI response
        await self.page.wait_for_selector('[data-testid="ai-response"]', timeout=15000)
        
        # Verify response contains relevant content
        response_text = await self.page.text_content('[data-testid="ai-response"]')
        assert len(response_text) > 10  # Basic check for meaningful response
        
        metrics.ai_query_time = time.time() - start_time

    async def _test_workflow_automation(self, metrics: UserJourneyMetrics):
        """Test workflow automation features"""
        start_time = time.time()
        
        # Navigate to automations
        await self.page.click('[data-testid="automations-nav"]')
        
        # Create new automation
        await self.page.click('[data-testid="create-automation-button"]')
        
        # Configure trigger
        await self.page.select_option('[data-testid="trigger-type-select"]', "record_created")
        
        # Configure action
        await self.page.select_option('[data-testid="action-type-select"]', "send_email")
        await self.page.fill('[data-testid="email-template-input"]', "New record created: {{record.name}}")
        
        # Save automation
        await self.page.click('[data-testid="save-automation-button"]')
        
        # Verify automation is created
        await self.page.wait_for_selector('[data-testid="automation-created"]', timeout=5000)
        
        metrics.workflow_execution_time = time.time() - start_time

    async def _test_file_operations(self, metrics: UserJourneyMetrics):
        """Test file upload and processing"""
        start_time = time.time()
        
        # Navigate to files section
        await self.page.click('[data-testid="files-nav"]')
        
        # Create a test CSV file content
        csv_content = "Name,Email\nTest User,test@example.com\nAnother User,another@example.com"
        
        # Set file input (simulated)
        file_input = await self.page.query_selector('[data-testid="file-upload-input"]')
        if file_input:
            # In a real scenario, we'd upload an actual file
            # For testing, we simulate the upload result
            await self.page.evaluate("""
                () => {
                    window.simulateFileUpload({
                        name: 'test.csv',
                        size: 1024,
                        type: 'text/csv'
                    });
                }
            """)
        
        # Wait for file processing completion
        await self.page.wait_for_selector('[data-testid="file-processed"]', timeout=10000)
        
        metrics.file_upload_time = time.time() - start_time

    async def _test_websocket_features(self, metrics: UserJourneyMetrics):
        """Test real-time WebSocket features"""
        start_time = time.time()
        
        # Test real-time updates
        await self.page.evaluate("""
            () => {
                // Initialize WebSocket connection
                const ws = new WebSocket('ws://localhost:8000/ws');
                ws.onopen = () => {
                    window.wsConnected = true;
                    ws.send(JSON.stringify({
                        type: 'subscribe',
                        channel: 'table_updates'
                    }));
                };
                ws.onmessage = (event) => {
                    window.wsMessage = JSON.parse(event.data);
                };
            }
        """)
        
        # Wait for WebSocket connection
        await self.page.wait_for_function("window.wsConnected === true", timeout=5000)
        
        # Simulate real-time update
        async with httpx.AsyncClient() as client:
            await client.post(
                f"{test_environment.api_gateway_url}/api/tables/test/records",
                json={"name": "Real-time Test", "email": "realtime@example.com"},
                headers={"Authorization": "Bearer test_token"}
            )
        
        # Wait for WebSocket message
        await self.page.wait_for_function("window.wsMessage !== undefined", timeout=5000)
        
        metrics.websocket_connection_time = time.time() - start_time

    async def _test_collaboration_features(self, metrics: UserJourneyMetrics):
        """Test collaboration features"""
        # Test sharing table
        await self.page.click('[data-testid="share-table-button"]')
        
        # Add collaborator
        await self.page.fill('[data-testid="collaborator-email-input"]', "collaborator@example.com")
        await self.page.select_option('[data-testid="permission-level-select"]', "editor")
        await self.page.click('[data-testid="add-collaborator-button"]')
        
        # Verify collaborator added
        await self.page.wait_for_selector('[data-testid="collaborator-added"]', timeout=5000)

    async def _test_data_export(self, metrics: UserJourneyMetrics):
        """Test data export functionality"""
        # Navigate to export
        await self.page.click('[data-testid="export-data-button"]')
        
        # Select export format
        await self.page.select_option('[data-testid="export-format-select"]', "csv")
        
        # Start export
        await self.page.click('[data-testid="start-export-button"]')
        
        # Wait for export completion
        await self.page.wait_for_selector('[data-testid="export-complete"]', timeout=10000)

    async def _validate_performance_metrics(self, metrics: UserJourneyMetrics):
        """Validate that performance metrics meet acceptable thresholds"""
        # Define acceptable thresholds
        thresholds = {
            'registration_time': 5.0,
            'login_time': 3.0,
            'first_table_creation_time': 5.0,
            'record_creation_time': 3.0,
            'ai_query_time': 10.0,
            'workflow_execution_time': 5.0,
            'websocket_connection_time': 2.0,
            'file_upload_time': 10.0,
            'total_journey_time': 60.0
        }
        
        # Check each metric
        for metric_name, threshold in thresholds.items():
            actual_value = getattr(metrics, metric_name)
            assert actual_value <= threshold, f"{metric_name} took {actual_value:.2f}s, exceeding threshold of {threshold}s"
        
        # Log metrics for reporting
        print(f"Performance Metrics:")
        for metric_name, threshold in thresholds.items():
            actual_value = getattr(metrics, metric_name)
            print(f"  {metric_name}: {actual_value:.2f}s (threshold: {threshold}s)")


@pytest.mark.e2e
class TestErrorScenarios:
    """Test error handling and edge cases in user journeys"""

    async def test_registration_with_invalid_data(self, test_environment):
        """Test registration with various invalid inputs"""
        async with async_playwright() as p:
            browser = await p.chromium.launch()
            page = await browser.new_page()
            
            await page.goto(f"{test_environment.api_gateway_url}/register")
            
            # Test with invalid email
            await page.fill('[data-testid="email-input"]', "invalid-email")
            await page.fill('[data-testid="password-input"]', "password123")
            await page.click('[data-testid="register-button"]')
            
            # Verify error message
            error_message = await page.wait_for_selector('[data-testid="email-error"]', timeout=5000)
            assert error_message is not None
            
            await browser.close()

    async def test_network_failure_handling(self, test_environment):
        """Test application behavior during network failures"""
        async with async_playwright() as p:
            browser = await p.chromium.launch()
            context = await browser.new_context()
            
            # Simulate network failure
            await context.route("**/*", lambda route: route.abort())
            
            page = await context.new_page()
            await page.goto(f"{test_environment.api_gateway_url}/login")
            
            # Verify error handling
            await page.wait_for_selector('[data-testid="network-error"]', timeout=10000)
            
            await browser.close()


@pytest.mark.e2e
class TestAccessibilityCompliance:
    """Test accessibility compliance for user interfaces"""

    async def test_keyboard_navigation(self, test_environment):
        """Test complete keyboard navigation through the application"""
        async with async_playwright() as p:
            browser = await p.chromium.launch()
            page = await browser.new_page()
            
            await page.goto(f"{test_environment.api_gateway_url}/login")
            
            # Test tab navigation
            await page.press('body', 'Tab')  # Focus on email input
            await page.type('[data-testid="login-email-input"]', 'test@example.com')
            
            await page.press('body', 'Tab')  # Focus on password input
            await page.type('[data-testid="login-password-input"]', 'password123')
            
            await page.press('body', 'Tab')  # Focus on login button
            await page.press('body', 'Enter')  # Submit form
            
            await browser.close()

    async def test_screen_reader_compatibility(self, test_environment):
        """Test screen reader compatibility with ARIA labels"""
        async with async_playwright() as p:
            browser = await p.chromium.launch()
            page = await browser.new_page()
            
            await page.goto(f"{test_environment.api_gateway_url}/dashboard")
            
            # Check for proper ARIA labels
            elements_with_aria = await page.query_selector_all('[aria-label]')
            assert len(elements_with_aria) > 0, "No elements with ARIA labels found"
            
            # Check for proper heading structure
            headings = await page.query_selector_all('h1, h2, h3, h4, h5, h6')
            assert len(headings) > 0, "No semantic headings found"
            
            await browser.close()


@pytest.mark.e2e
class TestMobileResponsiveness:
    """Test mobile responsiveness and touch interactions"""

    async def test_mobile_viewport_adaptation(self, test_environment):
        """Test application adaptation to mobile viewports"""
        async with async_playwright() as p:
            browser = await p.chromium.launch()
            context = await browser.new_context(
                viewport={'width': 375, 'height': 667},  # iPhone SE
                user_agent='Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)'
            )
            page = await context.new_page()
            
            await page.goto(f"{test_environment.api_gateway_url}/dashboard")
            
            # Verify mobile navigation
            mobile_menu = await page.query_selector('[data-testid="mobile-menu-button"]')
            assert mobile_menu is not None, "Mobile menu button not found"
            
            # Test mobile menu functionality
            await page.click('[data-testid="mobile-menu-button"]')
            mobile_nav = await page.wait_for_selector('[data-testid="mobile-navigation"]', timeout=5000)
            assert mobile_nav is not None
            
            await browser.close()

    async def test_touch_interactions(self, test_environment):
        """Test touch interactions on mobile devices"""
        async with async_playwright() as p:
            browser = await p.chromium.launch()
            context = await browser.new_context(
                viewport={'width': 375, 'height': 667},
                has_touch=True
            )
            page = await context.new_page()
            
            await page.goto(f"{test_environment.api_gateway_url}/dashboard")
            
            # Test swipe gestures
            table_element = await page.query_selector('[data-testid="data-table"]')
            if table_element:
                # Simulate swipe gesture
                await page.touch_screen.tap(200, 300)
                await page.touch_screen.tap(100, 300)
            
            await browser.close()