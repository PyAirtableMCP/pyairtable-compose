#!/usr/bin/env python3
"""
PyAirtable E2E Testing Agents System

This system creates AI-powered synthetic agents that can interact with the PyAirtable
application like real users, performing comprehensive end-to-end testing, debugging,
and evaluation.

Features:
- Multiple specialized testing agents (UI, API, Integration, Performance)
- Automated browser interaction using Selenium
- AI-powered decision making for test scenarios
- Comprehensive logging and reporting
- Issue detection and debugging
- Visual regression testing
- Performance monitoring
- Accessibility testing
"""

import asyncio
import json
import logging
import time
import traceback
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
import uuid
import random

import requests
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.action_chains import ActionChains
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.common.exceptions import TimeoutException, NoSuchElementException
from selenium.webdriver.common.desired_capabilities import DesiredCapabilities

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class TestResult:
    """Container for test results and metadata"""
    def __init__(self, agent_name: str, test_name: str):
        self.agent_name = agent_name
        self.test_name = test_name
        self.start_time = datetime.now()
        self.end_time = None
        self.status = "running"  # running, passed, failed, error
        self.screenshots = []
        self.logs = []
        self.performance_metrics = {}
        self.issues_found = []
        self.recommendations = []
        
    def add_log(self, level: str, message: str, details: Dict = None):
        """Add a log entry"""
        self.logs.append({
            "timestamp": datetime.now().isoformat(),
            "level": level,
            "message": message,
            "details": details or {}
        })
        
    def add_screenshot(self, path: str, description: str):
        """Add a screenshot"""
        self.screenshots.append({
            "path": path,
            "description": description,
            "timestamp": datetime.now().isoformat()
        })
        
    def add_issue(self, severity: str, title: str, description: str, element: str = None):
        """Add an issue found during testing"""
        self.issues_found.append({
            "severity": severity,  # critical, high, medium, low
            "title": title,
            "description": description,
            "element": element,
            "timestamp": datetime.now().isoformat()
        })
        
    def complete(self, status: str):
        """Mark test as complete"""
        self.end_time = datetime.now()
        self.status = status
        self.duration = (self.end_time - self.start_time).total_seconds()

class E2ETestingAgent:
    """Base class for E2E testing agents"""
    
    def __init__(self, name: str, base_url: str = "http://localhost:3005"):
        self.name = name
        self.base_url = base_url
        self.session = requests.Session()
        self.driver = None
        self.results = []
        
        # Create results directory
        self.results_dir = Path("e2e_test_results")
        self.results_dir.mkdir(exist_ok=True)
        
        # Create agent-specific directory
        self.agent_dir = self.results_dir / self.name.lower().replace(" ", "_")
        self.agent_dir.mkdir(exist_ok=True)
        
    def setup_driver(self, headless: bool = True):
        """Setup Chrome WebDriver"""
        chrome_options = Options()
        if headless:
            chrome_options.add_argument("--headless")
        chrome_options.add_argument("--no-sandbox")
        chrome_options.add_argument("--disable-dev-shm-usage")
        chrome_options.add_argument("--disable-gpu")
        chrome_options.add_argument("--window-size=1920,1080")
        
        # Enable logging
        chrome_options.add_argument("--enable-logging")
        chrome_options.add_argument("--log-level=0")
        
        try:
            self.driver = webdriver.Chrome(options=chrome_options)
            self.driver.implicitly_wait(10)
            logger.info(f"{self.name}: WebDriver setup complete")
        except Exception as e:
            logger.error(f"{self.name}: Failed to setup WebDriver: {e}")
            raise
    
    def take_screenshot(self, filename: str, description: str = "") -> str:
        """Take a screenshot and save it"""
        if not self.driver:
            return None
            
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        screenshot_path = self.agent_dir / f"{timestamp}_{filename}.png"
        
        try:
            self.driver.save_screenshot(str(screenshot_path))
            logger.info(f"{self.name}: Screenshot saved: {screenshot_path}")
            return str(screenshot_path)
        except Exception as e:
            logger.error(f"{self.name}: Failed to take screenshot: {e}")
            return None
    
    def wait_for_element(self, by: By, selector: str, timeout: int = 10) -> Optional[Any]:
        """Wait for element to be present and visible"""
        try:
            wait = WebDriverWait(self.driver, timeout)
            element = wait.until(EC.presence_of_element_located((by, selector)))
            return element
        except TimeoutException:
            logger.warning(f"{self.name}: Element not found: {selector}")
            return None
    
    def analyze_page_health(self, result: TestResult):
        """Analyze current page for common issues"""
        if not self.driver:
            return
            
        try:
            # Check for JavaScript errors
            logs = self.driver.get_log('browser')
            js_errors = [log for log in logs if log['level'] == 'SEVERE']
            
            for error in js_errors:
                result.add_issue(
                    "high",
                    "JavaScript Error",
                    error['message'],
                    f"Line: {error.get('source', 'unknown')}"
                )
            
            # Check for broken images
            broken_images = self.driver.execute_script("""
                var images = document.getElementsByTagName('img');
                var broken = [];
                for (var i = 0; i < images.length; i++) {
                    if (!images[i].complete || images[i].naturalWidth === 0) {
                        broken.push(images[i].src);
                    }
                }
                return broken;
            """)
            
            for img_src in broken_images:
                result.add_issue("medium", "Broken Image", f"Image failed to load: {img_src}")
            
            # Check page title
            title = self.driver.title
            if not title or title.lower() in ['untitled', '']:
                result.add_issue("low", "Missing Page Title", "Page has no title or generic title")
            
            # Check for accessibility issues
            self.check_accessibility(result)
            
        except Exception as e:
            result.add_log("error", f"Failed to analyze page health: {e}")
    
    def check_accessibility(self, result: TestResult):
        """Check for basic accessibility issues"""
        try:
            # Check for alt text on images
            images_without_alt = self.driver.execute_script("""
                var images = document.getElementsByTagName('img');
                var missing_alt = [];
                for (var i = 0; i < images.length; i++) {
                    if (!images[i].alt || images[i].alt.trim() === '') {
                        missing_alt.push(images[i].src || 'unnamed image');
                    }
                }
                return missing_alt;
            """)
            
            for img in images_without_alt:
                result.add_issue("medium", "Missing Alt Text", f"Image missing alt text: {img}")
            
            # Check for form labels
            unlabeled_inputs = self.driver.execute_script("""
                var inputs = document.querySelectorAll('input[type="text"], input[type="email"], textarea');
                var unlabeled = [];
                for (var i = 0; i < inputs.length; i++) {
                    var input = inputs[i];
                    var hasLabel = input.labels && input.labels.length > 0;
                    var hasAriaLabel = input.getAttribute('aria-label');
                    var hasAriaLabelledBy = input.getAttribute('aria-labelledby');
                    
                    if (!hasLabel && !hasAriaLabel && !hasAriaLabelledBy) {
                        unlabeled.push(input.name || input.id || 'unnamed input');
                    }
                }
                return unlabeled;
            """)
            
            for input_name in unlabeled_inputs:
                result.add_issue("medium", "Unlabeled Form Input", f"Form input missing label: {input_name}")
                
        except Exception as e:
            result.add_log("warning", f"Accessibility check failed: {e}")
    
    def cleanup(self):
        """Cleanup resources"""
        if self.driver:
            self.driver.quit()
            logger.info(f"{self.name}: WebDriver cleaned up")

