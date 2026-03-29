# Hajimi Team: BCR Project - Data Ingestion (GitHub Local Version)
# Author: Penghao Wang (Data Engineer)

from clearml import Task
import os

# 1. 初始化 ClearML 任务
task = Task.init(project_name="AI_Studio_Demo", task_name="Pipeline step 1 dataset artifact")

# 2. 指向本地数据集文件夹
local_dataset_path = './dataset'

# 3. 将文件夹作为 Artifact 上传给 ClearML 追踪
if os.path.exists(local_dataset_path):
    task.upload_artifact(name='bcr_raw_images', artifact_object=local_dataset_path)
    print(f'Successfully tracked local folder: {local_dataset_path}')
else:
    print(f'Error: Cannot find {local_dataset_path} folder!')

print('Uploading artifacts in the background...')
print('Done 🔥')