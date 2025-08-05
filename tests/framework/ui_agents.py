"""
Synthetic UI Agents for PyAirtable Integration Testing
======================================================

This module provides AI-powered synthetic agents that can interact with the PyAirtable
application like real users, performing comprehensive end-to-end testing with Playwright.
"""

import asyncio
import json
import logging
import time
import traceback
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple, Union
import uuid
import random

from playwright.async_api import async_playwright, Browser, BrowserContext, Page, Response
from playwright.async_api import TimeoutError as PlaywrightTimeoutError

from .test_config import TestFrameworkConfig, get_config
from .test_reporter import TestResult, TestReport

logger = logging.getLogger(__name__)

class UIAgentAction:
    """Represents a UI action performed by an agent"""
    
    def __init__(self, action_type: str, target: str, value: Any = None, 
                 description: str = "", metadata: Dict = None):
        self.action_type = action_type
        self.target = target
        self.value = value
        self.description = description
        self.metadata = metadata or {}
        self.timestamp = datetime.now()
        self.duration = 0.0
        self.success = False
        self.error_message = ""
        self.screenshot_path = ""

class SyntheticUIAgent:
    """Base class for synthetic UI agents that can interact with the application"""
    
    def __init__(self, name: str, config: TestFrameworkConfig = None):
        self.name = name
        self.config = config or get_config()
        self.browser: Optional[Browser] = None
        self.context: Optional[BrowserContext] = None
        self.page: Optional[Page] = None
        self.actions_performed: List[UIAgentAction] = []
        self.test_session_id = f"{name.lower().replace(' ', '_')}_{uuid.uuid4().hex[:8]}"
        
        # Agent state
        self.current_url = ""
        self.session_data = {}
        
        # Test results
        self.test_results: List[TestResult] = []
        
        # Screenshots and traces directory
        self.artifacts_dir = Path("test-results") / "ui-agents" / self.test_session_id
        self.artifacts_dir.mkdir(parents=True, exist_ok=True)
    
    async def __aenter__(self):
        """Async context manager entry"""
        await self.initialize()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit"""
        await self.cleanup()
    
    async def initialize(self):
        """Initialize the browser and context"""
        try:
            playwright = await async_playwright().start()
            
            # Launch browser
            browser_type = getattr(playwright, self.config.browser.browser_type)
            self.browser = await browser_type.launch(
                headless=self.config.browser.headless,
                slow_mo=self.config.browser.slow_mo,
                args=['--disable-web-security', '--disable-features=VizDisplayCompositor']
            )
            
            # Create context
            context_options = {
                'viewport': {
                    'width': self.config.browser.viewport_width,
                    'height': self.config.browser.viewport_height
                },
                'ignore_https_errors': True,
                'record_video_dir': str(self.artifacts_dir / "videos") if self.config.browser.video else None,
                'record_har_path': str(self.artifacts_dir / "network.har")
            }
            
            self.context = await self.browser.new_context(**context_options)
            
            # Enable tracing if configured
            if self.config.browser.trace or self.config.save_traces:
                await self.context.tracing.start(screenshots=True, snapshots=True, sources=True)
            
            # Create page
            self.page = await self.context.new_page()
            
            # Set up event listeners
            self.page.on("console", self._handle_console_message)
            self.page.on("pageerror", self._handle_page_error)
            self.page.on("requestfailed", self._handle_request_failed)
            
            logger.info(f"Agent {self.name} initialized successfully")
            
        except Exception as e:
            logger.error(f"Failed to initialize agent {self.name}: {e}")
            await self.cleanup()
            raise
    
    async def cleanup(self):
        """Cleanup browser resources"""
        try:
            # Save trace if enabled
            if self.context and (self.config.browser.trace or self.config.save_traces):
                trace_path = self.artifacts_dir / "trace.zip"
                await self.context.tracing.stop(path=str(trace_path))
            
            # Close browser
            if self.browser:
                await self.browser.close()
                
            logger.info(f"Agent {self.name} cleaned up successfully")
            
        except Exception as e:
            logger.error(f"Error during cleanup for agent {self.name}: {e}")
    
    def _handle_console_message(self, msg):
        """Handle console messages from the page"""
        if msg.type == "error":
            logger.warning(f"Console error on {self.current_url}: {msg.text}")
            # Add to current test result if available
            if self.test_results:
                self.test_results[-1].add_issue(
                    "medium", "Console Error", msg.text, "browser_console"
                )
    
    def _handle_page_error(self, error):
        """Handle uncaught page errors"""
        logger.error(f"Page error on {self.current_url}: {error}")
        if self.test_results:
            self.test_results[-1].add_issue(
                "high", "Page Error", str(error), "page_error"
            )
    
    def _handle_request_failed(self, request):
        """Handle failed network requests"""
        logger.warning(f"Request failed: {request.method} {request.url} - {request.failure}")
        if self.test_results:
            self.test_results[-1].add_issue(
                "medium", "Network Request Failed", 
                f"{request.method} {request.url}: {request.failure}",
                "network_request"
            )
    
    async def perform_action(self, action: UIAgentAction) -> bool:
        """Perform a UI action and record the result"""
        start_time = time.time()
        
        try:
            logger.info(f"Agent {self.name} performing action: {action.description}")
            
            success = await self._execute_action(action)
            
            action.duration = time.time() - start_time
            action.success = success
            
            # Take screenshot if configured or if action failed
            if self.config.save_screenshots or (not success and self.config.browser.screenshot_on_failure):
                screenshot_path = await self._take_screenshot(f"action_{len(self.actions_performed)}")
                action.screenshot_path = screenshot_path
            
            self.actions_performed.append(action)
            
            if success:
                logger.info(f"Action completed successfully in {action.duration:.2f}s")
            else:
                logger.warning(f"Action failed in {action.duration:.2f}s: {action.error_message}")
            
            return success
            
        except Exception as e:
            action.duration = time.time() - start_time
            action.success = False
            action.error_message = str(e)
            self.actions_performed.append(action)
            
            logger.error(f"Action failed with exception: {e}")
            return False
    
    async def _execute_action(self, action: UIAgentAction) -> bool:
        """Execute the actual UI action"""
        try:
            if action.action_type == "navigate":
                await self.page.goto(action.target, wait_until="networkidle")
                self.current_url = action.target
                return True
                
            elif action.action_type == "click":
                await self.page.click(action.target)
                return True
                
            elif action.action_type == "fill":
                await self.page.fill(action.target, str(action.value))
                return True
                
            elif action.action_type == "type":
                await self.page.type(action.target, str(action.value))
                return True
                
            elif action.action_type == "press":
                await self.page.press(action.target, str(action.value))
                return True
                
            elif action.action_type == "wait_for_selector":
                await self.page.wait_for_selector(action.target, timeout=action.metadata.get("timeout", 5000))
                return True
                
            elif action.action_type == "wait_for_response":
                await self.page.wait_for_response(action.target, timeout=action.metadata.get("timeout", 30000))
                return True
                
            elif action.action_type == "evaluate":
                result = await self.page.evaluate(action.target)
                action.metadata["result"] = result
                return True
                
            elif action.action_type == "hover":
                await self.page.hover(action.target)
                return True
                
            elif action.action_type == "select_option":
                await self.page.select_option(action.target, action.value)
                return True
                
            elif action.action_type == "upload_file":
                await self.page.set_input_files(action.target, action.value)
                return True
                
            elif action.action_type == "drag_and_drop":
                source, target = action.value
                await self.page.drag_and_drop(source, target)
                return True
                
            elif action.action_type == "scroll":
                await self.page.evaluate(f"window.scrollTo({action.value[0]}, {action.value[1]})")
                return True
                
            elif action.action_type == "wait":
                await asyncio.sleep(action.value)
                return True
                
            else:
                action.error_message = f"Unknown action type: {action.action_type}"
                return False
                
        except PlaywrightTimeoutError as e:
            action.error_message = f"Timeout: {str(e)}"
            return False
        except Exception as e:
            action.error_message = str(e)
            return False
    
    async def _take_screenshot(self, name: str) -> str:
        """Take a screenshot and return the path"""
        try:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            screenshot_path = self.artifacts_dir / f"{timestamp}_{name}.png"
            await self.page.screenshot(path=str(screenshot_path), full_page=True)
            return str(screenshot_path)
        except Exception as e:
            logger.error(f"Failed to take screenshot: {e}")
            return ""
    
    async def wait_for_element(self, selector: str, timeout: int = 5000) -> bool:
        """Wait for an element to be visible"""
        action = UIAgentAction(
            "wait_for_selector", selector, 
            description=f"Wait for element {selector}",
            metadata={"timeout": timeout}
        )
        return await self.perform_action(action)
    
    async def navigate_to(self, url: str) -> bool:
        """Navigate to a URL"""
        action = UIAgentAction(
            "navigate", url, 
            description=f"Navigate to {url}"
        )
        return await self.perform_action(action)
    
    async def click_element(self, selector: str, description: str = "") -> bool:
        """Click an element"""
        action = UIAgentAction(
            "click", selector, 
            description=description or f"Click {selector}"
        )
        return await self.perform_action(action)
    
    async def fill_input(self, selector: str, value: str, description: str = "") -> bool:
        """Fill an input field"""
        action = UIAgentAction(
            "fill", selector, value,
            description=description or f"Fill {selector} with '{value}'"
        )
        return await self.perform_action(action)
    
    async def type_text(self, selector: str, text: str, description: str = "") -> bool:
        """Type text into an element"""
        action = UIAgentAction(
            "type", selector, text,
            description=description or f"Type '{text}' into {selector}"
        )
        return await self.perform_action(action)
    
    async def get_text_content(self, selector: str) -> Optional[str]:
        """Get text content of an element"""
        try:
            return await self.page.text_content(selector)
        except Exception as e:
            logger.error(f"Failed to get text content for {selector}: {e}")
            return None
    
    async def get_attribute(self, selector: str, attribute: str) -> Optional[str]:
        """Get attribute value of an element"""
        try:
            return await self.page.get_attribute(selector, attribute)
        except Exception as e:
            logger.error(f"Failed to get attribute {attribute} for {selector}: {e}")
            return None
    
    async def is_visible(self, selector: str) -> bool:
        """Check if an element is visible"""
        try:
            return await self.page.is_visible(selector)
        except Exception:
            return False
    
    async def is_enabled(self, selector: str) -> bool:
        """Check if an element is enabled"""
        try:
            return await self.page.is_enabled(selector)
        except Exception:
            return False
    
    async def wait_for_network_idle(self, timeout: int = 30000):
        """Wait for network to be idle"""
        try:
            await self.page.wait_for_load_state("networkidle", timeout=timeout)
        except PlaywrightTimeoutError:
            logger.warning("Network idle timeout reached")
    
    async def analyze_page_accessibility(self) -> Dict[str, Any]:
        """Analyze page for accessibility issues"""
        try:
            # Check for basic accessibility issues
            accessibility_report = {
                "missing_alt_text": [],
                "missing_labels": [],
                "low_contrast": [],
                "missing_headings": False,
                "missing_landmarks": False
            }
            
            # Check for images without alt text
            images = await self.page.query_selector_all("img")
            for img in images:
                alt = await img.get_attribute("alt")
                src = await img.get_attribute("src")
                if not alt:
                    accessibility_report["missing_alt_text"].append(src or "unknown")
            
            # Check for form inputs without labels
            inputs = await self.page.query_selector_all("input[type='text'], input[type='email'], textarea")
            for input_elem in inputs:
                label_id = await input_elem.get_attribute("id")
                aria_label = await input_elem.get_attribute("aria-label")
                if not aria_label and label_id:
                    label = await self.page.query_selector(f"label[for='{label_id}']")
                    if not label:
                        accessibility_report["missing_labels"].append(label_id or "unknown")
            
            # Check for headings
            headings = await self.page.query_selector_all("h1, h2, h3, h4, h5, h6")
            accessibility_report["missing_headings"] = len(headings) == 0
            
            # Check for landmarks
            landmarks = await self.page.query_selector_all("main, nav, header, footer, aside, section[aria-label]")
            accessibility_report["missing_landmarks"] = len(landmarks) == 0
            
            return accessibility_report
            
        except Exception as e:
            logger.error(f"Failed to analyze accessibility: {e}")
            return {}
    
    async def analyze_page_performance(self) -> Dict[str, Any]:
        """Analyze page performance metrics"""
        try:
            # Get navigation timing
            timing = await self.page.evaluate("""
                () => {
                    const timing = performance.timing;
                    return {
                        loadTime: timing.loadEventEnd - timing.navigationStart,
                        domContentLoaded: timing.domContentLoadedEventEnd - timing.navigationStart,
                        firstByte: timing.responseStart - timing.navigationStart,
                        domInteractive: timing.domInteractive - timing.navigationStart
                    };
                }
            """)
            
            # Get resource counts
            resources = await self.page.evaluate("""
                () => {
                    const resources = performance.getEntriesByType('resource');
                    return {
                        total: resources.length,
                        scripts: resources.filter(r => r.initiatorType === 'script').length,
                        stylesheets: resources.filter(r => r.initiatorType === 'link').length,
                        images: resources.filter(r => r.initiatorType === 'img').length,
                        xhr: resources.filter(r => r.initiatorType === 'xmlhttprequest').length
                    };
                }
            """)
            
            return {
                "timing": timing,
                "resources": resources
            }
            
        except Exception as e:
            logger.error(f"Failed to analyze performance: {e}")
            return {}

class ChatInterfaceAgent(SyntheticUIAgent):
    """Specialized agent for testing chat interface functionality"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        super().__init__("Chat Interface Agent", config)
    
    async def test_chat_functionality(self) -> TestResult:
        """Test complete chat functionality"""
        result = TestResult("Chat Interface Agent", "Chat Functionality Test")
        
        try:
            # Navigate to frontend
            frontend_url = self.config.services["frontend"].url
            success = await self.navigate_to(frontend_url)
            
            if not success:
                result.add_issue("critical", "Navigation Failed", f"Could not navigate to {frontend_url}")
                result.complete("failed")
                return result
            
            result.add_log("info", "Successfully navigated to frontend")
            
            # Wait for page to load
            await self.wait_for_network_idle()
            
            # Look for chat interface elements
            chat_elements = {
                "message_input": "#messageInput, [data-testid='message-input'], input[placeholder*='message']",
                "send_button": "#sendButton, [data-testid='send-button'], button[type='submit']",
                "chat_container": ".chat-container, [data-testid='chat-container'], .messages"
            }
            
            # Verify chat interface elements are present
            missing_elements = []
            for element_name, selector in chat_elements.items():
                is_visible = await self.is_visible(selector)
                if not is_visible:
                    missing_elements.append(element_name)
                else:
                    result.add_log("info", f"Found {element_name}")
            
            if missing_elements:
                result.add_issue("critical", "Missing Chat Elements", 
                               f"Missing elements: {', '.join(missing_elements)}")
                result.complete("failed")
                return result
            
            # Test sending a message
            test_message = "Hello, this is a test message from the synthetic UI agent. Can you help me analyze my Airtable data?"
            
            # Fill input
            success = await self.fill_input(
                chat_elements["message_input"], 
                test_message,
                "Fill chat input with test message"
            )
            
            if not success:
                result.add_issue("high", "Input Fill Failed", "Could not fill chat input")
                result.complete("failed")
                return result
            
            # Take screenshot before sending
            screenshot_path = await self._take_screenshot("before_send_message")
            if screenshot_path:
                result.add_screenshot(screenshot_path, "Chat interface before sending message")
            
            # Click send button
            success = await self.click_element(
                chat_elements["send_button"],
                "Click send button"
            )
            
            if not success:
                result.add_issue("high", "Send Button Failed", "Could not click send button")
                result.complete("failed")
                return result
            
            # Wait for message to appear and potential response
            await asyncio.sleep(2)
            
            # Check if user message appears
            user_messages = await self.page.query_selector_all(".message.user, [data-role='user'], .user-message")
            if user_messages:
                result.add_log("info", f"Found {len(user_messages)} user messages")
            else:
                result.add_issue("medium", "User Message Not Found", "User message did not appear in chat")
            
            # Wait for AI response (with timeout)
            response_timeout = 30  # seconds
            start_time = time.time()
            ai_response_found = False
            
            while time.time() - start_time < response_timeout:
                ai_messages = await self.page.query_selector_all(".message.assistant, [data-role='assistant'], .ai-message, .assistant-message")
                if len(ai_messages) > 0:  # Assuming there might be a welcome message
                    # Check if there's a new response
                    last_message_text = await ai_messages[-1].text_content()
                    if last_message_text and len(last_message_text) > 50:  # Substantial response
                        ai_response_found = True
                        result.add_log("info", f"AI response received: {last_message_text[:100]}...")
                        break
                
                await asyncio.sleep(1)
            
            if not ai_response_found:
                result.add_issue("high", "No AI Response", "AI did not respond to user message within timeout")
            
            # Take screenshot after interaction
            screenshot_path = await self._take_screenshot("after_send_message")
            if screenshot_path:
                result.add_screenshot(screenshot_path, "Chat interface after sending message")
            
            # Test example prompts if available
            example_prompts = await self.page.query_selector_all(".example-prompt, [data-testid='example-prompt']")
            if example_prompts:
                result.add_log("info", f"Found {len(example_prompts)} example prompts")
                
                # Click first example prompt
                if len(example_prompts) > 0:
                    await example_prompts[0].click()
                    await asyncio.sleep(1)
                    
                    # Check if input was populated
                    input_value = await self.get_attribute(chat_elements["message_input"], "value")
                    if input_value:
                        result.add_log("info", "Example prompt successfully populated input")
                    else:
                        result.add_issue("low", "Example Prompt Issue", "Example prompt did not populate input")
            
            # Analyze page performance
            performance_metrics = await self.analyze_page_performance()
            if performance_metrics:
                result.performance_metrics.update(performance_metrics)
            
            # Analyze accessibility
            accessibility_report = await self.analyze_page_accessibility()
            if accessibility_report:
                # Report accessibility issues
                for issue_type, issues in accessibility_report.items():
                    if isinstance(issues, list) and issues:
                        result.add_issue("medium", f"Accessibility: {issue_type}", 
                                       f"Found {len(issues)} instances")
                    elif isinstance(issues, bool) and issues:
                        result.add_issue("medium", f"Accessibility: {issue_type}", 
                                       "Accessibility issue detected")
            
            result.complete("passed" if not any(issue["severity"] in ["critical", "high"] for issue in result.issues_found) else "failed")
            
        except Exception as e:
            result.add_log("error", f"Chat functionality test failed: {e}")
            result.add_log("error", traceback.format_exc())
            result.complete("failed")
        
        self.test_results.append(result)
        return result
    
    async def test_responsive_design(self) -> TestResult:
        """Test responsive design across different screen sizes"""
        result = TestResult("Chat Interface Agent", "Responsive Design Test")
        
        screen_sizes = [
            ("Desktop", 1920, 1080),
            ("Tablet", 768, 1024),
            ("Mobile", 375, 667),
            ("Large Desktop", 2560, 1440)
        ]
        
        try:
            frontend_url = self.config.services["frontend"].url
            await self.navigate_to(frontend_url)
            
            for size_name, width, height in screen_sizes:
                result.add_log("info", f"Testing {size_name} size: {width}x{height}")
                
                # Set viewport size
                await self.page.set_viewport_size({"width": width, "height": height})
                await asyncio.sleep(2)  # Allow layout to adjust
                
                # Take screenshot
                screenshot_path = await self._take_screenshot(f"responsive_{size_name.lower().replace(' ', '_')}")
                if screenshot_path:
                    result.add_screenshot(screenshot_path, f"{size_name} responsive view")
                
                # Check if essential elements are still visible and accessible
                essential_elements = {
                    "message_input": "#messageInput, [data-testid='message-input'], input[placeholder*='message']",
                    "send_button": "#sendButton, [data-testid='send-button'], button[type='submit']"
                }
                
                for element_name, selector in essential_elements.items():
                    is_visible = await self.is_visible(selector)
                    is_enabled = await self.is_enabled(selector)
                    
                    if not is_visible:
                        result.add_issue("high", f"Element Hidden on {size_name}", 
                                       f"{element_name} not visible on {size_name} screen")
                    elif not is_enabled:
                        result.add_issue("medium", f"Element Disabled on {size_name}", 
                                       f"{element_name} not enabled on {size_name} screen")
                    else:
                        result.add_log("info", f"{size_name}: {element_name} is visible and enabled")
                
                # Check for horizontal scrolling (usually indicates responsive issues)
                scroll_info = await self.page.evaluate("""
                    () => ({
                        scrollWidth: document.body.scrollWidth,
                        clientWidth: document.documentElement.clientWidth,
                        hasHorizontalScroll: document.body.scrollWidth > document.documentElement.clientWidth
                    })
                """)
                
                if scroll_info["hasHorizontalScroll"]:
                    result.add_issue("medium", f"Horizontal Scroll on {size_name}", 
                                   f"Content width ({scroll_info['scrollWidth']}px) exceeds viewport ({scroll_info['clientWidth']}px)")
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Responsive design test failed: {e}")
            result.complete("failed")
        
        self.test_results.append(result)
        return result

