#!/usr/bin/env python3

import sys
import subprocess
import os
import re
import getpass

def read_multiline_input(prompt):
    """Read multiline input until empty line (just press Enter)"""
    print(prompt)
    print("Press Enter on an empty line when finished")
    print()
    
    lines = []
    while True:
        line = input()
        if line == "":  # Empty line = finished
            break
        lines.append(line)
    
    return '\n'.join(lines)

def get_api_key_from_log(log_file_path='es_startup.log'):
    """Extract API key from es_startup.log file"""
    try:
        if not os.path.exists(log_file_path):
            return None
        
        with open(log_file_path, 'r') as f:
            content = f.read()
        
        # Look for pattern: 🔑 API key: <key>
        match = re.search(r'🔑 API key:\s*([A-Za-z0-9+/=_-]+)', content)
        if match:
            return match.group(1)
        
        # Alternative pattern without emoji
        match = re.search(r'API key:\s*([A-Za-z0-9+/=_-]+)', content)
        if match:
            return match.group(1)
        
        return None
    except Exception as e:
        print(f"⚠️  Warning: Could not read {log_file_path}: {e}")
        return None

def get_api_key():
    """Get API key from log file, environment variable, or prompt user"""
    # Priority 1: Try to get from es_startup.log
    api_key = get_api_key_from_log()
    if api_key:
        print("\n✓ Using API key from es_startup.log")
        return api_key
    
    # Priority 2: Try to get from environment variable
    api_key = os.environ.get('ES_LOCAL_API_KEY')
    if api_key:
        print("\n✓ Using API key from $ES_LOCAL_API_KEY environment variable")
        return api_key
    
    # Priority 3: Prompt user
    print("\n⚠️  API key not found in es_startup.log or $ES_LOCAL_API_KEY")
    api_key = getpass.getpass("Please enter your Elasticsearch API key (input hidden): ")
    
    if not api_key:
        raise ValueError("API key cannot be empty")
    
    return api_key

def confirm_execution():
    """Ask user to confirm command execution"""
    while True:
        response = input("\nDo you want to execute this command? (y/n): ").strip().lower()
        if response in ['y', 'yes']:
            return True
        elif response in ['n', 'no']:
            return False
        else:
            print("Please enter 'y' or 'n'")

def execute_command(command):
    """Write command to file, upload to VM, and execute"""
    script_file = "autoops_docker_run.sh"
    try:
        # Extract container name from the docker command
        container_name = extract_container_name(command)
        
        # Fix the ES URL to always use localhost:9200
        command = fix_es_url(command)
        
        # Ensure host network is used
        command = ensure_host_network(command)
        
        # Ensure the command ends with a newline but doesn't have embedded issues
        command = command.strip()
        
        # Step 1: Write command to a local file
        print(f"\n📝 Writing command to {script_file}...")
        with open(script_file, 'w') as f:
            f.write("#!/bin/bash\n\n")
            f.write("set -e\n\n")  # Exit on error
            
            # Add container cleanup if name was found
            if container_name:
                # Use a simpler approach that avoids format string issues
                cleanup_script = f"""# Remove existing container if it exists
echo 'Checking for existing container: {container_name}'
if docker ps -a | grep -q '{container_name}'; then
    echo '🗑️  Found existing container: {container_name}'
    echo 'Stopping container...'
    docker stop {container_name} 2>/dev/null || true
    echo 'Removing container...'
    docker rm -f {container_name}
    echo '✓ Container removed successfully'
else
    echo '✓ No existing container found'
fi

"""
                f.write(cleanup_script)
            
            f.write("# Run the docker container\n")
            f.write("echo 'Starting new container...'\n")
            # Write the command - it should already have proper line continuations
            f.write(command)
            # Ensure it ends with a newline
            if not command.endswith('\n'):
                f.write("\n")
        
        # Make it executable
        os.chmod(script_file, 0o755)
        print(f"✓ Script file created: {script_file}")
        if container_name:
            print(f"✓ Added cleanup for existing container: {container_name}")
        
        # Step 2: Upload to VM
        print("\n📤 Uploading script to VM...")
        upload_result = subprocess.run(
            f"multipass transfer {script_file} autoops:/home/ubuntu/{script_file}",
            shell=True,
            check=True,
            capture_output=True,
            text=True
        )
        print("✓ Script uploaded to VM")
        
        # Step 3: Make executable on VM and execute
        print("\n🚀 Executing script on VM...")
        exec_result = subprocess.run(
            f"multipass exec autoops -- bash -c 'chmod +x /home/ubuntu/{script_file} && /home/ubuntu/{script_file}'",
            shell=True,
            check=True,
            capture_output=True,
            text=True
        )
        
        if exec_result.stdout:
            print("\nOutput:")
            print(exec_result.stdout)
        
        print("\n✓ Command executed successfully on VM!")
        
        # Clean up local file
        os.remove(script_file)
        print(f"✓ Cleaned up local {script_file}")
        
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"\n✗ Error: Command execution failed")
        print(f"Exit code: {e.returncode}")
        if e.stderr:
            print(f"Error output: {e.stderr}")
        
        # Keep the script file for debugging
        print(f"\n💾 Script file kept for debugging: {script_file}")
        print("You can inspect it to see what went wrong.")
        
        return False
    except Exception as e:
        print(f"\n✗ Error: {e}")
        if os.path.exists(script_file):
            print(f"\n💾 Script file kept for debugging: {script_file}")
        return False

