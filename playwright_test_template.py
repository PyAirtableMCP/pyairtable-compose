# PyAirtable Playwright Test Suite
# Run with: playwright test

from playwright.sync_api import sync_playwright, expect
import pytest

class TestPyAirtableUI:
    def setup_method(self):
        self.base_url = "http://localhost:3000"
    
    def test_landing_page_load(self, page):
        """Test main landing page loads correctly"""
        page.goto(self.base_url)
        expect(page).to_have_title("PyAirtable")
        expect(page.locator("nav")).to_be_visible()
    
    def test_user_registration(self, page):
        """Test user registration workflow"""
        page.goto(f"{self.base_url}/register")
        page.fill("[data-testid=email-input]", "test@example.com")
        page.fill("[data-testid=password-input]", "password123")
        page.click("[data-testid=register-button]")
        expect(page).to_have_url(f"{self.base_url}/dashboard")
    
    def test_user_login(self, page):
        """Test user login process"""
        page.goto(f"{self.base_url}/login")
        page.fill("[data-testid=email-input]", "test@example.com")
        page.fill("[data-testid=password-input]", "password123")
        page.click("[data-testid=login-button]")
        expect(page.locator("[data-testid=user-menu]")).to_be_visible()
    
    def test_oauth_login_google(self, page):
        """Test Google OAuth login"""
        page.goto(f"{self.base_url}/login")
        page.click("[data-testid=google-login-button]")
        # OAuth flow would continue here
        
    def test_dashboard_navigation(self, page):
        """Test dashboard navigation"""
        # Assuming user is logged in
        page.goto(f"{self.base_url}/dashboard")
        expect(page.locator("[data-testid=sidebar]")).to_be_visible()
        expect(page.locator("[data-testid=main-content]")).to_be_visible()
        
    def test_cost_tracking_interface(self, page):
        """Test cost monitoring UI"""
        page.goto(f"{self.base_url}/dashboard/costs")
        expect(page.locator("[data-testid=usage-chart]")).to_be_visible()
        expect(page.locator("[data-testid=cost-breakdown]")).to_be_visible()
        
    def test_ai_chat_interface(self, page):
        """Test AI chat functionality"""
        page.goto(f"{self.base_url}/chat")
        page.fill("[data-testid=message-input]", "Hello, can you help me?")
        page.click("[data-testid=send-button]")
        expect(page.locator("[data-testid=ai-response]")).to_be_visible()
        
    def test_workflow_builder(self, page):
        """Test workflow automation UI"""
        page.goto(f"{self.base_url}/workflows")
        page.click("[data-testid=new-workflow-button]")
        expect(page.locator("[data-testid=workflow-editor]")).to_be_visible()
        
    def test_mobile_responsiveness(self, page):
        """Test mobile responsive design"""
        page.set_viewport_size({"width": 375, "height": 667})  # iPhone size
        page.goto(self.base_url)
        expect(page.locator("[data-testid=mobile-menu]")).to_be_visible()
        
    def test_accessibility_compliance(self, page):
        """Test accessibility standards"""
        page.goto(self.base_url)
        # Check for proper heading hierarchy
        h1_count = page.locator("h1").count()
        assert h1_count == 1, "Page should have exactly one h1 element"
        
        # Check for alt text on images
        images = page.locator("img")
        for i in range(images.count()):
            img = images.nth(i)
            expect(img).to_have_attribute("alt")

# Configuration
pytest_plugins = ["playwright.sync_api"]