class DataAnalysisAgent(SyntheticUIAgent):
    """Specialized agent for testing data analysis workflows"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        super().__init__("Data Analysis Agent", config)
    
    async def test_airtable_data_analysis(self) -> TestResult:
        """Test Airtable data analysis workflows"""
        result = TestResult("Data Analysis Agent", "Airtable Data Analysis Test")
        
        try:
            frontend_url = self.config.services["frontend"].url
            await self.navigate_to(frontend_url)
            await self.wait_for_network_idle()
            
            # Test various data analysis scenarios
            analysis_scenarios = [
                "Show me all tables in my Airtable base and their structure",
                "Analyze the Facebook posts table and provide recommendations",
                "Calculate total working hours by project from the working hours table",
                "List all projects with their current status and budget information",
                "Create a summary report of all data in my base"
            ]
            
            message_input_selector = "#messageInput, [data-testid='message-input'], input[placeholder*='message']"
            send_button_selector = "#sendButton, [data-testid='send-button'], button[type='submit']"
            
            for i, scenario in enumerate(analysis_scenarios):
                result.add_log("info", f"Testing scenario {i+1}: {scenario[:50]}...")
                
                # Fill and send message
                await self.fill_input(message_input_selector, scenario)
                await self.click_element(send_button_selector)
                
                # Wait for response
                response_found = False
                timeout = 45  # seconds
                start_time = time.time()
                
                while time.time() - start_time < timeout:
                    # Look for new assistant messages
                    ai_messages = await self.page.query_selector_all(
                        ".message.assistant, [data-role='assistant'], .ai-message"
                    )
                    
                    if len(ai_messages) > i:  # New message appeared
                        last_message = ai_messages[-1]
                        message_text = await last_message.text_content()
                        
                        if message_text and len(message_text) > 100:  # Substantial response
                            response_found = True
                            result.add_log("info", f"Scenario {i+1} response received ({len(message_text)} chars)")
                            
                            # Check for data-related keywords in response
                            data_keywords = ["table", "record", "field", "data", "analysis", "total", "project"]
                            keyword_count = sum(1 for keyword in data_keywords if keyword.lower() in message_text.lower())
                            
                            if keyword_count >= 3:
                                result.add_log("info", f"Response contains relevant data analysis content")
                            else:
                                result.add_issue("medium", "Response Quality", 
                                               f"Response may lack data analysis content (keywords: {keyword_count})")
                            break
                    
                    await asyncio.sleep(2)
                
                if not response_found:
                    result.add_issue("high", f"Scenario {i+1} Timeout", 
                                   f"No response received for: {scenario[:50]}...")
                
                # Take screenshot after each scenario
                screenshot_path = await self._take_screenshot(f"scenario_{i+1}")
                if screenshot_path:
                    result.add_screenshot(screenshot_path, f"After scenario {i+1}")
                
                # Small delay between scenarios
                await asyncio.sleep(2)
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Data analysis test failed: {e}")
            result.complete("failed")
        
        self.test_results.append(result)
        return result

class PerformanceTestingAgent(SyntheticUIAgent):
    """Specialized agent for performance testing"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        super().__init__("Performance Testing Agent", config)
    
    async def test_page_load_performance(self) -> TestResult:
        """Test page load performance metrics"""
        result = TestResult("Performance Testing Agent", "Page Load Performance Test")
        
        try:
            frontend_url = self.config.services["frontend"].url
            
            # Measure page load times
            load_times = []
            for i in range(3):  # Test 3 times for average
                start_time = time.time()
                
                await self.navigate_to(frontend_url)
                await self.wait_for_network_idle()
                
                load_time = time.time() - start_time
                load_times.append(load_time)
                
                result.add_log("info", f"Load attempt {i+1}: {load_time:.2f}s")
                
                # Clear cache between attempts
                await self.context.clear_cookies()
            
            # Calculate statistics
            avg_load_time = sum(load_times) / len(load_times)
            max_load_time = max(load_times)
            min_load_time = min(load_times)
            
            result.performance_metrics.update({
                "avg_load_time": avg_load_time,
                "max_load_time": max_load_time,
                "min_load_time": min_load_time,
                "load_times": load_times
            })
            
            # Check against thresholds
            if avg_load_time > 5.0:
                result.add_issue("high", "Slow Page Load", 
                               f"Average load time {avg_load_time:.2f}s exceeds 5s threshold")
            elif avg_load_time > 3.0:
                result.add_issue("medium", "Moderate Page Load", 
                               f"Average load time {avg_load_time:.2f}s exceeds 3s threshold")
            
            # Get detailed performance metrics
            detailed_metrics = await self.analyze_page_performance()
            if detailed_metrics:
                result.performance_metrics.update(detailed_metrics)
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Performance test failed: {e}")
            result.complete("failed")
        
        self.test_results.append(result)
        return result
    
    async def test_chat_response_performance(self) -> TestResult:
        """Test chat response performance under different scenarios"""
        result = TestResult("Performance Testing Agent", "Chat Response Performance Test")
        
        try:
            frontend_url = self.config.services["frontend"].url
            await self.navigate_to(frontend_url)
            await self.wait_for_network_idle()
            
            # Test different types of messages and their response times
            test_scenarios = [
                ("Simple greeting", "Hello!"),
                ("Data query", "Show me my Airtable tables"),
                ("Complex analysis", "Analyze all my data and provide detailed insights with recommendations"),
                ("Multiple requests", "List all projects, calculate totals, and create a summary report")
            ]
            
            message_input_selector = "#messageInput, [data-testid='message-input'], input[placeholder*='message']"
            send_button_selector = "#sendButton, [data-testid='send-button'], button[type='submit']"
            
            for scenario_name, message in test_scenarios:
                result.add_log("info", f"Testing {scenario_name}")
                
                # Send message and measure response time
                await self.fill_input(message_input_selector, message)
                
                send_time = time.time()
                await self.click_element(send_button_selector)
                
                # Wait for response
                response_time = None
                timeout = 60  # seconds
                
                while time.time() - send_time < timeout:
                    ai_messages = await self.page.query_selector_all(
                        ".message.assistant, [data-role='assistant'], .ai-message"
                    )
                    
                    if ai_messages:
                        last_message = ai_messages[-1]
                        message_text = await last_message.text_content()
                        
                        if message_text and len(message_text) > 20:  # Substantial response
                            response_time = time.time() - send_time
                            result.add_log("info", f"{scenario_name} response time: {response_time:.2f}s")
                            break
                    
                    await asyncio.sleep(0.5)
                
                if response_time:
                    result.performance_metrics[f"{scenario_name.lower().replace(' ', '_')}_response_time"] = response_time
                    
                    # Check against performance thresholds
                    threshold = self.config.performance_threshold_ms / 1000  # Convert to seconds
                    if response_time > threshold:
                        result.add_issue("medium", f"Slow Response - {scenario_name}", 
                                       f"Response time {response_time:.2f}s exceeds {threshold}s threshold")
                else:
                    result.add_issue("high", f"No Response - {scenario_name}", 
                                   f"No response received within {timeout}s")
                
                # Small delay between tests
                await asyncio.sleep(2)
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Chat performance test failed: {e}")
            result.complete("failed")
        
        self.test_results.append(result)
        return result

