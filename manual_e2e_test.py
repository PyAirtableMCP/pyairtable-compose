#!/usr/bin/env python3
"""
Manual E2E Test Script for PyAirtable Application

This script allows manual testing of individual scenarios
for debugging and development purposes.

Usage:
    python manual_e2e_test.py --scenario <scenario_number>
    python manual_e2e_test.py --all
    python manual_e2e_test.py --health-check
"""

import asyncio
import httpx
import json
import time
import argparse
from typing import Dict, Any


class ManualE2ETest:
    """Manual E2E testing utility"""
    
    def __init__(self):
        self.api_gateway_url = "http://localhost:8000"
        self.llm_orchestrator_url = "http://localhost:8003"
        self.mcp_server_url = "http://localhost:8001"
        self.airtable_gateway_url = "http://localhost:8002"
        self.airtable_base = "appVLUAubH5cFWhMV"
        self.airtable_api_key = "pya_d7f8e9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6"
        self.client = httpx.AsyncClient(timeout=60.0)
        self.session_id = None
    
    async def __aenter__(self):
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.client.aclose()
    
    async def health_check(self):
        """Check health of all services"""
        print("🏥 Checking service health...")
        
        services = {
            "API Gateway": f"{self.api_gateway_url}/api/health",
            "LLM Orchestrator": f"{self.llm_orchestrator_url}/health",
            "MCP Server": f"{self.mcp_server_url}/health",
            "Airtable Gateway": f"{self.airtable_gateway_url}/health"
        }
        
        for service_name, health_url in services.items():
            try:
                response = await self.client.get(health_url)
                if response.status_code == 200:
                    print(f"  ✅ {service_name}: Healthy")
                    if hasattr(response, 'json'):
                        try:
                            health_data = response.json()
                            print(f"     {json.dumps(health_data, indent=6)}")
                        except:
                            pass
                else:
                    print(f"  ❌ {service_name}: Unhealthy (Status: {response.status_code})")
            except Exception as e:
                print(f"  ❌ {service_name}: Unreachable ({str(e)})")
    
    async def send_chat_message(self, message: str) -> Dict[str, Any]:
        """Send a chat message through the API Gateway"""
        print(f"\n💬 Sending message: {message[:100]}{'...' if len(message) > 100 else ''}")
        
        chat_endpoint = f"{self.api_gateway_url}/api/chat"
        
        payload = {
            "messages": [
                {
                    "role": "user",
                    "content": f"I have an Airtable base with ID {self.airtable_base}. {message}"
                }
            ],
            "session_id": self.session_id or "manual_test_session"
        }
        
        headers = {
            "Content-Type": "application/json",
            "X-API-Key": self.airtable_api_key,
            "User-Agent": "PyAirtable-Manual-Test/1.0"
        }
        
        try:
            print("📤 Making request to API Gateway...")
            response = await self.client.post(chat_endpoint, json=payload, headers=headers)
            
            print(f"📥 Response Status: {response.status_code}")
            
            if response.status_code == 200:
                result = response.json()
                if "session_id" in result and not self.session_id:
                    self.session_id = result["session_id"]
                    print(f"🔗 Session ID: {self.session_id}")
                
                return result
            else:
                print(f"❌ Request failed: {response.text}")
                return {"error": f"HTTP {response.status_code}", "details": response.text}
                
        except Exception as e:
            print(f"❌ Request exception: {str(e)}")
            return {"error": "exception", "details": str(e)}
    
    async def test_scenario_1(self):
        """Test Facebook posts analysis"""
        print("\n" + "="*60)
        print("📋 SCENARIO 1: Facebook Posts Analysis")
        print("="*60)
        
        message = (
            "Notice the facebook posts table in my Airtable base. Please analyze it, "
            "recommend improvements for each existing post, and come up with 2 to 5 new "
            "post ideas that would fit well."
        )
        
        result = await self.send_chat_message(message)
        
        if "response" in result:
            print(f"\n✅ Response received ({len(result['response'])} characters):")
            print("-" * 40)
            print(result["response"])
            print("-" * 40)
            if "session_id" in result:
                print(f"Session ID: {result['session_id']}")
        else:
            print(f"\n❌ No response received: {result}")
    
    async def test_scenario_2(self):
        """Test metadata table creation"""
        print("\n" + "="*60)
        print("📋 SCENARIO 2: Metadata Table Creation")
        print("="*60)
        
        message = (
            "Create a metadata table that describes all tables in my Airtable base "
            "with their purpose and key fields"
        )
        
        result = await self.send_chat_message(message)
        
        if "response" in result:
            print(f"\n✅ Response received ({len(result['response'])} characters):")
            print("-" * 40)
            print(result["response"])
            print("-" * 40)
            if "session_id" in result:
                print(f"Session ID: {result['session_id']}")
        else:
            print(f"\n❌ No response received: {result}")
    
    async def test_scenario_3(self):
        """Test working hours calculation"""
        print("\n" + "="*60)
        print("📋 SCENARIO 3: Working Hours Calculation")
        print("="*60)
        
        message = (
            "Show me the working hours table and calculate total hours worked per project"
        )
        
        result = await self.send_chat_message(message)
        
        if "response" in result:
            print(f"\n✅ Response received ({len(result['response'])} characters):")
            print("-" * 40)
            print(result["response"])
            print("-" * 40)
            if "session_id" in result:
                print(f"Session ID: {result['session_id']}")
        else:
            print(f"\n❌ No response received: {result}")
    
    async def test_scenario_4(self):
        """Test projects status and expenses"""
        print("\n" + "="*60)
        print("📋 SCENARIO 4: Projects Status and Expenses")
        print("="*60)
        
        message = (
            "List all projects with their current status and expenses"
        )
        
        result = await self.send_chat_message(message)
        
        if "response" in result:
            print(f"\n✅ Response received ({len(result['response'])} characters):")
            print("-" * 40)
            print(result["response"])
            print("-" * 40)
            if "session_id" in result:
                print(f"Session ID: {result['session_id']}")
        else:
            print(f"\n❌ No response received: {result}")
    
    async def test_gemini_connection(self):
        """Test basic Gemini connection"""
        print("\n" + "="*60)
        print("🤖 GEMINI CONNECTION TEST")
        print("="*60)
        
        message = (
            "Hello! Can you tell me what AI model you are and confirm you can "
            "access my Airtable data? Please keep your response brief."
        )
        
        result = await self.send_chat_message(message)
        
        if "response" in result:
            print(f"\n✅ Gemini response received ({len(result['response'])} characters):")
            print("-" * 40)
            print(result["response"])
            print("-" * 40)
        else:
            print(f"\n❌ No response received: {result}")
    
    async def run_all_scenarios(self):
        """Run all test scenarios"""
        print("🚀 Running all test scenarios...")
        
        await self.health_check()
        await self.test_gemini_connection()
        await self.test_scenario_1()
        await self.test_scenario_2()
        await self.test_scenario_3()
        await self.test_scenario_4()
        
        print("\n🏁 All scenarios completed!")