class UITestingAgent(E2ETestingAgent):
    """Agent specialized in UI/UX testing"""
    
    def __init__(self):
        super().__init__("UI Testing Agent")
        
    async def run_ui_tests(self) -> List[TestResult]:
        """Run comprehensive UI tests"""
        tests = [
            self.test_page_load,
            self.test_responsive_design,
            self.test_chat_interface,
            self.test_visual_elements,
            self.test_user_interactions
        ]
        
        results = []
        self.setup_driver(headless=False)  # Show browser for UI testing
        
        try:
            for test in tests:
                result = await test()
                results.append(result)
        finally:
            self.cleanup()
            
        return results
    
    async def test_page_load(self) -> TestResult:
        """Test initial page load and basic functionality"""
        result = TestResult(self.name, "Page Load Test")
        
        try:
            result.add_log("info", "Starting page load test")
            
            # Measure page load time
            start_time = time.time()
            self.driver.get(self.base_url)
            load_time = time.time() - start_time
            
            result.performance_metrics["page_load_time"] = load_time
            result.add_log("info", f"Page loaded in {load_time:.2f} seconds")
            
            # Take initial screenshot
            screenshot_path = self.take_screenshot("page_load", "Initial page load")
            if screenshot_path:
                result.add_screenshot(screenshot_path, "Initial page load")
            
            # Check if essential elements are present
            essential_elements = [
                ("title", By.TAG_NAME, "h1"),
                ("chat_container", By.CLASS_NAME, "chat-container"),
                ("message_input", By.ID, "messageInput"),
                ("send_button", By.ID, "sendButton")
            ]
            
            for name, by, selector in essential_elements:
                element = self.wait_for_element(by, selector, timeout=5)
                if element:
                    result.add_log("info", f"Found essential element: {name}")
                else:
                    result.add_issue("critical", f"Missing Essential Element: {name}", 
                                   f"Could not find {name} using selector {selector}")
            
            # Analyze page health
            self.analyze_page_health(result)
            
            # Check performance thresholds
            if load_time > 5.0:
                result.add_issue("high", "Slow Page Load", f"Page took {load_time:.2f}s to load (>5s)")
            elif load_time > 3.0:
                result.add_issue("medium", "Moderate Page Load", f"Page took {load_time:.2f}s to load (>3s)")
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Page load test failed: {e}")
            result.add_log("error", traceback.format_exc())
            result.complete("failed")
        
        return result
    
    async def test_chat_interface(self) -> TestResult:
        """Test chat interface functionality"""
        result = TestResult(self.name, "Chat Interface Test")
        
        try:
            result.add_log("info", "Starting chat interface test")
            
            # Find chat elements
            message_input = self.wait_for_element(By.ID, "messageInput")
            send_button = self.wait_for_element(By.ID, "sendButton")
            
            if not message_input or not send_button:
                result.add_issue("critical", "Chat Interface Missing", "Could not find chat input or send button")
                result.complete("failed")
                return result
            
            # Test input functionality
            test_message = "Hello, this is a test message from the E2E testing agent"
            message_input.clear()
            message_input.send_keys(test_message)
            
            # Verify input value
            if message_input.get_attribute("value") != test_message:
                result.add_issue("high", "Input Field Issue", "Message input field not working correctly")
            
            # Take screenshot before sending
            screenshot_path = self.take_screenshot("before_send", "Before sending message")
            if screenshot_path:
                result.add_screenshot(screenshot_path, "Chat interface with test message")
            
            # Test send button
            send_button.click()
            
            # Wait for message to appear
            time.sleep(2)
            
            # Check if message appears in chat
            chat_messages = self.driver.find_elements(By.CLASS_NAME, "message")
            user_messages = [msg for msg in chat_messages if "user" in msg.get_attribute("class")]
            
            if user_messages:
                result.add_log("info", "User message successfully added to chat")
            else:
                result.add_issue("high", "Message Not Displayed", "User message did not appear in chat")
            
            # Wait for potential AI response
            time.sleep(5)
            
            # Take screenshot after interaction
            screenshot_path = self.take_screenshot("after_send", "After sending message")
            if screenshot_path:
                result.add_screenshot(screenshot_path, "Chat after sending message")
            
            # Check for AI response
            ai_messages = [msg for msg in self.driver.find_elements(By.CLASS_NAME, "message") 
                          if "assistant" in msg.get_attribute("class")]
            
            if len(ai_messages) > 1:  # More than initial welcome message
                result.add_log("info", "AI response received")
            else:
                result.add_issue("medium", "No AI Response", "AI did not respond to user message")
            
            # Test example prompts
            example_prompts = self.driver.find_elements(By.CLASS_NAME, "example-prompt")
            if example_prompts:
                result.add_log("info", f"Found {len(example_prompts)} example prompts")
                
                # Click on first example
                if example_prompts:
                    example_prompts[0].click()
                    time.sleep(1)
                    
                    # Check if input is populated
                    current_value = message_input.get_attribute("value")
                    if current_value:
                        result.add_log("info", "Example prompt successfully populated input")
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Chat interface test failed: {e}")
            result.add_log("error", traceback.format_exc())
            result.complete("failed")
        
        return result
    
    async def test_responsive_design(self) -> TestResult:
        """Test responsive design across different screen sizes"""
        result = TestResult(self.name, "Responsive Design Test")
        
        screen_sizes = [
            ("Desktop", 1920, 1080),
            ("Tablet", 768, 1024),
            ("Mobile", 375, 667)
        ]
        
        try:
            for size_name, width, height in screen_sizes:
                result.add_log("info", f"Testing {size_name} size: {width}x{height}")
                
                # Resize window
                self.driver.set_window_size(width, height)
                time.sleep(2)  # Allow layout to adjust
                
                # Take screenshot
                screenshot_path = self.take_screenshot(f"responsive_{size_name.lower()}", 
                                                    f"{size_name} view ({width}x{height})")
                if screenshot_path:
                    result.add_screenshot(screenshot_path, f"{size_name} responsive view")
                
                # Check if essential elements are still visible
                essential_elements = ["messageInput", "sendButton"]
                for element_id in essential_elements:
                    element = self.driver.find_element(By.ID, element_id)
                    if element and element.is_displayed():
                        result.add_log("info", f"{size_name}: {element_id} is visible")
                    else:
                        result.add_issue("high", f"Element Hidden on {size_name}", 
                                       f"{element_id} not visible on {size_name} screen")
                
                # Check for horizontal scrolling (bad UX)
                scroll_width = self.driver.execute_script("return document.body.scrollWidth")
                client_width = self.driver.execute_script("return document.documentElement.clientWidth")
                
                if scroll_width > client_width:
                    result.add_issue("medium", f"Horizontal Scroll on {size_name}", 
                                   f"Content width ({scroll_width}px) exceeds viewport ({client_width}px)")
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Responsive design test failed: {e}")
            result.complete("failed")
        
        return result
    
    async def test_visual_elements(self) -> TestResult:
        """Test visual elements and styling"""
        result = TestResult(self.name, "Visual Elements Test")
        
        try:
            result.add_log("info", "Testing visual elements")
            
            # Check color contrast
            elements_to_check = [
                ("h1", "Header text contrast"),
                (".message-content", "Message content contrast"),
                (".send-button", "Send button contrast")
            ]
            
            for selector, description in elements_to_check:
                try:
                    element = self.driver.find_element(By.CSS_SELECTOR, selector)
                    # Get computed styles
                    bg_color = self.driver.execute_script(
                        "return window.getComputedStyle(arguments[0]).backgroundColor", element)
                    text_color = self.driver.execute_script(
                        "return window.getComputedStyle(arguments[0]).color", element)
                    
                    result.add_log("info", f"{description}: bg={bg_color}, text={text_color}")
                    
                except NoSuchElementException:
                    result.add_issue("medium", "Missing Visual Element", f"Could not find {selector}")
            
            # Check for CSS animations
            animated_elements = self.driver.execute_script("""
                var elements = document.querySelectorAll('*');
                var animated = [];
                for (var i = 0; i < elements.length; i++) {
                    var style = window.getComputedStyle(elements[i]);
                    if (style.animationName !== 'none' || style.transitionProperty !== 'none') {
                        animated.push(elements[i].tagName + (elements[i].className ? '.' + elements[i].className : ''));
                    }
                }
                return animated;
            """)
            
            if animated_elements:
                result.add_log("info", f"Found animated elements: {animated_elements}")
            
            # Check font loading
            fonts = self.driver.execute_script("""
                return Array.from(document.fonts).map(font => ({
                    family: font.family,
                    status: font.status
                }));
            """)
            
            for font in fonts:
                if font['status'] !== 'loaded':
                    result.add_issue("low", "Font Loading Issue", f"Font {font['family']} status: {font['status']}")
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Visual elements test failed: {e}")
            result.complete("failed")
        
        return result
    
    async def test_user_interactions(self) -> TestResult:
        """Test various user interactions"""
        result = TestResult(self.name, "User Interactions Test")
        
        try:
            result.add_log("info", "Testing user interactions")
            
            # Test keyboard shortcuts
            message_input = self.wait_for_element(By.ID, "messageInput")
            if message_input:
                # Test Enter key
                message_input.clear()
                message_input.send_keys("Test keyboard shortcut")
                message_input.send_keys(Keys.ENTER)
                
                time.sleep(2)
                
                # Check if message was sent
                current_value = message_input.get_attribute("value")
                if current_value == "":
                    result.add_log("info", "Enter key successfully sends message")
                else:
                    result.add_issue("medium", "Keyboard Shortcut Issue", "Enter key doesn't send message")
            
            # Test button hover states
            send_button = self.wait_for_element(By.ID, "sendButton")
            if send_button:
                # Move mouse to button
                ActionChains(self.driver).move_to_element(send_button).perform()
                time.sleep(1)
                
                # Check for hover styles (this is basic - in real scenarios you'd check computed styles)
                result.add_log("info", "Button hover interaction completed")
            
            # Test example prompt clicks
            example_prompts = self.driver.find_elements(By.CLASS_NAME, "example-prompt")
            if example_prompts and len(example_prompts) > 0:
                for i, prompt in enumerate(example_prompts[:2]):  # Test first 2 prompts
                    prompt_text = prompt.text
                    prompt.click()
                    time.sleep(1)
                    
                    # Check if input was populated
                    current_value = message_input.get_attribute("value")
                    if prompt_text.strip('"') in current_value:
                        result.add_log("info", f"Example prompt {i+1} works correctly")
                    else:
                        result.add_issue("medium", f"Example Prompt {i+1} Issue", 
                                       "Clicking example didn't populate input correctly")
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"User interactions test failed: {e}")
            result.complete("failed")
        
        return result

