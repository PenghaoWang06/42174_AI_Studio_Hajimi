# Hajimi Team: BCR Project - Image Preprocessing
# Author: Penghao Wang (Data Engineer)

from clearml import Task
import os
import cv2 # AWS 终端通常预装了 OpenCV

# 1. Initialize Task
task = Task.init(project_name="AI_Studio_Demo", task_name="Pipeline step 2 data preprocessing")

# 2. Configuration for Zhengyi's YOLOv8s model
# According to BCR.pptx, we need 1024x1024 resolution.
TARGET_SIZE = (1024, 1024)
input_folder = './dataset'
output_folder = './processed_dataset'

if not os.path.exists(output_folder):
    os.makedirs(output_folder)

print(f"Starting preprocessing: Resizing to {TARGET_SIZE}...")

# 3. Process each image
processed_count = 0
for file_name in os.listdir(input_folder):
    if file_name.lower().endswith(('.png', '.jpg', '.jpeg')):
        img_path = os.path.join(input_folder, file_name)
        img = cv2.imread(img_path)
        
        if img is not None:
            # Resize image to target resolution
            resized_img = cv2.resize(img, TARGET_SIZE)
            cv2.imwrite(os.path.join(output_folder, file_name), resized_img)
            processed_count += 1

# 4. Upload processed images to ClearML
task.upload_artifact(name='bcr_processed_images', artifact_object=output_folder)

print(f"Successfully processed {processed_count} images.")
print("Stage 2 Preprocessing Done 🔥")