async def main():
    """Main function"""
    parser = argparse.ArgumentParser(description="Manual E2E Test for PyAirtable")
    parser.add_argument("--scenario", type=int, choices=[1, 2, 3, 4], 
                       help="Run specific scenario (1-4)")
    parser.add_argument("--all", action="store_true", help="Run all scenarios")
    parser.add_argument("--health-check", action="store_true", help="Run health check only")
    parser.add_argument("--gemini-test", action="store_true", help="Test Gemini connection only")
    
    args = parser.parse_args()
    
    if not any([args.scenario, args.all, args.health_check, args.gemini_test]):
        parser.print_help()
        return
    
    async with ManualE2ETest() as test:
        try:
            if args.health_check:
                await test.health_check()
            elif args.gemini_test:
                await test.test_gemini_connection()
            elif args.scenario:
                await test.health_check()
                if args.scenario == 1:
                    await test.test_scenario_1()
                elif args.scenario == 2:
                    await test.test_scenario_2()
                elif args.scenario == 3:
                    await test.test_scenario_3()
                elif args.scenario == 4:
                    await test.test_scenario_4()
            elif args.all:
                await test.run_all_scenarios()
                
        except KeyboardInterrupt:
            print("\n\n⚠️ Test interrupted by user")
        except Exception as e:
            print(f"\n❌ Test failed with error: {str(e)}")


if __name__ == "__main__":
    asyncio.run(main())