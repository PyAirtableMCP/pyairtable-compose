#!/usr/bin/env python3
"""
Simple fix for the trace_id parameter issue
"""

import subprocess
import tempfile
import os

def simple_fix():
    """Apply simple fix by removing trace_id parameter from main.py"""
    
    try:
        # Get the current main.py content  
        result = subprocess.run([
            "docker", "exec", "pyairtable-compose-llm-orchestrator-1", 
            "cat", "/app/src/main.py"
        ], capture_output=True, text=True, check=True)
        
        original_content = result.stdout
        print("✅ Retrieved main.py content")
        
        # Fix the problematic line - remove trace_id parameter
        fixed_content = original_content.replace(
            "return await chat_handler.handle_chat_request(request, trace_id=trace_id)",
            "return await chat_handler.handle_chat_request(request)"
        )
        
        # Verify the change was made
        if fixed_content == original_content:
            print("❌ No changes made - pattern not found")
            return False
            
        print("✅ Pattern found and replaced")
        
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
        
        print("🎉 Fix applied! The trace_id parameter has been removed from the ChatHandler call.")
        
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"❌ Error applying fix: {e}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

if __name__ == "__main__":
    print("🔧 Applying simple fix for trace_id parameter issue...")
    success = simple_fix()
    if success:
        print("\n✅ Fix completed successfully!")
        print("The container should now work without restarting.")
        print("Test with: curl -X POST \"http://localhost:8003/chat\" -H \"Content-Type: application/json\" -d '{\"message\": \"Hello\", \"session_id\": \"test-123\"}'")
    else:
        print("\n❌ Fix failed!")