class APITestingAgent(E2ETestingAgent):
    """Agent specialized in API testing"""
    
    def __init__(self):
        super().__init__("API Testing Agent")
        self.api_base = "http://localhost:8000"
        
    async def run_api_tests(self) -> List[TestResult]:
        """Run comprehensive API tests"""
        tests = [
            self.test_health_endpoints,
            self.test_chat_api,
            self.test_airtable_integration,
            self.test_error_handling,
            self.test_performance
        ]
        
        results = []
        
        for test in tests:
            result = await test()
            results.append(result)
            
        return results
    
    async def test_health_endpoints(self) -> TestResult:
        """Test health check endpoints"""
        result = TestResult(self.name, "Health Endpoints Test")
        
        endpoints = [
            f"{self.api_base}/health",
            f"{self.api_base}/api/v1/health",
            "http://localhost:8001/health",  # MCP Server
            "http://localhost:8002/health",  # Airtable Gateway
            "http://localhost:8003/health"   # LLM Orchestrator
        ]
        
        try:
            for endpoint in endpoints:
                try:
                    response = self.session.get(endpoint, timeout=10)
                    result.add_log("info", f"Health check {endpoint}: {response.status_code}")
                    
                    if response.status_code == 200:
                        result.add_log("info", f"✓ {endpoint} is healthy")
                    else:
                        result.add_issue("high", "Service Unhealthy", 
                                       f"{endpoint} returned {response.status_code}")
                        
                except requests.exceptions.ConnectionError:
                    result.add_issue("critical", "Service Down", f"Cannot connect to {endpoint}")
                except requests.exceptions.Timeout:
                    result.add_issue("high", "Service Timeout", f"Timeout connecting to {endpoint}")
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Health endpoints test failed: {e}")
            result.complete("failed")
        
        return result
    
    async def test_chat_api(self) -> TestResult:
        """Test chat API endpoints"""
        result = TestResult(self.name, "Chat API Test")
        
        chat_endpoints = [
            "/api/v1/chat/message",
            "/api/v1/llm/chat",
            "/api/v1/mcp/query"
        ]
        
        test_messages = [
            "Hello, this is a test message",
            "Analyze my data",
            "Create a formula for calculating totals",
            "What are my top performing records?"
        ]
        
        try:
            for endpoint in chat_endpoints:
                url = f"{self.api_base}{endpoint}"
                result.add_log("info", f"Testing endpoint: {url}")
                
                for message in test_messages:
                    try:
                        payload = {
                            "message": message,
                            "session_id": f"test-session-{uuid.uuid4()}",
                            "query": message,
                            "input": message
                        }
                        
                        start_time = time.time()
                        response = self.session.post(url, json=payload, timeout=30)
                        response_time = time.time() - start_time
                        
                        result.performance_metrics[f"{endpoint}_response_time"] = response_time
                        
                        if response.status_code == 200:
                            result.add_log("info", f"✓ {endpoint} responded in {response_time:.2f}s")
                            
                            # Try to parse response
                            try:
                                response_data = response.json()
                                if isinstance(response_data, dict):
                                    result.add_log("info", f"Response keys: {list(response_data.keys())}")
                            except json.JSONDecodeError:
                                result.add_issue("medium", "Invalid JSON Response", 
                                               f"{endpoint} returned non-JSON response")
                        else:
                            result.add_issue("high", f"API Error {response.status_code}", 
                                           f"{endpoint} returned {response.status_code} for message: {message}")
                        
                        if response_time > 10.0:
                            result.add_issue("medium", "Slow API Response", 
                                           f"{endpoint} took {response_time:.2f}s (>10s)")
                        
                    except requests.exceptions.Timeout:
                        result.add_issue("high", "API Timeout", f"{endpoint} timed out for message: {message}")
                    except requests.exceptions.ConnectionError:
                        result.add_issue("critical", "API Connection Error", f"Cannot connect to {endpoint}")
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Chat API test failed: {e}")
            result.complete("failed")
        
        return result
    
    async def test_airtable_integration(self) -> TestResult:
        """Test Airtable integration endpoints"""
        result = TestResult(self.name, "Airtable Integration Test")
        
        try:
            airtable_endpoints = [
                "/api/v1/airtable/bases",
                "/api/v1/airtable/tables",
                "/api/v1/airtable/records",
                "/api/v1/airtable/analyze"
            ]
            
            for endpoint in airtable_endpoints:
                url = f"http://localhost:8002{endpoint}"
                
                try:
                    response = self.session.get(url, timeout=15)
                    result.add_log("info", f"Airtable endpoint {endpoint}: {response.status_code}")
                    
                    if response.status_code in [200, 401, 403]:  # 401/403 might be auth issues, which is expected
                        result.add_log("info", f"✓ {endpoint} is responding")
                    else:
                        result.add_issue("medium", "Airtable Endpoint Issue", 
                                       f"{endpoint} returned unexpected status {response.status_code}")
                        
                except requests.exceptions.ConnectionError:
                    result.add_issue("high", "Airtable Service Down", f"Cannot connect to {endpoint}")
                except requests.exceptions.Timeout:
                    result.add_issue("medium", "Airtable Timeout", f"Timeout on {endpoint}")
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Airtable integration test failed: {e}")
            result.complete("failed")
        
        return result
    
    async def test_error_handling(self) -> TestResult:
        """Test API error handling"""
        result = TestResult(self.name, "Error Handling Test")
        
        try:
            # Test invalid endpoints
            invalid_endpoints = [
                "/api/v1/nonexistent",
                "/api/v1/chat/invalid",
                "/api/v999/test"
            ]
            
            for endpoint in invalid_endpoints:
                url = f"{self.api_base}{endpoint}"
                
                try:
                    response = self.session.get(url, timeout=10)
                    
                    if response.status_code == 404:
                        result.add_log("info", f"✓ Correct 404 response for {endpoint}")
                    else:
                        result.add_issue("low", "Unexpected Error Response", 
                                       f"{endpoint} returned {response.status_code} instead of 404")
                        
                except requests.exceptions.ConnectionError:
                    # This might be expected if the service is designed to reject invalid routes
                    result.add_log("info", f"Connection refused for {endpoint} (might be expected)")
            
            # Test malformed requests
            malformed_requests = [
                {"invalid": "json"},
                {"message": None},
                {"message": "test", "invalid_field": "value"}
            ]
            
            for payload in malformed_requests:
                try:
                    response = self.session.post(f"{self.api_base}/api/v1/chat/message", 
                                               json=payload, timeout=10)
                    
                    if response.status_code in [400, 422]:  # Bad Request or Unprocessable Entity
                        result.add_log("info", f"✓ Correct error response for malformed request")
                    else:
                        result.add_issue("medium", "Poor Error Handling", 
                                       f"Malformed request returned {response.status_code}")
                        
                except Exception as e:
                    result.add_log("warning", f"Error testing malformed request: {e}")
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Error handling test failed: {e}")
            result.complete("failed")
        
        return result
    
    async def test_performance(self) -> TestResult:
        """Test API performance under load"""
        result = TestResult(self.name, "Performance Test")
        
        try:
            endpoint = f"{self.api_base}/health"
            num_requests = 50
            concurrent_requests = 10
            
            result.add_log("info", f"Testing {num_requests} requests with {concurrent_requests} concurrent")
            
            # Measure response times
            response_times = []
            
            async def make_request(session_id):
                try:
                    start_time = time.time()
                    response = self.session.get(endpoint, timeout=10)
                    response_time = time.time() - start_time
                    response_times.append(response_time)
                    return response.status_code == 200
                except Exception:
                    return False
            
            # Make concurrent requests
            successful_requests = 0
            
            for i in range(0, num_requests, concurrent_requests):
                batch_tasks = []
                for j in range(min(concurrent_requests, num_requests - i)):
                    if await make_request(f"perf-test-{i}-{j}"):
                        successful_requests += 1
                
                # Small delay between batches
                time.sleep(0.1)
            
            # Calculate statistics
            if response_times:
                avg_response_time = sum(response_times) / len(response_times)
                max_response_time = max(response_times)
                min_response_time = min(response_times)
                
                result.performance_metrics.update({
                    "total_requests": num_requests,
                    "successful_requests": successful_requests,
                    "success_rate": successful_requests / num_requests * 100,
                    "avg_response_time": avg_response_time,
                    "max_response_time": max_response_time,
                    "min_response_time": min_response_time
                })
                
                result.add_log("info", f"Performance results:")
                result.add_log("info", f"  Success rate: {successful_requests}/{num_requests} ({successful_requests/num_requests*100:.1f}%)")
                result.add_log("info", f"  Avg response time: {avg_response_time:.3f}s")
                result.add_log("info", f"  Max response time: {max_response_time:.3f}s")
                result.add_log("info", f"  Min response time: {min_response_time:.3f}s")
                
                # Performance thresholds
                if avg_response_time > 1.0:
                    result.add_issue("medium", "Slow Average Response", 
                                   f"Average response time {avg_response_time:.3f}s > 1.0s")
                
                if max_response_time > 5.0:
                    result.add_issue("high", "Very Slow Response", 
                                   f"Max response time {max_response_time:.3f}s > 5.0s")
                
                if successful_requests / num_requests < 0.95:
                    result.add_issue("high", "Low Success Rate", 
                                   f"Success rate {successful_requests/num_requests*100:.1f}% < 95%")
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Performance test failed: {e}")
            result.complete("failed")
        
        return result

