# Hajimi Team: BCR Project - Uploading data to ClearML
# Written by: Penghao Wang

from clearml import Task
import os

# Setup ClearML for project
task = Task.init(project_name="AI_Studio_Demo", task_name="Step 1 - Uploading dataset")

# Path to the folder with my images
local_dataset_path = './dataset'

# Upload the folder so we can see it on the ClearML dashboard
if os.path.exists(local_dataset_path):
    # This sends the folder to ClearML to keep track of it
    task.upload_artifact(name='bcr_raw_images', artifact_object=local_dataset_path)
    print(f'Done! Found the folder: {local_dataset_path}')
else:
    # Print an error if I messed up the folder path
    print(f'Wait, I cannot find the {local_dataset_path} folder!')

print('Uploading everything in the background...')
print('All done!')