def extract_container_name(command):
    """Extract container name from docker run command"""
    # Look for --name flag
    match = re.search(r'--name[=\s]+([^\s]+)', command)
    if match:
        return match.group(1)
    return None

def fix_es_url(command):
    """Ensure AUTOOPS_ES_URL is always set to http://localhost:9200"""
    # Pattern to match -e AUTOOPS_ES_URL with single quotes, double quotes, or no quotes
    # Match: -e AUTOOPS_ES_URL='anything' or -e AUTOOPS_ES_URL="anything" or -e AUTOOPS_ES_URL=value
    patterns = [
        (r"-e\s+AUTOOPS_ES_URL='[^']*'", "-e AUTOOPS_ES_URL='http://localhost:9200'"),  # Single quotes
        (r'-e\s+AUTOOPS_ES_URL="[^"]*"', "-e AUTOOPS_ES_URL='http://localhost:9200'"),  # Double quotes
        (r'-e\s+AUTOOPS_ES_URL=\S+', "-e AUTOOPS_ES_URL='http://localhost:9200'"),      # No quotes
    ]
    
    replaced = False
    for pattern, replacement in patterns:
        if re.search(pattern, command):
            command = re.sub(pattern, replacement, command)
            print("✓ Overriding AUTOOPS_ES_URL to http://localhost:9200")
            replaced = True
            break
    
    if not replaced:
        # Add it if it doesn't exist (insert after docker run)
        command = re.sub(
            r'(docker\s+run\s+)',
            r'\1-e AUTOOPS_ES_URL=\'http://localhost:9200\' ',
            command,
            count=1
        )
        print("✓ Adding AUTOOPS_ES_URL=http://localhost:9200")
    
    return command

def ensure_host_network(command):
    """Ensure docker command uses --network host"""
    # Check if --network or --net is already present
    if re.search(r'--network\s+\S+', command) or re.search(r'--net\s+\S+', command):
        # Replace existing network setting with host
        command = re.sub(r'--network\s+\S+', '--network host', command)
        command = re.sub(r'--net\s+\S+', '--network host', command)
        print("✓ Overriding network to host mode")
    else:
        # Add --network host if it doesn't exist (insert after docker run)
        command = re.sub(
            r'(docker\s+run\s+)',
            r'\1--network host ',
            command,
            count=1
        )
        print("✓ Adding --network host")
    
    return command

def main():
    print("=" * 60)
    print("AutoOps Agent Docker Run Script")
    print("=" * 60)
    print()
    
    # Read docker command
    docker_command = read_multiline_input(
        "Please paste the AutoOps agent docker run command:"
    )
    
    if not docker_command.strip():
        print("\n✗ Error: No command entered")
        sys.exit(1)
    
    print("\n✓ Command received!")
    
    # Check for placeholder and replace if found
    placeholder = "{{id:api_key}}"
    if placeholder in docker_command:
        print(f"\n⚠️  Detected placeholder '{placeholder}' in the command.")
        api_key = get_api_key()
        docker_command = docker_command.replace(placeholder, api_key)
        print("✓ Placeholder replaced with your API key.")
    
    print("\nThe following command will be executed:")
    print("=" * 60)
    print(docker_command)
    print("=" * 60)
    
    # Confirm and execute
    if confirm_execution():
        execute_command(docker_command)
    else:
        print("\n✗ Command execution cancelled by user")
        sys.exit(0)


if __name__ == "__main__":
    main()