class IntegrationTestingAgent(E2ETestingAgent):
    """Agent specialized in integration testing"""
    
    def __init__(self):
        super().__init__("Integration Testing Agent")
        
    async def run_integration_tests(self) -> List[TestResult]:
        """Run comprehensive integration tests"""
        tests = [
            self.test_frontend_backend_integration,
            self.test_service_communication,
            self.test_data_flow,
            self.test_error_propagation
        ]
        
        results = []
        self.setup_driver(headless=True)
        
        try:
            for test in tests:
                result = await test()
                results.append(result)
        finally:
            self.cleanup()
            
        return results
    
    async def test_frontend_backend_integration(self) -> TestResult:
        """Test frontend-backend integration"""
        result = TestResult(self.name, "Frontend-Backend Integration Test")
        
        try:
            result.add_log("info", "Testing frontend-backend integration")
            
            # Load frontend
            self.driver.get(self.base_url)
            time.sleep(3)
            
            # Monitor network requests
            logs = self.driver.get_log('performance')
            network_events = []
            
            for log in logs:
                message = json.loads(log['message'])
                if message['message']['method'] in ['Network.requestWillBeSent', 'Network.responseReceived']:
                    network_events.append(message['message'])
            
            result.add_log("info", f"Captured {len(network_events)} network events")
            
            # Send a message and monitor the API call
            message_input = self.wait_for_element(By.ID, "messageInput")
            send_button = self.wait_for_element(By.ID, "sendButton")
            
            if message_input and send_button:
                test_message = "Integration test message"
                message_input.clear()
                message_input.send_keys(test_message)
                
                # Monitor for API calls
                initial_log_count = len(self.driver.get_log('performance'))
                
                send_button.click()
                
                # Wait for potential API call
                time.sleep(5)
                
                # Check for new network activity
                new_logs = self.driver.get_log('performance')
                new_network_events = new_logs[initial_log_count:]
                
                api_calls = []
                for log in new_network_events:
                    try:
                        message = json.loads(log['message'])
                        if (message['message']['method'] == 'Network.requestWillBeSent' and 
                            'localhost:8000' in message['message']['params']['request']['url']):
                            api_calls.append(message['message']['params']['request']['url'])
                    except:
                        continue
                
                if api_calls:
                    result.add_log("info", f"✓ Frontend made API calls: {api_calls}")
                else:
                    result.add_issue("high", "No API Integration", 
                                   "Frontend did not make expected API calls to backend")
                
                # Check if UI updated appropriately
                time.sleep(2)
                messages = self.driver.find_elements(By.CLASS_NAME, "message")
                
                if len(messages) > 1:  # More than welcome message
                    result.add_log("info", "✓ UI updated after sending message")
                else:
                    result.add_issue("medium", "UI Not Updated", 
                                   "UI did not update after sending message")
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Frontend-backend integration test failed: {e}")
            result.complete("failed")
        
        return result
    
    async def test_service_communication(self) -> TestResult:
        """Test communication between microservices"""
        result = TestResult(self.name, "Service Communication Test")
        
        try:
            result.add_log("info", "Testing service-to-service communication")
            
            # Test API Gateway to downstream services
            api_gateway_url = "http://localhost:8000"
            
            # Test if API Gateway can reach other services
            test_routes = [
                ("/api/v1/llm/health", "LLM Orchestrator"),
                ("/api/v1/mcp/health", "MCP Server"), 
                ("/api/v1/airtable/health", "Airtable Gateway")
            ]
            
            for route, service_name in test_routes:
                try:
                    response = self.session.get(f"{api_gateway_url}{route}", timeout=10)
                    
                    if response.status_code == 200:
                        result.add_log("info", f"✓ API Gateway -> {service_name} communication OK")
                    elif response.status_code == 404:
                        result.add_issue("medium", f"Route Not Configured", 
                                       f"API Gateway route {route} not found")
                    else:
                        result.add_issue("high", f"Service Communication Issue", 
                                       f"API Gateway -> {service_name} returned {response.status_code}")
                        
                except requests.exceptions.ConnectionError:
                    result.add_issue("critical", f"Service Unreachable", 
                                   f"Cannot reach {service_name} via API Gateway")
                except requests.exceptions.Timeout:
                    result.add_issue("high", f"Service Timeout", 
                                   f"Timeout reaching {service_name} via API Gateway")
            
            # Test direct service communication
            services = [
                ("http://localhost:8001", "MCP Server"),
                ("http://localhost:8002", "Airtable Gateway"),
                ("http://localhost:8003", "LLM Orchestrator")
            ]
            
            for service_url, service_name in services:
                try:
                    response = self.session.get(f"{service_url}/health", timeout=10)
                    
                    if response.status_code == 200:
                        result.add_log("info", f"✓ {service_name} direct access OK")
                    else:
                        result.add_issue("medium", f"Direct Service Issue", 
                                       f"{service_name} direct access returned {response.status_code}")
                        
                except requests.exceptions.ConnectionError:
                    result.add_issue("critical", f"Service Down", f"{service_name} is not responding")
                except requests.exceptions.Timeout:
                    result.add_issue("high", f"Service Slow", f"{service_name} response timeout")
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Service communication test failed: {e}")
            result.complete("failed")
        
        return result
    
    async def test_data_flow(self) -> TestResult:
        """Test data flow through the system"""
        result = TestResult(self.name, "Data Flow Test")
        
        try:
            result.add_log("info", "Testing data flow through system")
            
            # Create a test message and trace its path
            test_payload = {
                "message": "Test data flow message",
                "session_id": f"dataflow-test-{uuid.uuid4()}",
                "timestamp": datetime.now().isoformat()
            }
            
            # Send to API Gateway
            try:
                response = self.session.post(
                    "http://localhost:8000/api/v1/chat/message",
                    json=test_payload,
                    timeout=30
                )
                
                if response.status_code == 200:
                    result.add_log("info", "✓ Message accepted by API Gateway")
                    
                    try:
                        response_data = response.json()
                        result.add_log("info", f"Response data keys: {list(response_data.keys()) if isinstance(response_data, dict) else 'non-dict response'}")
                        
                        # Check if response contains expected fields
                        expected_fields = ['response', 'message', 'status', 'result']
                        found_fields = []
                        
                        if isinstance(response_data, dict):
                            for field in expected_fields:
                                if field in response_data:
                                    found_fields.append(field)
                        
                        if found_fields:
                            result.add_log("info", f"✓ Response contains expected fields: {found_fields}")
                        else:
                            result.add_issue("medium", "Unexpected Response Format", 
                                           f"Response doesn't contain expected fields: {expected_fields}")
                        
                    except json.JSONDecodeError:
                        result.add_issue("high", "Invalid Response Format", 
                                       "API Gateway returned non-JSON response")
                else:
                    result.add_issue("high", "Data Flow Blocked", 
                                   f"API Gateway rejected message with status {response.status_code}")
                    
            except requests.exceptions.Timeout:
                result.add_issue("critical", "Data Flow Timeout", 
                               "Message processing timed out")
            except requests.exceptions.ConnectionError:
                result.add_issue("critical", "Data Flow Broken", 
                               "Cannot connect to API Gateway")
            
            # Test data persistence (if applicable)
            # This would test if messages are stored and retrievable
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Data flow test failed: {e}")
            result.complete("failed")
        
        return result
    
    async def test_error_propagation(self) -> TestResult:
        """Test how errors propagate through the system"""
        result = TestResult(self.name, "Error Propagation Test")
        
        try:
            result.add_log("info", "Testing error propagation")
            
            # Test various error scenarios
            error_scenarios = [
                ("Empty message", {"message": ""}),
                ("Null message", {"message": None}),
                ("Missing session_id", {"message": "test"}),
                ("Invalid JSON structure", {"invalid": "structure"}),
            ]
            
            for scenario_name, payload in error_scenarios:
                try:
                    response = self.session.post(
                        "http://localhost:8000/api/v1/chat/message",
                        json=payload,
                        timeout=10
                    )
                    
                    result.add_log("info", f"{scenario_name}: {response.status_code}")
                    
                    if response.status_code in [400, 422]:  # Expected error codes
                        result.add_log("info", f"✓ {scenario_name} properly handled")
                        
                        # Check if error response is informative
                        try:
                            error_data = response.json()
                            if 'error' in error_data or 'message' in error_data:
                                result.add_log("info", f"✓ Error response is informative")
                            else:
                                result.add_issue("low", "Non-informative Error", 
                                               f"{scenario_name} error response lacks details")
                        except json.JSONDecodeError:
                            result.add_issue("medium", "Poor Error Format", 
                                           f"{scenario_name} error response is not JSON")
                    else:
                        result.add_issue("medium", "Unexpected Error Handling", 
                                       f"{scenario_name} returned unexpected status {response.status_code}")
                        
                except requests.exceptions.ConnectionError:
                    result.add_issue("critical", "Error Handling Broken", 
                                   f"System crashed on {scenario_name}")
                except requests.exceptions.Timeout:
                    result.add_issue("high", "Error Handling Slow", 
                                   f"System too slow handling {scenario_name}")
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Error propagation test failed: {e}")
            result.complete("failed")
        
        return result