class UITestOrchestrator:
    """Orchestrates UI testing agents and manages test execution"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        self.config = config or get_config()
        self.agents = []
        self.test_report = TestReport("UI Agent Test Suite")
    
    def add_agent(self, agent: SyntheticUIAgent):
        """Add an agent to the test suite"""
        self.agents.append(agent)
    
    async def run_all_tests(self) -> TestReport:
        """Run all agents and their tests"""
        logger.info("Starting UI agent test orchestration")
        
        # Create default agents if none added
        if not self.agents:
            self.agents = [
                ChatInterfaceAgent(self.config),
                DataAnalysisAgent(self.config),
                PerformanceTestingAgent(self.config)
            ]
        
        all_results = []
        
        if self.config.parallel_execution:
            # Run agents in parallel
            tasks = []
            for agent in self.agents:
                tasks.append(self._run_agent_tests(agent))
            
            agent_results = await asyncio.gather(*tasks, return_exceptions=True)
            
            for i, result in enumerate(agent_results):
                if isinstance(result, Exception):
                    logger.error(f"Agent {self.agents[i].name} failed: {result}")
                else:
                    all_results.extend(result)
        else:
            # Run agents sequentially
            for agent in self.agents:
                try:
                    agent_results = await self._run_agent_tests(agent)
                    all_results.extend(agent_results)
                except Exception as e:
                    logger.error(f"Agent {agent.name} failed: {e}")
        
        # Add all results to the test report
        for result in all_results:
            self.test_report.add_test_result(result)
        
        # Generate final report
        await self.test_report.generate_report()
        
        logger.info(f"UI agent tests completed. Total tests: {len(all_results)}")
        
        return self.test_report
    
    async def _run_agent_tests(self, agent: SyntheticUIAgent) -> List[TestResult]:
        """Run tests for a specific agent"""
        results = []
        
        async with agent:
            try:
                if isinstance(agent, ChatInterfaceAgent):
                    results.append(await agent.test_chat_functionality())
                    results.append(await agent.test_responsive_design())
                elif isinstance(agent, DataAnalysisAgent):
                    results.append(await agent.test_airtable_data_analysis())
                elif isinstance(agent, PerformanceTestingAgent):
                    results.append(await agent.test_page_load_performance())
                    results.append(await agent.test_chat_response_performance())
            
            except Exception as e:
                logger.error(f"Error running tests for agent {agent.name}: {e}")
                # Create error result
                error_result = TestResult(agent.name, "Agent Execution")
                error_result.add_log("error", f"Agent execution failed: {e}")
                error_result.complete("failed")
                results.append(error_result)
        
        return results