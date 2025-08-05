#!/usr/bin/env python3
"""
API Connectivity Test for PyAirtable
Tests connectivity to external APIs (Airtable, Gemini) using the deployed services
"""

import asyncio
import httpx
import json
import os
import subprocess
from typing import Dict, Any
import time

class APIConnectivityTester:
    def __init__(self):
        # Load environment variables
        self.load_env_vars()
        
        self.services = {
            "airtable-gateway": {"port": 8002},
            "llm-orchestrator": {"port": 8003},
            "mcp-server": {"port": 8001}
        }
        self.port_forwards = []
        
    def load_env_vars(self):
        """Load environment variables from .env file"""
        env_vars = {}
        try:
            with open('.env', 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        env_vars[key.strip()] = value.strip()
            
            self.airtable_token = env_vars.get('AIRTABLE_TOKEN', '')
            self.gemini_api_key = env_vars.get('GEMINI_API_KEY', '')
            self.airtable_base = env_vars.get('AIRTABLE_BASE', '')
            self.api_key = env_vars.get('API_KEY', '')
            
            print(f"🔑 Loaded API keys:")
            print(f"  Airtable Token: {'✅ Present' if self.airtable_token else '❌ Missing'} ({len(self.airtable_token)} chars)")
            print(f"  Gemini API Key: {'✅ Present' if self.gemini_api_key else '❌ Missing'} ({len(self.gemini_api_key)} chars)")
            print(f"  Airtable Base: {'✅ Present' if self.airtable_base else '❌ Missing'} ({self.airtable_base})")
            print(f"  Internal API Key: {'✅ Present' if self.api_key else '❌ Missing'}")
            
        except Exception as e:
            print(f"❌ Error loading .env file: {e}")
            self.airtable_token = ''
            self.gemini_api_key = ''
            self.airtable_base = ''
            self.api_key = ''
    
    async def setup_port_forwarding(self):
        """Set up port forwarding for testing services"""
        print("🔗 Setting up port forwarding for API tests...")
        
        for service, config in self.services.items():
            port = config["port"]
            cmd = f"kubectl port-forward -n pyairtable-dev service/{service} {port}:{port}"
            
            process = subprocess.Popen(
                cmd.split(),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            self.port_forwards.append(process)
        
        await asyncio.sleep(8)  # Wait for port forwards to establish
        
    def cleanup_port_forwarding(self):
        """Clean up port forwarding processes"""
        for process in self.port_forwards:
            process.terminate()
        subprocess.run(["pkill", "-f", "port-forward"], stderr=subprocess.DEVNULL)
    
    async def test_airtable_connectivity(self) -> Dict[str, Any]:
        """Test direct Airtable API connectivity"""
        print("🗂️  Testing Airtable API connectivity...")
        
        if not self.airtable_token or not self.airtable_base:
            return {
                "status": "skipped",
                "reason": "Missing Airtable credentials",
                "error": "AIRTABLE_TOKEN or AIRTABLE_BASE not configured"
            }
        
        try:
            # Test direct Airtable API access
            headers = {
                "Authorization": f"Bearer {self.airtable_token}",
                "Content-Type": "application/json"
            }
            
            # Get base schema information
            url = f"https://api.airtable.com/v0/meta/bases/{self.airtable_base}/tables"
            
            async with httpx.AsyncClient(timeout=30) as client:
                response = await client.get(url, headers=headers)
                
                if response.status_code == 200:
                    data = response.json()
                    tables = data.get("tables", [])
                    table_names = [table["name"] for table in tables]
                    
                    return {
                        "status": "success",
                        "tables_found": len(tables),
                        "table_names": table_names[:5],  # First 5 tables
                        "response_time_ms": None
                    }
                else:
                    return {
                        "status": "failed",
                        "status_code": response.status_code,
                        "error": response.text[:200]
                    }
                    
        except Exception as e:
            return {
                "status": "error",
                "error": str(e)
            }
    
    async def test_gemini_connectivity(self) -> Dict[str, Any]:
        """Test Gemini API connectivity through LLM orchestrator"""
        print("🤖 Testing Gemini API connectivity...")
        
        if not self.gemini_api_key:
            return {
                "status": "skipped",
                "reason": "Missing Gemini API key",
                "error": "GEMINI_API_KEY not configured"
            }
        
        try:
            # Test basic Gemini API connectivity
            headers = {
                "Content-Type": "application/json"
            }
            
            # Simple test request to Gemini
            url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={self.gemini_api_key}"
            
            payload = {
                "contents": [{
                    "parts": [{
                        "text": "Hello! Please respond with exactly: 'Gemini API is working'"
                    }]
                }]
            }
            
            async with httpx.AsyncClient(timeout=30) as client:
                response = await client.post(url, headers=headers, json=payload)
                
                if response.status_code == 200:
                    data = response.json()
                    candidates = data.get("candidates", [])
                    if candidates:
                        response_text = candidates[0]["content"]["parts"][0]["text"]
                        return {
                            "status": "success",
                            "response": response_text.strip(),
                            "working": "Gemini API is working" in response_text
                        }
                    else:
                        return {
                            "status": "failed",
                            "error": "No response candidates found"
                        }
                else:
                    return {
                        "status": "failed",
                        "status_code": response.status_code,
                        "error": response.text[:200]
                    }
                    
        except Exception as e:
            return {
                "status": "error",
                "error": str(e)
            }
    
    async def test_mcp_functionality(self) -> Dict[str, Any]:
        """Test MCP server functionality"""
        print("🔧 Testing MCP server functionality...")
        
        try:
            # Test MCP server health and basic endpoints
            url = "http://localhost:8001"
            
            async with httpx.AsyncClient(timeout=10) as client:
                # Test health endpoint
                health_response = await client.get(f"{url}/health")
                
                if health_response.status_code == 200:
                    # Test root endpoint
                    root_response = await client.get(url)
                    
                    return {
                        "status": "success",
                        "health_check": health_response.json(),
                        "root_response": root_response.json() if root_response.status_code == 200 else root_response.text,
                        "mcp_server_ready": True
                    }
                else:
                    return {
                        "status": "failed",
                        "error": f"Health check failed: {health_response.status_code}"
                    }
                    
        except Exception as e:
            return {
                "status": "error",
                "error": str(e)
            }
    
    async def test_integration_scenario(self) -> Dict[str, Any]:
        """Test a simple integration scenario"""
        print("🔄 Testing basic integration scenario...")
        
        try:
            # Test platform services chat endpoint with a simple query
            url = "http://localhost:8007/api/chat"
            
            # Simple chat request
            payload = {
                "message": "Hello, can you confirm the system is working?",
                "session_id": "test_session"
            }
            
            headers = {
                "Content-Type": "application/json",
                "X-API-Key": self.api_key
            }
            
            async with httpx.AsyncClient(timeout=15) as client:
                response = await client.post(url, json=payload, headers=headers)
                
                return {
                    "status": "success" if response.status_code == 200 else "failed",
                    "status_code": response.status_code,
                    "response": response.json() if response.status_code == 200 else response.text[:200],
                    "integration_working": response.status_code == 200
                }
                
        except Exception as e:
            return {
                "status": "error",
                "error": str(e)
            }
    
    async def run_connectivity_tests(self) -> Dict[str, Any]:
        """Run all API connectivity tests"""
        print("🚀 Starting PyAirtable API Connectivity Tests")
        print("=" * 60)
        
        start_time = time.time()
        
        # Set up port forwarding
        await self.setup_port_forwarding()
        
        try:
            # Run all tests
            results = {
                "timestamp": int(time.time()),
                "airtable_connectivity": await self.test_airtable_connectivity(),
                "gemini_connectivity": await self.test_gemini_connectivity(),
                "mcp_functionality": await self.test_mcp_functionality(),
                "integration_scenario": await self.test_integration_scenario()
            }
            
            # Calculate summary
            tests_run = 0
            tests_passed = 0
            
            for test_name, test_result in results.items():
                if test_name == "timestamp":
                    continue
                    
                tests_run += 1
                if test_result["status"] == "success":
                    tests_passed += 1
            
            end_time = time.time()
            
            results["summary"] = {
                "total_tests": tests_run,
                "passed_tests": tests_passed,
                "success_rate": round((tests_passed / tests_run) * 100, 1) if tests_run > 0 else 0,
                "duration_seconds": round(end_time - start_time, 2),
                "overall_status": "success" if tests_passed == tests_run else "partial"
            }
            
            return results
            
        finally:
            self.cleanup_port_forwarding()
    
    def print_results(self, results: Dict[str, Any]):
        """Print test results in a readable format"""
        print("\n" + "=" * 60)
        print("🎯 API CONNECTIVITY TEST RESULTS")
        print("=" * 60)
        
        summary = results["summary"]
        status_emoji = "✅" if summary["overall_status"] == "success" else "⚠️"
        
        print(f"\n{status_emoji} Overall Status: {summary['overall_status'].upper()}")
        print(f"📊 Success Rate: {summary['success_rate']}% ({summary['passed_tests']}/{summary['total_tests']} tests)")
        print(f"⏱️  Test Duration: {summary['duration_seconds']}s")
        
        # Individual test results
        print(f"\n📋 Test Results:")
        
        # Airtable connectivity
        airtable = results["airtable_connectivity"]
        if airtable["status"] == "success":
            print(f"  ✅ Airtable API: Connected successfully")
            print(f"     Found {airtable['tables_found']} tables: {', '.join(airtable['table_names'])}")
        elif airtable["status"] == "skipped":
            print(f"  ⏭️  Airtable API: Skipped ({airtable['reason']})")
        else:
            print(f"  ❌ Airtable API: {airtable['status']}")
            if airtable.get('error'):
                print(f"     Error: {airtable['error']}")
        
        # Gemini connectivity
        gemini = results["gemini_connectivity"]
        if gemini["status"] == "success":
            print(f"  ✅ Gemini API: Connected successfully")
            print(f"     Response: {gemini['response'][:50]}...")
        elif gemini["status"] == "skipped":
            print(f"  ⏭️  Gemini API: Skipped ({gemini['reason']})")
        else:
            print(f"  ❌ Gemini API: {gemini['status']}")
            if gemini.get('error'):
                print(f"     Error: {gemini['error']}")
        
        # MCP functionality
        mcp = results["mcp_functionality"]
        if mcp["status"] == "success":
            print(f"  ✅ MCP Server: Functional")
        else:
            print(f"  ❌ MCP Server: {mcp['status']}")
            if mcp.get('error'):
                print(f"     Error: {mcp['error']}")
        
        # Integration scenario
        integration = results["integration_scenario"]
        if integration["status"] == "success":
            print(f"  ✅ Integration: Working")
        else:
            print(f"  ❌ Integration: {integration['status']}")
            if integration.get('error'):
                print(f"     Error: {integration['error']}")
        
        # Recommendations
        print(f"\n💡 Recommendations:")
        if summary["overall_status"] == "success":
            print("  🎉 All APIs are connected and ready for production use!")
            print("  🚀 Deploy to staging/production environment")
            print("  📊 Monitor API usage and performance")
        else:
            print("  🔧 Fix API connectivity issues before production")
            print("  🔑 Verify API keys and permissions")
            print("  🌐 Check network connectivity and firewalls")


async def main():
    """Main test function"""
    tester = APIConnectivityTester()
    
    try:
        results = await tester.run_connectivity_tests()
        tester.print_results(results)
        
        # Save results
        results_file = "tests/reports/api_connectivity_results.json"
        os.makedirs(os.path.dirname(results_file), exist_ok=True)
        
        with open(results_file, "w") as f:
            json.dump(results, f, indent=2)
        
        print(f"\n📄 Results saved to: {results_file}")
        
        return 0 if results["summary"]["overall_status"] == "success" else 1
        
    except Exception as e:
        print(f"\n❌ API connectivity tests failed: {e}")
        return 1


if __name__ == "__main__":
    import sys
    exit_code = asyncio.run(main())
    sys.exit(exit_code)