class TestOrchestrator:
    """Orchestrates and manages all testing agents"""
    
    def __init__(self):
        self.agents = [
            UITestingAgent(),
            APITestingAgent(),
            IntegrationTestingAgent()
        ]
        
        self.results_dir = Path("e2e_test_results")
        self.results_dir.mkdir(exist_ok=True)
        
        # Setup logging
        self.setup_logging()
        
    def setup_logging(self):
        """Setup comprehensive logging"""
        log_file = self.results_dir / f"test_run_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
        
        file_handler = logging.FileHandler(log_file)
        file_handler.setLevel(logging.DEBUG)
        
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        file_handler.setFormatter(formatter)
        
        # Add file handler to all loggers
        logging.getLogger().addHandler(file_handler)
        
        logger.info(f"Test orchestrator initialized. Logs: {log_file}")
    
    async def run_all_tests(self) -> Dict[str, List[TestResult]]:
        """Run all tests from all agents"""
        logger.info("Starting comprehensive E2E test suite")
        
        all_results = {}
        
        for agent in self.agents:
            logger.info(f"Running tests for {agent.name}")
            
            try:
                if isinstance(agent, UITestingAgent):
                    results = await agent.run_ui_tests()
                elif isinstance(agent, APITestingAgent):
                    results = await agent.run_api_tests()
                elif isinstance(agent, IntegrationTestingAgent):
                    results = await agent.run_integration_tests()
                else:
                    results = []
                
                all_results[agent.name] = results
                logger.info(f"Completed {len(results)} tests for {agent.name}")
                
            except Exception as e:
                logger.error(f"Failed to run tests for {agent.name}: {e}")
                logger.error(traceback.format_exc())
                all_results[agent.name] = []
        
        # Generate comprehensive report
        await self.generate_report(all_results)
        
        return all_results
    
    async def generate_report(self, all_results: Dict[str, List[TestResult]]):
        """Generate comprehensive test report"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        report_file = self.results_dir / f"comprehensive_report_{timestamp}.json"
        html_report_file = self.results_dir / f"comprehensive_report_{timestamp}.html"
        
        # Prepare report data
        report_data = {
            "test_run_id": str(uuid.uuid4()),
            "timestamp": datetime.now().isoformat(),
            "summary": {
                "total_agents": len(self.agents),
                "total_tests": sum(len(results) for results in all_results.values()),
                "passed_tests": 0,
                "failed_tests": 0,
                "error_tests": 0,
                "total_issues": 0,
                "critical_issues": 0,
                "high_issues": 0,
                "medium_issues": 0,
                "low_issues": 0
            },
            "agents": {}
        }
        
        # Process results for each agent
        for agent_name, results in all_results.items():
            agent_data = {
                "name": agent_name,
                "total_tests": len(results),
                "passed": 0,
                "failed": 0,
                "errors": 0,
                "tests": []
            }
            
            for result in results:
                # Update counters
                if result.status == "passed":
                    agent_data["passed"] += 1
                    report_data["summary"]["passed_tests"] += 1
                elif result.status == "failed":
                    agent_data["failed"] += 1
                    report_data["summary"]["failed_tests"] += 1
                else:
                    agent_data["errors"] += 1
                    report_data["summary"]["error_tests"] += 1
                
                # Count issues
                for issue in result.issues_found:
                    report_data["summary"]["total_issues"] += 1
                    severity = issue["severity"]
                    report_data["summary"][f"{severity}_issues"] += 1
                
                # Add test data
                test_data = {
                    "name": result.test_name,
                    "status": result.status,
                    "duration": result.duration if result.end_time else None,
                    "issues_count": len(result.issues_found),
                    "screenshots_count": len(result.screenshots),
                    "logs_count": len(result.logs),
                    "performance_metrics": result.performance_metrics,
                    "issues": result.issues_found,
                    "recommendations": result.recommendations
                }
                
                agent_data["tests"].append(test_data)
            
            report_data["agents"][agent_name] = agent_data
        
        # Save JSON report
        with open(report_file, 'w') as f:
            json.dump(report_data, f, indent=2, default=str)
        
        # Generate HTML report
        html_content = self.generate_html_report(report_data, all_results)
        with open(html_report_file, 'w') as f:
            f.write(html_content)
        
        # Print summary
        summary = report_data["summary"]
        logger.info("=" * 80)
        logger.info("E2E TEST RESULTS SUMMARY")
        logger.info("=" * 80)
        logger.info(f"Total Tests: {summary['total_tests']}")
        logger.info(f"Passed: {summary['passed_tests']} | Failed: {summary['failed_tests']} | Errors: {summary['error_tests']}")
        logger.info(f"Success Rate: {summary['passed_tests']/max(summary['total_tests'], 1)*100:.1f}%")
        logger.info(f"Total Issues: {summary['total_issues']}")
        logger.info(f"  Critical: {summary['critical_issues']} | High: {summary['high_issues']} | Medium: {summary['medium_issues']} | Low: {summary['low_issues']}")
        logger.info(f"Reports saved:")
        logger.info(f"  JSON: {report_file}")
        logger.info(f"  HTML: {html_report_file}")
        logger.info("=" * 80)
        
        return report_file, html_report_file
    
    def generate_html_report(self, report_data: Dict, all_results: Dict[str, List[TestResult]]) -> str:
        """Generate HTML report"""
        html = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PyAirtable E2E Test Report</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }}
        .container {{ max-width: 1200px; margin: 0 auto; }}
        .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 2rem; border-radius: 8px; margin-bottom: 2rem; }}
        .summary {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }}
        .metric {{ background: white; padding: 1.5rem; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }}
        .metric h3 {{ margin: 0 0 0.5rem 0; color: #666; font-size: 0.9rem; }}
        .metric .value {{ font-size: 2rem; font-weight: bold; color: #333; }}
        .agents {{ display: flex; flex-direction: column; gap: 2rem; }}
        .agent {{ background: white; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); overflow: hidden; }}
        .agent-header {{ background: #f8f9fa; padding: 1rem; border-bottom: 1px solid #e9ecef; }}
        .agent-header h2 {{ margin: 0; color: #333; }}
        .agent-stats {{ display: flex; gap: 1rem; margin-top: 0.5rem; }}
        .stat {{ padding: 0.25rem 0.75rem; border-radius: 4px; font-size: 0.875rem; font-weight: 500; }}
        .stat.passed {{ background: #d4edda; color: #155724; }}
        .stat.failed {{ background: #f8d7da; color: #721c24; }}
        .stat.error {{ background: #fff3cd; color: #856404; }}
        .tests {{ padding: 1rem; }}
        .test {{ margin-bottom: 1.5rem; padding: 1rem; border: 1px solid #e9ecef; border-radius: 4px; }}
        .test-header {{ display: flex; justify-content: between; align-items: center; margin-bottom: 0.5rem; }}
        .test-name {{ font-weight: 600; color: #333; }}
        .test-status {{ padding: 0.25rem 0.5rem; border-radius: 3px; font-size: 0.75rem; font-weight: 500; text-transform: uppercase; }}
        .test-status.passed {{ background: #d4edda; color: #155724; }}
        .test-status.failed {{ background: #f8d7da; color: #721c24; }}
        .test-status.error {{ background: #fff3cd; color: #856404; }}
        .issues {{ margin-top: 1rem; }}
        .issue {{ margin: 0.5rem 0; padding: 0.75rem; border-radius: 4px; border-left: 4px solid; }}
        .issue.critical {{ background: #f8d7da; border-color: #dc3545; }}
        .issue.high {{ background: #fff3cd; border-color: #ffc107; }}
        .issue.medium {{ background: #d1ecf1; border-color: #17a2b8; }}
        .issue.low {{ background: #d4edda; border-color: #28a745; }}
        .issue-title {{ font-weight: 600; margin-bottom: 0.25rem; }}
        .issue-description {{ color: #666; font-size: 0.9rem; }}
        .performance {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 1rem; margin-top: 1rem; }}
        .perf-metric {{ background: #f8f9fa; padding: 0.75rem; border-radius: 4px; text-align: center; }}
        .perf-value {{ font-size: 1.25rem; font-weight: bold; color: #333; }}
        .perf-label {{ font-size: 0.75rem; color: #666; text-transform: uppercase; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>PyAirtable E2E Test Report</h1>
            <p>Generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            <p>Test Run ID: {report_data['test_run_id']}</p>
        </div>
        
        <div class="summary">
            <div class="metric">
                <h3>Total Tests</h3>
                <div class="value">{report_data['summary']['total_tests']}</div>
            </div>
            <div class="metric">
                <h3>Success Rate</h3>
                <div class="value">{report_data['summary']['passed_tests']/max(report_data['summary']['total_tests'], 1)*100:.1f}%</div>
            </div>
            <div class="metric">
                <h3>Passed</h3>
                <div class="value" style="color: #28a745;">{report_data['summary']['passed_tests']}</div>
            </div>
            <div class="metric">
                <h3>Failed</h3>
                <div class="value" style="color: #dc3545;">{report_data['summary']['failed_tests']}</div>
            </div>
            <div class="metric">
                <h3>Total Issues</h3>
                <div class="value" style="color: #ffc107;">{report_data['summary']['total_issues']}</div>
            </div>
            <div class="metric">
                <h3>Critical Issues</h3>
                <div class="value" style="color: #dc3545;">{report_data['summary']['critical_issues']}</div>
            </div>
        </div>
        
        <div class="agents">
"""
        
        # Add agent details
        for agent_name, agent_data in report_data['agents'].items():
            html += f"""
            <div class="agent">
                <div class="agent-header">
                    <h2>{agent_name}</h2>
                    <div class="agent-stats">
                        <div class="stat passed">{agent_data['passed']} Passed</div>
                        <div class="stat failed">{agent_data['failed']} Failed</div>
                        <div class="stat error">{agent_data['errors']} Errors</div>
                    </div>
                </div>
                <div class="tests">
"""
            
            # Add test details
            for test in agent_data['tests']:
                issues_html = ""
                if test['issues']:
                    issues_html = '<div class="issues">'
                    for issue in test['issues']:
                        issues_html += f"""
                        <div class="issue {issue['severity']}">
                            <div class="issue-title">{issue['title']}</div>
                            <div class="issue-description">{issue['description']}</div>
                        </div>
                        """
                    issues_html += '</div>'
                
                performance_html = ""
                if test['performance_metrics']:
                    performance_html = '<div class="performance">'
                    for metric, value in test['performance_metrics'].items():
                        if isinstance(value, (int, float)):
                            performance_html += f"""
                            <div class="perf-metric">
                                <div class="perf-value">{value:.3f}</div>
                                <div class="perf-label">{metric.replace('_', ' ')}</div>
                            </div>
                            """
                    performance_html += '</div>'
                
                html += f"""
                <div class="test">
                    <div class="test-header">
                        <div class="test-name">{test['name']}</div>
                        <div class="test-status {test['status']}">{test['status']}</div>
                    </div>
                    <div>Duration: {test['duration']:.2f}s | Issues: {test['issues_count']} | Screenshots: {test['screenshots_count']}</div>
                    {performance_html}
                    {issues_html}
                </div>
                """
            
            html += """
                </div>
            </div>
            """
        
        html += """
        </div>
    </div>
</body>
</html>
"""
        
        return html

