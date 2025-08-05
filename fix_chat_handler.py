#!/usr/bin/env python3
"""
Quick fix for LLM orchestrator ChatHandler trace_id issue
"""

import os
import shutil

def fix_main_py():
    """Fix the main.py file to remove trace_id parameter"""
    main_py_path = "/Users/kg/IdeaProjects/llm-orchestrator-py/src/main.py"
    
    if not os.path.exists(main_py_path):
        print(f"❌ File not found: {main_py_path}")
        return False
    
    # Create backup
    backup_path = main_py_path + ".backup"
    shutil.copy2(main_py_path, backup_path)
    print(f"✅ Created backup: {backup_path}")
    
    # Read file
    with open(main_py_path, 'r') as f:
        content = f.read()
    
    # Fix the trace_id issue
    old_line = "    return await chat_handler.handle_chat_request(request, trace_id=trace_id)"
    new_line = "    return await chat_handler.handle_chat_request(request)"
    
    if old_line in content:
        content = content.replace(old_line, new_line)
        print("✅ Fixed trace_id parameter issue")
    else:
        print("⚠️ Old line not found, checking for variations...")
        # Check for the problematic line
        if "handle_chat_request(request, trace_id" in content:
            # Use regex replacement for more flexibility
            import re
            content = re.sub(
                r'return await chat_handler\.handle_chat_request\(request,\s*trace_id=\w+\)',
                'return await chat_handler.handle_chat_request(request)',
                content
            )
            print("✅ Fixed trace_id parameter with regex")
        else:
            print("❌ Could not find problematic line")
            return False
    
    # Write fixed file
    with open(main_py_path, 'w') as f:
        f.write(content)
    
    print(f"✅ Fixed {main_py_path}")
    return True

def rebuild_llm_orchestrator_image():
    """Rebuild the LLM orchestrator Docker image"""
    import subprocess
    
    try:
        # Change to the llm-orchestrator directory
        llm_dir = "/Users/kg/IdeaProjects/llm-orchestrator-py"
        
        print("🔨 Building new LLM orchestrator image...")
        result = subprocess.run([
            "docker", "build", "-t", "pyairtable-llm-orchestrator-fixed:latest", "."
        ], cwd=llm_dir, capture_output=True, text=True)
        
        if result.returncode == 0:
            print("✅ Successfully built fixed LLM orchestrator image")
            return True
        else:
            print(f"❌ Docker build failed: {result.stderr}")
            return False
            
    except Exception as e:
        print(f"❌ Error building image: {e}")
        return False

if __name__ == "__main__":
    print("🚀 Fixing LLM Orchestrator ChatHandler issue...")
    
    if fix_main_py():
        if rebuild_llm_orchestrator_image():
            print("\n✅ Fix completed successfully!")
            print("Now run: docker-compose -f docker-compose.frontend-test.yml up -d --force-recreate llm-orchestrator")
        else:
            print("\n❌ Image rebuild failed")
    else:
        print("\n❌ File fix failed")