# Hajimi Team: BCR Project - Environment Verification
# Author: Penghao Wang (Data Engineer)

from clearml import Task
import os

"""
INSTRUCTION FOR TEAM MEMBERS:
1. If you get 'ModuleNotFoundError', run: pip install clearml
2. If you get 'MissingConfigError', run: clearml-init
3. Paste your credentials from ClearML Web UI (Settings -> Workspace)
"""

def verify_connection():
    try:
        # Initialize a temporary task to verify credentials and connection
        print("Checking ClearML connection...")
        task = Task.init(
            project_name="Hajimi_Verification", 
            task_name="Environment Check",
            auto_connect_frameworks=False
        )
        
        # Check if the project is successfully linked
        print(f"Success! Connected to project: {task.project}")
        print("Your credentials are valid on this machine.")
        
        # Close the task immediately after verification
        task.close()
        return True
        
    except Exception as e:
        print(f"Connection Failed: {str(e)}")
        print("Please ensure you have run 'clearml-init' in the terminal.")
        return False

if __name__ == "__main__":
    if verify_connection():
        print("Ready for Data Pipeline Stage 1 🔥")