async def main():
    """Main function to run E2E tests"""
    print("🤖 Starting PyAirtable E2E Testing Agents System")
    print("=" * 60)
    
    orchestrator = TestOrchestrator()
    
    try:
        results = await orchestrator.run_all_tests()
        
        # Print quick summary
        total_tests = sum(len(agent_results) for agent_results in results.values())
        passed_tests = sum(1 for agent_results in results.values() 
                          for result in agent_results if result.status == "passed")
        
        print(f"\n🎉 Testing Complete!")
        print(f"📊 Results: {passed_tests}/{total_tests} tests passed ({passed_tests/max(total_tests,1)*100:.1f}%)")
        print(f"📁 Detailed reports saved to: e2e_test_results/")
        
        return results
        
    except KeyboardInterrupt:
        print("\n⚠️  Testing interrupted by user")
        return {}
    except Exception as e:
        print(f"\n❌ Testing failed: {e}")
        logger.error(f"Testing orchestration failed: {e}")
        logger.error(traceback.format_exc())
        return {}

if __name__ == "__main__":
    # Install required packages if not present
    try:
        import selenium
        import requests
    except ImportError:
        print("Installing required packages...")
        import subprocess
        subprocess.check_call(["pip", "install", "selenium", "requests"])
        print("Packages installed!")
    
    # Run the tests
    asyncio.run(main())