#!/usr/bin/env python3
"""
Script to fix the main.py file by removing trace_id parameter from ChatHandler call
"""

import subprocess
import tempfile
import os

def fix_main_py():
    """Fix the main.py file to remove trace_id parameter"""
    
    try:
        # Stop the container first to avoid issues
        subprocess.run(["docker", "stop", "pyairtable-compose-llm-orchestrator-1"], check=True)
        
        # First restore the handler.py from backup
        subprocess.run([
            "docker", "start", "pyairtable-compose-llm-orchestrator-1"
        ], check=True)
        
        # Wait a moment for container to start
        subprocess.run(["sleep", "3"], check=True)
        
        # Restore handler.py from backup
        subprocess.run([
            "docker", "exec", "pyairtable-compose-llm-orchestrator-1",
            "cp", "/app/src/chat/handler.py.backup", "/app/src/chat/handler.py"
        ], check=True)
        
        print("✅ Restored handler.py from backup")
        
        # Get the current main.py content  
        result = subprocess.run([
            "docker", "exec", "pyairtable-compose-llm-orchestrator-1", 
            "cat", "/app/src/main.py"
        ], capture_output=True, text=True, check=True)
        
        original_content = result.stdout
        
        # Fix the problematic line - remove trace_id parameter
        fixed_content = original_content.replace(
            "return await chat_handler.handle_chat_request(request, trace_id=trace_id)",
            "return await chat_handler.handle_chat_request(request)"
        )
        
        # Create a temporary file with the fix
        with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
            f.write(fixed_content)
            temp_file = f.name
        
        # Copy the fixed file to the container
        subprocess.run([
            "docker", "cp", temp_file, 
            "pyairtable-compose-llm-orchestrator-1:/app/src/main.py"
        ], check=True)
        
        print("✅ Applied fix to main.py")
        
        # Clean up temp file
        os.unlink(temp_file)
        
        # Restart the container to apply changes
        print("🔄 Restarting LLM orchestrator container...")
        subprocess.run([
            "docker", "restart", "pyairtable-compose-llm-orchestrator-1"
        ], check=True)
        
        print("✅ Container restarted successfully")
        print("\n🎉 Fix applied! The main.py no longer passes trace_id to ChatHandler.")
        print("\nTo test the fix:")
        print("1. Wait a few seconds for the container to start up")
        print("2. Make a test request to /chat endpoint") 
        print("3. Check the logs to verify no more TypeError")
        
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"❌ Error applying fix: {e}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

if __name__ == "__main__":
    print("🔧 Fixing main.py trace_id parameter issue...")
    success = fix_main_py()
    if success:
        print("\n✅ Fix completed successfully!")
    else:
        print("\n❌ Fix failed!")